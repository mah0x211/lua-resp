/*
 *  Copyright (C) 2017 Masatoshi Teruya
 *
 *  Permission is hereby granted, free of charge, to any person obtaining a
 *  copy of this software and associated documentation files (the "Software"),
 *  to deal in the Software without restriction, including without limitation
 *  the rights to use, copy, modify, merge, publish, distribute, sublicense,
 *  and/or sell copies of the Software, and to permit persons to whom the
 *  Software is furnished to do so, subject to the following conditions:
 *
 *  The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
 *  THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 *  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 *  DEALINGS IN THE SOFTWARE.
 *
 *  src/resp.c
 *  lua-resp
 *  Created by Masatoshi Teruya on 2017/11/06.
 *
 */
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <errno.h>
#include <ctype.h>
#include <lua.h>
#include <lauxhlib.h>


#define RESP_EAGAIN     -1
#define RESP_EILSEQ     -2
// 512 MB = 1024*1024*512
#define BSTR_MAXLEN     536870912
#define CR              '\r'
#define LF              '\n'


typedef struct {
    ssize_t len;
    ssize_t idx;
    void *prev;
} arraylist_t;


static inline ssize_t str2num( const char *msg, ssize_t head, int64_t *num )
{
    char *endptr = NULL;

    errno = 0;
    *num = (int64_t)strtoll( msg + head, &endptr, 10 );
    // illegal byte sequence
    if( errno == ERANGE ){
        return RESP_EILSEQ;
    }
    else if( endptr == ( msg + head ) )
    {
        // skip first sign byte
        switch( msg[head] ){
            case '-':
            case '+':
                head++;
                break;
        }
    }
    else {
        head = endptr - msg;
    }

    switch( msg[head] )
    {
        // found CR
        case CR:
            // found CRLF
            if( msg[head + 1] == LF ){
                return head + 2;
            }
            // need more bytes
            else if( !msg[head + 1] ){
        case 0:
                return RESP_EAGAIN;
            }
            // fallthrough

        // illegal byte sequence
        default:
            return RESP_EILSEQ;
    }
}


static inline ssize_t geteol( const char *msg, size_t len, ssize_t cur )
{
    for(; cur < len; cur++ )
    {
        switch( msg[cur] )
        {
            // found CR
            case CR:
                // found CRLF
                if( msg[cur + 1] == LF ){
                    return cur;
                }
                // need more bytes
                else if( !msg[cur + 1] ){
                    return RESP_EAGAIN;
                }
                // fallthrough

            // illegal byte sequence
            case LF:
                return RESP_EILSEQ;
        }
    }

    // need more bytes
    return RESP_EAGAIN;
}


static ssize_t decode2string( lua_State *L, const char *msg, size_t len,
                              ssize_t head )
{
    ssize_t cur = geteol( msg, len, head );

    if( cur > 0 ){
        lua_pushlstring( L, msg + head, cur - head );
        return cur + 2;
    }

    lua_settop( L, 0 );
    lua_pushinteger( L, cur );
    return cur;
}


static ssize_t decode2integer( lua_State *L, const char *msg, size_t len,
                               ssize_t head )
{
    int64_t num = 0;
    ssize_t cur = str2num( msg, head + 1, &num );

    if( cur > 0 ){
        lua_pushinteger( L, num );
        return cur;
    }

    lua_settop( L, 0 );
    lua_pushinteger( L, cur );
    return cur;
}


static ssize_t decode2bulkstring( lua_State *L, const char *msg, size_t len,
                                  ssize_t head )
{
    int64_t nbyte = 0;
    ssize_t cur = str2num( msg, head + 1, &nbyte );

    if( cur > 0 )
    {
        if( nbyte >= 0 )
        {
            if( ( len - cur ) >= ( nbyte + 2 ) )
            {
                head = cur;
                cur += nbyte;
                // found CRLF
                if( msg[cur] == CR && msg[cur + 1] == LF ){
                    lua_pushlstring( L, msg + head, nbyte );
                    return cur + 2;
                }
                // illegal byte sequence
                cur = RESP_EILSEQ;
            }
            // need more bytes
            else {
                cur = RESP_EAGAIN;
            }
        }
        // Null value
        else if( nbyte == -1 ){
            lua_pushnil( L );
            return cur;
        }
        // illegal byte sequence
        else {
            cur = RESP_EILSEQ;
        }
    }

    lua_settop( L, 0 );
    lua_pushinteger( L, cur );
    return cur;
}


static ssize_t decode2array( lua_State *L, const char *msg, size_t len,
                             ssize_t head, int64_t *narr )
{
    ssize_t cur = str2num( msg, head + 1, narr );

    if( cur > 0 )
    {
        if( *narr >= 0 ){
            lua_createtable( L, *narr, 0 );
            return cur;
        }
        // Null value
        else if( *narr == -1 ){
            lua_pushnil( L );
            return cur;
        }

        // illegal byte sequence
        cur = RESP_EILSEQ;
    }

    lua_settop( L, 0 );
    lua_pushinteger( L, cur );
    return cur;
}


static int decode_lua( lua_State *L )
{
    size_t len = 0;
    const char *msg = lauxh_checklstring( L, 1, &len );
    ssize_t head = lauxh_optuint64( L, 2, 0 );
    arraylist_t *arr = NULL;
    int64_t narr = 0;
    char type = msg[head];

    lua_settop( L, 1 );
    lua_pushnil( L );

PARSE_ELEMENT:
    switch( msg[head] ){
        // need more bytes
        case 0:
            lua_settop( L, 0 );
            lua_pushinteger( L, RESP_EAGAIN );
            return 1;

        // simplestrings
        case '+':
            head++;
        // errors
        case '-':
            if( ( head = decode2string( L, msg, len, head ) ) < 1 ){
                return 1;
            }
            break;

        // integers
        case ':':
            if( ( head = decode2integer( L, msg, len, head ) ) < 1 ){
                return 1;
            }
            break;

        // bulkstrings
        case '$':
            if( ( head = decode2bulkstring( L, msg, len, head ) ) < 1 ){
                return 1;
            }
            break;

        // arrays
        case '*':
            if( ( head = decode2array( L, msg, len, head, &narr ) ) < 1 ){
                return 1;
            }
            // not null or empty
            else if( narr > 0 ){
                arraylist_t *prev = arr;

                arr = lua_newuserdata( L, sizeof( arraylist_t ) );
                *arr = (arraylist_t){
                    .len = narr,
                    .idx = 0,
                    .prev = prev
                };
                goto PARSE_ELEMENT;
            }
            break;

        // illegal byte sequence
        default:
            lua_settop( L, 0 );
            lua_pushinteger( L, RESP_EILSEQ );
            return 1;
    }

    while( arr )
    {
        arr->idx++;
        lua_rawseti( L, -3, arr->idx );
        if( arr->idx < arr->len ){
            goto PARSE_ELEMENT;
        }
        arr = arr->prev;
        lua_pop( L, 1 );
    }

    lua_pushinteger( L, head );
    lua_replace( L, 2 );
    // push message type
    lua_pushinteger( L, type );

    return 3;
}


static inline void stackgrow( lua_State *stack, int slot )
{
    if( !lua_checkstack( stack, slot ) ){
        lua_concat( stack, lua_gettop( stack ) );
    }
}


static int encode2number( lua_State *L, int idx, lua_State *stack )
{
    lua_Number v = lua_tonumber( L, idx );
    lua_Integer iv = lua_tointeger( L, idx );

    stackgrow( stack, 1 );
    if( v == (lua_Number)iv ){
        lua_pushfstring( stack, ":%d\r\n", iv );
    }
    else {
        lua_pushfstring( stack, "+%f\r\n", v );
    }

    return 0;
}


static int encode2string( lua_State *L, int idx, lua_State *stack )
{
    size_t len = 0;
    const char *str = lua_tolstring( L, idx, &len );
    size_t cur = 0;
    int bulk = 1;

    if( len > BSTR_MAXLEN ){
        lua_settop( L, 0 );
        lua_pushnil( L );
        lua_pushstring( L, "string length must be up to 512 MB" );
        return -1;
    }

    switch( *str ){
        // simple strings
        case '+':
        case '-':
            cur++;
            if( cur < len ){
                bulk = 0;
            }
        // bulk string
        default:
            // check string value
            for(; cur < len; cur++ )
            {
                switch( str[cur] ){
                    case CR:
                    case LF:
                        lua_settop( L, 0 );
                        lua_pushnil( L );
                        lua_pushstring( L, "string cannot containe a CR or LF" );
                        return -1;
                }
            }

            if( bulk ){
                lua_pushfstring( stack, "$%d\r\n", len );
            }
            stackgrow( stack, 1 );
            lua_pushvalue( L, idx );
            lua_xmove( L, stack, 1 );
            lua_pushlstring( stack, "\r\n", 2 );
            return 0;
    }
}


static int encode2boolean( lua_State *L, int idx, lua_State *stack )
{
    stackgrow( stack, 1 );
    if( lua_toboolean( L, idx ) ){
        lua_pushlstring( stack, ":1\r\n", 4 );
    }
    else {
        lua_pushlstring( stack, ":0\r\n", 4 );
    }

    return 0;
}


static int encode2nil( lua_State *L, int idx, lua_State *stack )
{
    stackgrow( stack, 1 );
    lua_pushlstring( stack, "$-1\r\n", 5 );
    return 0;
}


static int encode2array( lua_State *L, int idx, lua_State *stack );


static int encode2value( lua_State *L, int idx, lua_State *stack )
{
    switch( lua_type( L, idx ) )
    {
        case LUA_TNIL:
            return encode2nil( L, idx, stack );

        case LUA_TBOOLEAN:
            return encode2boolean( L, idx, stack );

        case LUA_TSTRING:
            return encode2string( L, idx, stack );

        case LUA_TNUMBER:
            return encode2number( L, idx, stack );

        case LUA_TTABLE:
            return encode2array( L, idx, stack );

        default:
            lua_settop( L, 0 );
            lua_pushnil( L );
            lua_pushfstring( L, "could not encode a %s value",
                             lua_typename( L, lua_type( L, idx ) ) );
            return -1;
    }
}


static int encode2array( lua_State *L, int idx, lua_State *stack )
{
    size_t narr = lauxh_rawlen( L, idx );
    size_t i = 1;

    stackgrow( stack, 1 );
    // array length
    lua_pushfstring( stack, "*%d\r\n", narr );
    for(; i <= narr; i++ )
    {
        lua_rawgeti( L, idx, i );
        if( encode2value( L, lua_gettop( L ), stack ) != 0 ){
            return -1;
        }
        lua_pop( L, 1 );
    }

    return 0;
}


static int encode2array_lua( lua_State *L )
{
    int narg = lua_gettop( L );

    if( narg )
    {
        lua_State *stack = lua_newthread( L );
        int i = 1;

        // array length
        lua_pushfstring( stack, "*%d\r\n", narg );
        for(; i <= narg; i++ )
        {
            if( encode2value( L, i, stack ) != 0 ){
                return 2;
            }
        }

        lua_concat( stack, lua_gettop( stack ) );
        lua_settop( L, 0 );
        lua_xmove( stack, L, 1 );
    }
    else {
        lua_pushlstring( L, "", 0 );
    }

    return 1;
}


static int encode_lua( lua_State *L )
{
    int narg = lua_gettop( L );

    if( narg )
    {
        lua_State *stack = lua_newthread( L );

        if( narg > 1 )
        {
            int i = 1;

            // array length
            lua_pushfstring( stack, "*%d\r\n", narg );
            for(; i <= narg; i++ )
            {
                if( encode2value( L, i, stack ) != 0 ){
                    return 2;
                }
            }
        }
        else if( encode2value( L, 1, stack ) != 0 ){
            return 2;
        }

        lua_concat( stack, lua_gettop( stack ) );
        lua_settop( L, 0 );
        lua_xmove( stack, L, 1 );
    }
    else {
        lua_pushlstring( L, "", 0 );
    }

    return 1;
}


LUALIB_API int luaopen_resp( lua_State *L )
{
    struct luaL_Reg method[] = {
        { "encode", encode_lua },
        { "encode2array", encode2array_lua },
        { "decode", decode_lua },
        { NULL, NULL }
    };
    struct luaL_Reg *ptr = method;

    lua_newtable( L );
    do {
        lauxh_pushfn2tbl( L, ptr->name, ptr->func );
        ptr++;
    }while( ptr->name );

    // constants
    lauxh_pushint2tbl( L, "EAGAIN", RESP_EAGAIN );
    lauxh_pushint2tbl( L, "EILSEQ", RESP_EILSEQ );
    // decoded msg type
    // simplestrings
    lauxh_pushint2tbl( L, "STR", '+' );
    // errors
    lauxh_pushint2tbl( L, "ERR", '-' );
    // integers
    lauxh_pushint2tbl( L, "INT", ':' );
    // bulkstrings
    lauxh_pushint2tbl( L, "BLK", '$' );
    // arrays
    lauxh_pushint2tbl( L, "ARR", '*' );

    return 1;
}
