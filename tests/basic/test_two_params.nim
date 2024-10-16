import std/json

import drunk_snail

assert rendered(
  new_template "one <!-- (param)p1 --> two <!-- (param)p2 --> three",
  %* {"p1": ["v1"], "p2": ["v2"]}) == "one v1 two v2 three"
