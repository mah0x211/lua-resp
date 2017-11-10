# lua-resp

RESP (REdis Serialization Protocol) parser module.

**NOTE: this module is under heavy development.**

---

## resp module


```lua
local resp = require('resp')
```


## Status Constants

- `resp.EAGAIN`: Not enough data available.
- `resp.EILSEQ`: Found illegal byte sequence.


## Functions


### msg, err = resp.encode( ... )

encode messages.

**Parameters**

- `...`: messages of the following data types;
    - `nil`
    - `string`
    - `number`
    - `boolean`
    - `table (non-sparse array only)`

**Returns**

- `msg:string`: serialized message.
- `err:string`: error message.


### msg, err = resp.encode2array( ... )

encode messages as array.  
usually, this api use to encode a command message.

**Parameters and Returns**

same as [resp.encode API](#msg-err--respencode--)


### consumed, msg = resp.decode( str [, head] )

decode serialized message strings.

**Parameters**

- `str`: serialized message string.
- `head`: decode start position. (default `0`)

**Returns**

- `consumed:number`: greater than 0 on sucess, or [Status Constants](#status-constants).
- `msg:string, number or array`: decoded message.


---


## Example

```lua
local inspect = require'util'.inspect
local resp = require("resp")

local msg = resp.encode( 'HMSET', 'myhash', 'hello', '"world"' )
-- encoded to following string;
--  *4\r\n$5\r\nHMSET\r\n$6\r\nmyhash\r\n$5\r\nhello\r\n$7\r\n"world"\r\n


local consumed, data = resp.decode( msg )
-- consumed equal to 51
-- decoded to following table;
--  { [1] = "HMSET",
--    [2] = "myhash",
--    [3] = "hello",
--    [4] = "\"world\"",
--    len = 4 }


-- decode multiple-message
local mmsg = table.concat({msg, msg, msg})

consumed, data = resp.decode( mmsg )
while consumed > 0 do
    mmsg = string.sub( mmsg, consumed + 1 )
    consumed, data = resp.decode( mmsg )
end


-- use with head optional argument
mmsg = table.concat({msg, msg, msg})

consumed, data = resp.decode( mmsg )
while consumed > 0 do
    consumed, data = resp.decode( mmsg, consumed )
end
```

