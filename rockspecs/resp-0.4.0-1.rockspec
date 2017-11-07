package = "resp"
version = "0.4.0-1"
source = {
    url = "git://github.com/mah0x211/lua-resp.git",
    tag = "v0.4.0"
}
description = {
    summary = "RESP (REdis Serialization Protocol) parser",
    homepage = "https://github.com/mah0x211/lua-resp",
    license = "MIT/X11",
    maintainer = "Masatoshi Teruya"
}
dependencies = {
    "lua >= 5.1"
}
build = {
    type = "builtin",
    modules = {
        resp = "resp.lua"
    }
}

