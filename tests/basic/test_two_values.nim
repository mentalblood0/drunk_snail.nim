import std/json

import drunk_snail

assert rendered(new_template "one <!-- (param)p1 --> two", %* {"p1": ["v1",
    "v2"]}) == "one v1 two\none v2 two"
