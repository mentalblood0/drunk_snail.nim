import std/tables
import std/options

import regex

const open = "<!--"
const close = "-->"

const expression_regex = re2("(?P<open>" & open &
    r") *\((?P<operator>[A-Za-z]+)\)(?P<name>[A-Za-z0-9]+) *(?P<close>" &
    close & r")")

type Expression = tuple[boundaries: Slice[system.int], optional: bool,
    operator: string, name: string]
type Line = tuple[source: string, expressions: seq[Expression]]

proc new_line(line: string): Line =
  for m in find_all(line, expression_regex):
    result.expressions.add((boundaries: m.boundaries, optional: false,
        operator: line[m.group("operator")], name: line[m.group("name")]))
  result.source = line

template render_expression(i: int) =
  if e.boundaries.a > 0: result &= line.source[b ..< e.boundaries.a]
  if e.operator == "param":
    if e.optional and not (e.name in params):
      continue
    result &= params[e.name][i]

proc rendered(line: Line, params: Table): string =
  let max_len = block:
    var r = 0
    for i, e in line.expressions:
      let n = len(params[e.name])
      if r == 0 or n > r:
        r = n
    r
  var b = 0
  for i in 0 ..< max_len:
    if i != 0:
      result &= '\n'
    var b = 0
    for e in line.expressions:
      render_expression(i)
      b = e.boundaries.b + 1
    result &= line.source[b .. ^1]

proc test(line: string, params: Table, expect: string) =
  let r = rendered(new_line(line), params)
  if r != expect:
    echo "\"", r, "\" != \"", expect, "\""

test("one <!-- (param)p1 --> two <!-- (param)p2 --> three", {"p1": @["v1"],
    "p2": @["v2"]}.toTable, "one v1 two v2 three")
test("one <!-- (param)p1 --> two", {"p1": @["v1", "v2"]}.toTable, "one v1 two\none v2 two")

