rockspec_format = "3.0"
package = "resp"
version = "scm-1"
source = {
    url = "git+https://github.com/mah0x211/lua-resp.git"
}
description = {
    summary = "RESP (REdis Serialization Protocol) parser",
    homepage = "https://github.com/mah0x211/lua-resp",
    license = "MIT/X11",
    maintainer = "Masatoshi Teruya"
}
dependencies = {
    "lua >= 5.1",
}
build = {
    type = "builtin",
    modules = {
        resp = {
            incdirs = { "deps/lauxhlib" },
            sources = { "src/resp.c" },
        }
    }
}

