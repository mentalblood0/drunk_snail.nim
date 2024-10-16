import std/json
import std/tables

import drunk_snail

assert rendered(
  new_template "one <!-- (ref)r --> two",
  %* {"r": [{"p": ["three"]}]},
  {"r": new_template "<!-- (param)p -->"}.to_table,
) == "one three two"

