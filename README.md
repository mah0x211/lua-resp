# lua-resp

RESP (REdis Serialization Protocol) parser module.

**NOTE: this module is under heavy development.**

---

## resp module


```lua
local RESP = require('resp')
```


## Status Constants

- `RESP.OK`: Serialized message has been decoded.
- `RESP.EAGAIN`: Please add more serialized message chunk and try again.
- `RESP.EILSEQ`: Found illegal byte sequence.


## Create a RESP Object.

### r = RESP.new()

returns a new `RESP` object.

**Returns**

- `r:RESP`: RESP object.


## RESP Methods


### msg = r:encode( ... )

encode messages.

**Parameters**

- `...`: messages of the following data types;
    - `string`
    - `number`
    - `boolean`
    - `table (non-sparse array only)`

**Returns**

- `msg:string`: serialized message.


### status, msg, extra = r:decode( [str] )

decode serialized message strings.

**Parameters**

- `str`: serialized message string.

**Returns**

- `status:number`: [Status Constants](#status-constants).
- `msg:string, number or array`: decoded message.
- `extra:string`: extra strings if exists.


---


## Example

```lua
local RESP = require("resp")
local r = RESP.new()
local status, msg

msg = r:encode( 'HMSET', 'myhash', 'hello', '"world"' )
-- encoded to following string;
--  *4\r\n$5\r\nHMSET\r\n$6\r\nmyhash\r\n$5\r\nhello\r\n$7\r\n"world"\r\n

status, msg = r:decode( msg )
-- status equal to RESP.OK
-- decoded to following table;
--  { [1] = "HMSET",
--    [2] = "myhash",
--    [3] = "hello",
--    [4] = "\"world\"",
--    len = 4 }
```

