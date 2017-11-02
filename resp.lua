--[[

  Copyright (C) 2017 Masatoshi Teruya

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
  THE SOFTWARE.

  resp.lua
  lua-resp
  Created by Masatoshi Teruya on 17/06/30.

--]]

--- assign to local
local select = select;
local type = type;
local floor = math.floor;
local setmetatable = setmetatable;
local tostring = tostring;
local tonumber = tonumber;
local concat = table.concat;
local strfind = string.find;
local strsub = string.sub;
local strbyte = string.byte;
--- constants
local INF_P = math.huge;
local INF_N = -INF_P;
local CR = strbyte('\r');
local LF = strbyte('\n');
--- status constants
local OK = 0;
local EAGAIN = 35;
local EILSEQ = 92;


--- isint
-- @param v
-- @return ok
local function isint( v )
    return v < INF_P and v > INF_N and floor( v ) == v;
end


--- getpos
-- @param r
-- @return rc
-- @return pos
local function getpos( r )
    local msg = r.msg;
    local pos = strfind( msg, '[\r\n]+', r.cur );

    -- not found
    if not pos then
        r.cur = #msg;
    -- found illegal byte sequence
    elseif strbyte( msg, pos ) ~= CR then
        r.cur = pos;
        return EILSEQ;
    -- reached to eol
    elseif pos == #msg then
        r.cur = pos - 1;
    -- found LF
    elseif strbyte( msg, pos + 1 ) == LF then
        r.cur = pos + 2;
        return OK, pos - 1;
    -- found illegal byte sequence
    else
        r.cur = pos;
        return EILSEQ;
    end

    return EAGAIN;
end


--- getline
-- @param r
-- @return rc
-- @return line
local function getline( r )
    local rc, pos = getpos( r );
    local line;

    if rc == OK then
        local msg = r.msg;

        line = strsub( msg, 1, pos );
        r.msg = strsub( msg, r.cur );
        r.cur = 1;
    end

    return rc, line;
end


--- simplestrings
-- @param r
-- @return rc
-- @return str
local function simplestrings( r )
    return getline( r );
end


--- errors
-- @param r
-- @return rc
-- @return err
-- @return msg
local function errors( r )
    local rc, err = getline( r );

    if rc == OK then
        local head, tail = strfind( err, '[%s]+' );

        -- found deliminters
        if head then
            return OK, strsub( err, 1, head - 1 ), strsub( err, tail + 1 );
        end

        return OK, err;
    end

    return rc;
end


--- integers
-- @param r
-- @return rc
-- @return val
local function integers( r )
    local rc, val = getline( r );

    if rc == OK then
        val = strfind( val, '^-*[0-9]+$' ) and tonumber( val );
        return val and OK or EILSEQ, val;
    end

    return rc;
end


--- bulkstrings
-- @param r
-- @return rc
-- @return str
local function bulkstrings( r )
    -- parse byte length of bulk-strings
    if not r.byte then
        local rc, nbyte = integers( r );

        -- got error
        if rc ~= OK then
            return rc;
        -- Null Bulk String
        elseif nbyte == -1 then
            return OK;
        end

        r.nbyte = nbyte;
    end

    -- need more bytes
    if ( #r.msg - r.nbyte ) < 2 then
        return EAGAIN;
    -- found line-terminator
    elseif strbyte( r.msg, r.nbyte + 1 ) == CR and
           strbyte( r.msg, r.nbyte + 2 ) == LF then
        local nbyte = r.nbyte;
        local msg = r.msg;

        -- extract a bulk strings
        r.msg = strsub( msg, nbyte + 3 );
        r.nbyte = nil;

        return OK, strsub( msg, 1, nbyte );
    end

    -- found illegal byte sequence
    return EILSEQ;
end


--- arrays
-- @param r
-- @param val
-- @return rc
-- @return arr
local function arrays( r )
    -- parse array length
    local rc, len = integers( r );

    -- got error
    if rc ~= OK then
        return rc;
    -- Null Array
    elseif len == -1 then
        return OK;
    -- Empty Array
    elseif len == 0 then
        return OK, {};
    -- save current array context
    elseif r.arr then
        r.narr = r.narr + 1;
        r.arrs[r.narr] = {
            arr = r.arr,
            idx = r.idx
        };
    end

    -- create arrays properties
    r.arr = {
        len = len
    };
    r.idx = 0;
    -- parse values
    r.handler = nil;

    return r:decode();
end


--- handlers
local HANDLERS_LUT = {
    ['+'] = simplestrings,
    ['-'] = errors,
    [':'] = integers,
    ['$'] = bulkstrings,
    ['*'] = arrays
};


--- class RESP
local RESP = {};


--- decode
-- @param msg
-- @return rc
-- @return val
-- @return extra
function RESP:decode( msg )
    local handler = self.handler;
    local rc, val, extra;

    -- append new message chunk
    if msg then
        self.msg = self.msg .. msg;
    end

    -- select handler
    if not handler then
        -- ignore empty-message
        if #self.msg == 0 then
            return EAGAIN;
        end

        handler = HANDLERS_LUT[strsub( self.msg, 1, 1 )];
        if not handler then
            self.msg = '';
            self.prev = nil;
            return EILSEQ;
        -- remove prefix if not simple-strings or error-strings
        elseif handler ~= simplestrings and handler ~= errors then
            self.msg = strsub( self.msg, 2 );
        end

        self.handler = handler;
    end

    rc, val, extra = handler( self );
    if rc == EAGAIN then
        return EAGAIN;
    end

    self.handler = nil;
    if rc ~= OK then
        return rc;
    elseif not self.arr then
        return OK, val, extra;
    end

    self.idx = self.idx + 1;
    self.arr[self.idx] = val;

    -- context in arrays parser
    -- finish arrays
    while self.idx == self.arr.len do
        local ctx;

        val = self.arr;
        -- return arrays
        if self.narr == 0 then
            self.arr = nil;
            self.idx = nil;
            return OK, val;
        end

        -- select parent arrays
        ctx = self.arrs[self.narr];
        -- pop
        self.arrs[self.narr] = nil;
        self.narr = self.narr - 1;

        -- update arrays context
        self.arr = ctx.arr;
        self.idx = ctx.idx;

        -- add val to parent array
        self.idx = self.idx + 1;
        self.arr[self.idx] = val;
    end

    return self:decode();
end


local encode2array;

--- encode2value
-- @param val
-- @return msg
local function encode2value( val )
    local t = type( val );

    if t == 'string' then
        -- simple strings
        if strfind( val, '^[+-]' ) then
            return val;
        end

        return '$' .. #val .. '\r\n' .. val;
    elseif t == 'number' then
        if isint( val ) then
            return ':' .. tostring( val );
        end

        val = tostring( val );
        return '$' .. #val .. '\r\n' .. val;
    elseif t == 'boolean' then
        return '$1\r\n' .. ( val and '1' or '0' );
    elseif t == 'table' then
        return encode2array( #val, val );
    elseif val == nil then
        return '$-1';
    else
        error( 'invalid argument ' .. t );
    end
end


--- encode2array
-- @param narg
-- @param argv
-- @return msg
encode2array = function( narg, argv )
    local arr = {
        -- array length
        '*' .. narg
    };
    local idx = 2;

    -- encode command
    for i = 1, narg do
        arr[idx] = encode2value( argv[i] );
        idx = idx + 1;
    end

    return concat( arr, '\r\n' );
end


--- encodeReply
-- @param ...
-- @return msg
local function encodeReply( ... )
    local narg = select( '#', ... );

    if narg > 1 then
        return encode2array( narg, { ... } ) .. '\r\n';
    end

    return encode2value( ... ) .. '\r\n';
end


--- encodeCommand
-- @param ...
-- @return msg
local function encodeCommand( ... )
    return encode2array( select( '#', ... ), { ... } ) .. '\r\n';
end


--- new
-- @return r
local function new()
    return setmetatable({
        msg = '',
        cur = 1,
        arrs = {},
        narr = 0
    }, {
        __index = RESP
    })
end


return {
    new = new,
    encodeReply = encodeReply,
    encodeCommand = encodeCommand,
    OK = OK,
    EAGAIN = EAGAIN,
    EILSEQ = EILSEQ
};
