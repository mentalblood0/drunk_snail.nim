import std/tables
import std/strutils
import std/options

import regex

const open = "<!--"
const close = "-->"

const expression_regex = re2("(?P<open>" & open &
    r") *(?:\((?P<optional>optional)\))?\((?P<operator>[A-Za-z]+)\)(?P<name>[A-Za-z0-9]+) *(?P<close>" &
    close & r")")

type Expression = tuple[boundaries: Slice[system.int], optional: bool,
    operator: string, name: string]
type Line = tuple[source: string, expressions: seq[Expression]]
type Template* = tuple[lines: seq[Line]]
type Params* = Table[string, seq[string]]
type Templates* = Table[string, Template]

proc new_line(line: string): Line =
  for m in find_all(line, expression_regex):
    result.expressions.add((boundaries: m.boundaries, optional: len(line[
        m.group("optional")]) > 0, operator: line[m.group("operator")],
            name: line[m.group("name")]))
  result.source = line

proc rendered*(t: Template, params: Params = Params(init_table[string, seq[
    string]]()), templates: Templates = Templates(init_table[string,
        Template]())): string

proc rendered(line: Line, params: Params, templates: Templates): string =
  let min_len = block:
    var r = 1
    for i, e in line.expressions:
      if e.optional or not (e.name in params):
        continue
      if e.operator == "template":
        r = 0
        break
      let n = len(params[e.name])
      if r == 1 or n < r:
        r = n
    r
  for i in 0 ..< min_len:
    if i != 0:
      result &= '\n'
    var b = 0
    for e in line.expressions:
      if e.boundaries.a > 0: result &= line.source[b ..< e.boundaries.a]
      if e.operator == "param":
        if not (e.optional and ((not (e.name in params)) or (len(params[
            e.name]) == 0))):
          result &= params[e.name][i]
      elif e.operator == "ref":
        if not (e.optional and not (e.name in templates)):
          result &= rendered(templates[e.name], params, templates)
      b = e.boundaries.b + 1
    result &= line.source[b .. ^1]

proc new_template(text: string): Template =
  for l in split_lines text:
    result.lines.add new_line l

proc rendered*(t: Template, params: Params = Params(init_table[string, seq[
    string]]()), templates: Templates = Templates(init_table[string,
        Template]())): string =
  for i, l in t.lines:
    if i != 0:
      result &= '\n'
    result &= rendered(l, params, templates)

proc test(t: string, expect: string, params: Params = Params(init_table[string,
    seq[string]]()), templates: Templates = Templates(init_table[string,
        Template]())) =
  let r = rendered(new_template t, params, templates)
  if r != expect:
    echo "\"", r, "\" != \"", expect, "\""

test("one <!-- (param)p1 --> two <!-- (param)p2 --> three",
    "one v1 two v2 three", {"p1": @["v1"], "p2": @["v2"]}.to_table)
test("one <!-- (param)p1 --> two", "one v1 two\none v2 two", {"p1": @["v1",
    "v2"]}.to_table)
test("one <!-- (param)p1 --> two <!-- (param)p2 --> three",
    "one v1 two v2 three\none v3 two v4 three", {"p1": @["v1", "v3"], "p2": @[
        "v2", "v4", "v5"]}.to_table)
test("one <!-- (optional)(param)p1 --> two", "one  two")
test("one <!-- (ref)r --> two", "one three two", templates = {"r": new_template(
    "three")}.to_table)
