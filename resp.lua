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

--- status constants
local OK = 0;
local EAGAIN = 35;
local EILSEQ = 92;


--- getpos
-- @param r
-- @return rc
-- @return pos
local function getpos( r )
    local msg = r.msg;
    local pos = msg:find( '[\r\n]+', r.cur );

    -- not found
    if not pos then
        r.cur = #msg;
    -- found illegal byte sequence
    elseif msg:sub( pos, pos ) ~= '\r' then
        r.cur = pos;
        return EILSEQ;
    -- reached to eol
    elseif pos == #msg then
        r.cur = pos - 1;
    -- found LF
    elseif msg:sub( pos + 1, pos + 1 ) == '\n' then
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

        line = msg:sub( 1, pos );
        r.msg = msg:sub( r.cur );
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
        local head, tail = err:find('[%s]+');

        -- found deliminters
        if head then
            return OK, err:sub( 1, head - 1 ), err:sub( tail + 1 );
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
        val = val:find('^-*[0-9]+$') and tonumber( val );
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
    elseif r.msg:sub( r.nbyte + 1, r.nbyte + 2 ) == '\r\n' then
        local nbyte = r.nbyte;
        local msg = r.msg;

        -- extract a bulk strings
        r.msg = msg:sub( nbyte + 3 );
        r.nbyte = nil;

        return OK, msg:sub( 1, nbyte );
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

    return r:parse();
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


--- parse
-- @param msg
-- @return rc
-- @return val
function RESP:parse( msg )
    local handler = self.handler;
    local rc, val, extra;

    -- append new message chunk
    if msg then
        self.msg = self.msg .. msg;
    end

    -- select handler
    if not handler then
        handler = HANDLERS_LUT[self.msg:sub( 1, 1 )];
        if not handler then
            self.msg = '';
            self.prev = nil;
            return EILSEQ;
        end

        self.handler = handler;
        self.msg = self.msg:sub( 2 );
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

    return self:parse();
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
    OK = OK,
    EAGAIN = EAGAIN,
    EILSEQ = EILSEQ
};
