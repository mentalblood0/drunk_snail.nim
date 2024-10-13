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

proc rendered(line: Line, params: Table): string =
  var b = 0
  for e in line.expressions:
    if e.boundaries.a > 0: result &= line.source[b ..< e.boundaries.a]
    if e.operator == "param":
      if e.optional and not (e.name in params):
        continue
      result &= params[e.name]
    b = e.boundaries.b + 1
  if b != len(line.source)-1:
    result &= line.source[b .. ^1]

let parsed_line = new_line("one <!-- (param)p1 --> two <!-- (param)p2 --> three")
do_assert rendered(parsed_line, {"p1": "v1", "p2": "v2"}.toTable) == "one v1 two v2 three"
