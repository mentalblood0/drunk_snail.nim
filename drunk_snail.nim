import std/tables
import std/[times, os]
import std/strutils

import regex

const open = "<!--"
const close = "-->"

func expression_regex(operator: static string): auto =
  return re2(
    "(?P<open>" & open &
      r") *(?:\((?P<optional>optional)\))?\((?P<operator>" & operator &
    r")\)(?P<name>[A-Za-z0-9]+) *(?P<close>" &
      close & r")"
  )

const param_regex = expression_regex("param")
const ref_regex = expression_regex("ref")

type
  Expression = tuple[name: string, optional: bool]
  Bounds = tuple[left: string, right: string]

  ParamLineTokenKind = enum
    pltPlain,
    pltParam

  ParamLineToken = ref ParamLineTokenObj
  ParamLineTokenObj = object
    case kind: ParamLineTokenKind
    of pltPlain:
      value: string
    of pltParam:
      expression: Expression

  LineKind = enum
    lPlain,
    lParams,
    lRef

  Line = ref LineObj
  LineObj = object
    case kind: LineKind
    of lPlain:
      value: string
    of lParams:
      tokens: seq[ParamLineToken]
    of lRef:
      expression: Expression
      bounds: Bounds

  Template* = tuple[lines: seq[Line]]
  Templates* = Table[string, Template]

  Params* = Table[string, Value]
  ValueKind = enum
    vkValuesList
    vkParamsList

  Value = ref ValueObj
  ValueObj = object
    case kind: ValueKind
    of vkValuesList: values_list: seq[string]
    of vkParamsList: params_list: seq[Params]

  ParseError* = object of ValueError
  RenderError* = object of ValueError

func new_expression(line: string, m: regex.RegexMatch2): Expression =
  return (name: line[m.group("name")], optional: len(line[m.group(
      "optional")]) > 0)

func new_bounds(line: string, m: regex.RegexMatch2): Bounds = (line[0 ..<
    m.boundaries.a], line[m.boundaries.b + 1 .. ^1])

func `&`(a: Bounds, b: Bounds): Bounds = (b.left & a.left, a.right & b.right)

func values_list(l: seq[string]): Value =
  Value(kind: vkValuesList, values_list: l)

func params_list(l: seq[Params]): Value =
  Value(kind: vkParamsList, params_list: l)

func len(v: Value): int =
  if v.kind == vkValuesList:
    return len(v.values_list)
  if v.kind == vkParamsList:
    return len(v.params_list)

func new_line(line: string): Line =
  let refs = find_all(line, ref_regex)
  let params = find_all(line, param_regex)
  if len(refs) > 1:
    raise new_exception(ParseError, "Line `" & line & "` contain more then one reference expressions")
  if len(params) > 0 and len(refs) > 0:
    raise new_exception(ParseError, "Line `" & line & "` mixes parameters and references expressions")

  if len(refs) > 0:
    let r = refs[0]
    return Line(kind: lRef, expression: new_expression(line, r),
        bounds: new_bounds(line, r))
  elif len(params) > 0:
    result = Line(kind: lParams)
    var b = 0
    for p in params:
      let plain = line[b ..< p.boundaries.a]
      if len(plain) > 0:
        result.tokens.add ParamLineToken(kind: pltPlain, value: plain)
      b = p.boundaries.b + 1
      result.tokens.add ParamLineToken(kind: pltParam,
          expression: new_expression(line, p))
    let plain = line[b .. ^1]
    if len(plain) > 0:
      result.tokens.add ParamLineToken(kind: pltPlain, value: line[b .. ^1])
  else:
    return Line(kind: lPlain, value: line)

func rendered*(
  t: Template,
  params: Params = Params(init_table[string, Value]()),
  templates: Templates = Templates(init_table[string, Template]()),
  bounds: Bounds = ("", "")
): string

func rendered(
    line: Line, params: Params, templates: Templates, external: Bounds
): string =

  if line.kind == lPlain:
    return external.left & line.value & external.right

  elif line.kind == lParams:
    let min_len = block:
      var r = 1
      for t in line.tokens:
        if t.kind == pltParam:
          let e = t.expression
          if e.optional or not (e.name in params):
            continue
          let n = len(params[e.name])
          if r == 1 or n < r:
            r = n
      r
    for i in 0 ..< min_len:
      if i != 0:
        result &= '\n'
      result &= external.left
      for t in line.tokens:
        if t.kind == pltPlain:
          result &= t.value
        elif t.kind == pltParam:
          let e = t.expression
          if not (
            e.optional and (
              (not (e.name in params)) or (len(params[e.name]) == 0) or
              (params[e.name].kind != vkValuesList)
            )
          ):
            result &= params[e.name].values_list[i]
      result &= external.right

  elif line.kind == lRef:
    let e = line.expression
    if (e.name in params) and (params[e.name].kind == vkParamsList):
      for i, subparams in params[e.name].params_list:
        if i != 0:
          result &= '\n'
        if not (e.optional and not (e.name in templates)):
          result &= rendered(templates[e.name], subparams, templates,
              line.bounds & external)
    else:
      if e.optional: return ""
      else: raise new_exception(RenderError,
          "Parameters for non-optional subtemplate `" & e.name & "` not provided")

func new_template(text: string): Template =
  for l in split_lines text:
    result.lines.add new_line l

func rendered*(
    t: Template,
    params: Params = Params(init_table[string, Value]()),
    templates: Templates = Templates(init_table[string, Template]()),
    bounds: Bounds = ("", "")
): string =
  for i, l in t.lines:
    if i != 0:
      result &= '\n'
    result &= rendered(l, params, templates, bounds)

# proc test(
#     t: string,
#     expect: string,
#     params: Params = Params(init_table[string, Value]()),
#     templates: Templates = Templates(init_table[string, Template]()),
# ) =
#   let r = rendered(new_template t, params, templates)
#   if r != expect:
#     echo "\"", r, "\" != \"", expect, "\""
#
# test(
#   "one <!-- (param)p1 --> two <!-- (param)p2 --> three",
#   "one v1 two v2 three",
#   {"p1": values_list @["v1"], "p2": values_list @["v2"]}.to_table,
# )
# test(
#   "one <!-- (param)p1 --> two",
#   "one v1 two\none v2 two",
#   {"p1": values_list @["v1", "v2"]}.to_table,
# )
# test(
#   "one <!-- (param)p1 --> two <!-- (param)p2 --> three",
#   "one v1 two v2 three\none v3 two v4 three",
#   {"p1": values_list @["v1", "v3"], "p2": values_list @["v2", "v4",
#       "v5"]}.to_table,
# )
# test("one <!-- (optional)(param)p1 --> two", "one  two")
# test(
#   "one <!-- (ref)r --> two",
#   "one three two",
#   {"r": params_list @[init_table[string, Value]()]}.to_table,
#   {"r": new_template("three")}.to_table,
# )
# test(
#   "one <!-- (ref)r --> two",
#   "one three two",
#   {"r": params_list @[{"p": values_list @["three"]}.to_table]}.to_table,
#   {"r": new_template "<!-- (param)p -->"}.to_table,
# )
# test(
#   "one <!-- (ref)r --> two",
#   "one three two\none four two",
#   {"r": params_list @[{"p": values_list @["three"]}.to_table, {
#       "p": values_list @["four"]}.to_table]}.to_table,
#   {"r": new_template "<!-- (param)p -->"}.to_table,
# )
# test(
#   "<table>\n\t<!-- (ref)Row -->\n</table>",
#   "<table>\n\t<tr>\n\t\t<td>1.1</td>\n\t\t<td>2.1</td>\n\t</tr>\n\t<tr>\n\t\t<td>1.2</td>\n\t\t<td>2.2</td>\n\t</tr>\n</table>",
#   {"Row": params_list @[{"cell": values_list @["1.1", "2.1"]}.to_table, {
#       "cell": values_list @["1.2", "2.2"]}.to_table]}.to_table,
#   {"Row": new_template "<tr>\n\t<td><!-- (param)cell --></td>\n</tr>"}.to_table,
# )

let table = new_template "<table>\n\t<!-- (ref)Row -->\n</table>"
let templates = {"Row": new_template "<tr>\n\t<td><!-- (param)cell --></td>\n</tr>"}.to_table

proc benchmark_table(size: int, n: int) =

  let params = block:
    var r = {"Row": params_list @[]}.to_table
    for y in 0 .. size:
      var rc = {"cell": values_list @[]}.to_table
      for x in 0 .. size:
        rc["cell"].values_list.add $(x + y * size)
      r["Row"].params_list.add rc
    r

  let start_time = cpu_time()
  for i in 0 ..< n:
    discard rendered(table, params, templates)
  let end_time = cpu_time()
  echo "rendered " & $size & "x" & $size & " table in " & $(
      (end_time - start_time) / n.float) & " seconds"

benchmark_table(100, 100)
