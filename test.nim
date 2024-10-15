import std/tables

import drunk_snail

proc test(
    t: string,
    expect: string,
    params: drunk_snail.Params = Params(init_table[string, drunk_snail.Value]()),
    templates: drunk_snail.Templates =
      drunk_snail.Templates(init_table[string, drunk_snail.Template]()),
) =
  let r = rendered(new_template t, params, templates)
  if r != expect:
    echo "\"", r, "\" != \"", expect, "\""

test(
  "one <!-- (param)p1 --> two <!-- (param)p2 --> three",
  "one v1 two v2 three",
  {"p1": drunk_snail.values_list @["v1"], "p2": drunk_snail.values_list @["v2"]}.to_table,
)
test(
  "one <!-- (param)p1 --> two",
  "one v1 two\none v2 two",
  {"p1": values_list @["v1", "v2"]}.to_table,
)
test(
  "one <!-- (param)p1 --> two <!-- (param)p2 --> three",
  "one v1 two v2 three\none v3 two v4 three",
  {"p1": values_list @["v1", "v3"], "p2": values_list @["v2", "v4", "v5"]}.to_table,
)
test("one <!-- (optional)(param)p1 --> two", "one  two")
test(
  "one <!-- (ref)r --> two",
  "one three two",
  {"r": params_list @[init_table[string, Value]()]}.to_table,
  {"r": new_template("three")}.to_table,
)
test(
  "one <!-- (ref)r --> two",
  "one three two",
  {"r": params_list @[{"p": values_list @["three"]}.to_table]}.to_table,
  {"r": new_template "<!-- (param)p -->"}.to_table,
)
test(
  "one <!-- (ref)r --> two",
  "one three two\none four two",
  {
    "r": params_list @[
      {"p": values_list @["three"]}.to_table, {"p": values_list @["four"]}.to_table
    ]
  }.to_table,
  {"r": new_template "<!-- (param)p -->"}.to_table,
)
test(
  "<table>\n\t<!-- (ref)Row -->\n</table>",
  "<table>\n\t<tr>\n\t\t<td>1.1</td>\n\t\t<td>2.1</td>\n\t</tr>\n\t<tr>\n\t\t<td>1.2</td>\n\t\t<td>2.2</td>\n\t</tr>\n</table>",
  {
    "Row": params_list @[
      {"cell": values_list @["1.1", "2.1"]}.to_table,
      {"cell": values_list @["1.2", "2.2"]}.to_table,
    ]
  }.to_table,
  {"Row": new_template "<tr>\n\t<td><!-- (param)cell --></td>\n</tr>"}.to_table,
)
