import std/json
import std/tables

import drunk_snail

assert rendered(
  new_template "one <!-- (ref)r --> two",
  %* {"r": [{"p": ["three"]}, {"p": ["four"]}]},
  {"r": new_template "<!-- (param)p -->"}.to_table,
) == "one three two\none four two"
