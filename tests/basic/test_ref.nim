import std/json
import std/tables

import drunk_snail

assert rendered(
  new_template "one <!-- (ref)r --> two",
  %* {"r": [{}]},
  {"r": new_template("three")}.to_table,
) == "one three two"

