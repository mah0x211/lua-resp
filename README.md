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


### consumed, msg = resp.decode( str )

decode serialized message strings.

**Parameters**

- `str`: serialized message string.

**Returns**

- `consumed:number`: greater than 0 on sucess, or [Status Constants](#status-constants).
- `msg:string, number or array`: decoded message.


---


## Example

```lua
local resp = require("resp")
local data = resp.encode( 'HMSET', 'myhash', 'hello', '"world"' )
-- encoded to following string;
--  *4\r\n$5\r\nHMSET\r\n$6\r\nmyhash\r\n$5\r\nhello\r\n$7\r\n"world"\r\n

local consumed, msg = resp.decode( data )
-- consumed equal to 51
-- decoded to following table;
--  { [1] = "HMSET",
--    [2] = "myhash",
--    [3] = "hello",
--    [4] = "\"world\"",
--    len = 4 }
```

