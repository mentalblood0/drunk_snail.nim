import std/tables
import std/sequtils
import std/unittest
import std/sugar
import std/json
import std/strutils

import regex

const open = "<!--"
const close = "-->"

func expression_regex(operator: static string): auto =
  return re2(
    open & r" *(?P<optional>\(optional\))?\(" & operator &
    r"\)(?P<name>[A-Za-z0-9]+) *" &
      close
  )

const param_regex = expression_regex "param"
const ref_regex = expression_regex "ref"

type
  Expression = tuple[name: string, optional: bool]
  Bounds = tuple[left: string, right: string]

  ParamLineTokenKind = enum
    pltPlain
    pltParam

  ParamLineToken = ref ParamLineTokenObj
  ParamLineTokenObj = object
    case kind: ParamLineTokenKind
    of pltPlain:
      value: string
    of pltParam:
      expression: Expression

  LineKind = enum
    lPlain
    lParams
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

  ParseError* = object of ValueError
  RenderError* = object of ValueError

func new_expression(line: string, m: regex.RegexMatch2): Expression =
  return (name: line[m.group("name")], optional: len(line[m.group(
      "optional")]) > 0)

func new_bounds(line: string, m: regex.RegexMatch2): Bounds =
  (line[0 ..< m.boundaries.a], line[m.boundaries.b + 1 .. ^1])

func `&`(a: Bounds, b: Bounds): Bounds =
  (b.left & a.left, a.right & b.right)
func `&`(a: string, b: Bounds): string =
  b.left & a & b.right

func new_line(line: string): Line =
  let refs = find_all(line, ref_regex)
  let params = find_all(line, param_regex)
  if len(refs) > 1:
    raise new_exception(
      ParseError, "Line `" & line & "` contain more then one reference expressions"
    )
  if len(params) > 0 and len(refs) > 0:
    raise new_exception(
      ParseError, "Line `" & line & "` mixes parameters and references expressions"
    )

  if len(refs) > 0:
    let r = refs[0]
    return
      Line(kind: lRef, expression: new_expression(line, r), bounds: new_bounds(
          line, r))
  elif len(params) > 0:
    result = Line(kind: lParams)
    var b = 0
    for p in params:
      let plain = line[b ..< p.boundaries.a]
      if len(plain) > 0:
        result.tokens.add ParamLineToken(kind: pltPlain, value: plain)
      b = p.boundaries.b + 1
      result.tokens.add ParamLineToken(
        kind: pltParam, expression: new_expression(line, p)
      )
    let plain = line[b .. ^1]
    if len(plain) > 0:
      result.tokens.add ParamLineToken(kind: pltPlain, value: line[b .. ^1])
  else:
    return Line(kind: lPlain, value: line)

func rendered*(
  t: Template,
  params: JsonNode = %*{},
  templates: Templates = Templates(init_table[string, Template]()),
  bounds: Bounds = ("", ""),
): string

func rendered(
    line: Line, params: JsonNode, templates: Templates, external: Bounds
): string =
  if line.kind == lPlain:
    return line.value & external
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
              (not (e.name in params)) or (params[e.name].kind != JArray) or (
                  len(params[e.name].elems) == 0))
          ):
            result &= params[e.name].elems[i].str
      result &= external.right
  elif line.kind == lRef:
    let e = line.expression
    if (e.name in params) and (params[e.name].kind == JArray):
      for i, subparams in params[e.name].elems:
        if i != 0:
          result &= '\n'
        if not (e.optional and not (e.name in templates)):
          result &=
            rendered(templates[e.name], subparams, templates, line.bounds & external)
    else:
      if e.optional:
        return ""
      else:
        raise new_exception(
          RenderError,
          "Parameters for non-optional subtemplate `" & e.name &
          "` not provided",
        )

func new_template*(text: string): Template =
  for l in split_lines text:
    result.lines.add new_line l

func rendered*(
    t: Template,
    params: JsonNode = %*{},
    templates: Templates = Templates(init_table[string, Template]()),
    bounds: Bounds = ("", ""),
): string =
  for i, l in t.lines:
    if i != 0:
      result &= '\n'
    result &= rendered(l, params, templates, bounds)

when is_main_module:

  check rendered(
    new_template "one <!-- (ref)r --> two",
    %* {"r": [{}]},
    {"r": new_template("three")}.to_table,
  ) == "one three two"

  check rendered(
    new_template "<table>\n\t<!-- (ref)Row -->\n</table>",
    %* {"Row": [{"cell": ["1.1", "2.1"]}, {"cell": ["1.2", "2.2"]}]},
    {"Row": new_template "<tr>\n\t<td><!-- (param)cell --></td>\n</tr>"}.to_table,
  ) == "<table>\n\t<tr>\n\t\t<td>1.1</td>\n\t\t<td>2.1</td>\n\t</tr>\n\t<tr>\n\t\t<td>1.2</td>\n\t\t<td>2.2</td>\n\t</tr>\n</table>"

  check rendered(new_template "one <!-- (optional)(param)p1 --> two") == "one  two"

  check rendered(
    new_template "one <!-- (ref)r --> two",
    %* {"r": [{"p": ["three"]}]},
    {"r": new_template "<!-- (param)p -->"}.to_table,
  ) == "one three two"

  check rendered(new_template "one <!-- (param)p1 --> two", %* {"p1": ["v1",
    "v2"]}) == "one v1 two\none v2 two"

  check rendered(
    new_template "one <!-- (param)p1 --> two <!-- (param)p2 --> three",
    %* {"p1": ["v1"], "p2": ["v2"]}) == "one v1 two v2 three"

  check rendered(
    new_template "one <!-- (ref)r --> two",
    %* {"r": [{"p": ["three"]}, {"p": ["four"]}]},
    {"r": new_template "<!-- (param)p -->"}.to_table,
  ) == "one three two\none four two"

  check rendered(new_template "one <!-- (param)p1 --> two <!-- (param)p2 --> three",
      %*{"p1": ["v1", "v3"], "p2": ["v2", "v4", "v5"]}) == "one v1 two v2 three\none v3 two v4 three"

  const syntax* = (opening: open, close: close, optional: "(optional)",
      param: "(param)", `ref`: "(ref)")

  type TestLine* = ref object
    expression*: string
    name*: string
    bound_left*: string
    open_tag*: string = syntax.opening
    gap_left*: string
    flag*: string
    gap_right*: string
    close_tag*: string = syntax.close
    bound_right*: string

  func join*(l: TestLine): string = l.bound_left & l.open_tag & l.gap_left & l.flag &
          l.expression & l.name & l.gap_right & l.close_tag & l.bound_right

  const valid* = (other: ["", " ", "la"], gap: ["", " ", "  "], value: ["", "l",
      "la", "\n"], `ref`: [syntax.opening & syntax.param & "p" &
          syntax.close], one_line_params_number: [2, 3])

  const invalid* = (gap: ["l", "la"],
    open_tag: block: collect:
      for n in 1 .. len(syntax.opening):
        $syntax.opening[0 ..< n],
    close_tag: block: collect:
      for n in 1 .. len(syntax.close):
        $syntax.close[0 ..< n],
    name: ["1", "-", "1l"]
  )

  for value in valid.value:
    for bound_left in concat(@(valid.other), @[syntax.opening]):
      for gap_left in valid.gap:
        for gap_right in valid.gap:
          for bound_right in concat(@(valid.other), @[syntax.close]):
            let r = rendered(
              new_template TestLine(
                expression: syntax.param,
                name: "p",
                bound_left: bound_left,
                gap_left: gap_left,
                gap_right: gap_right,
                bound_right: bound_right
              ).join(),
              %* {"p": [value]}
            )
            check r == bound_left & value & bound_right

  for value in valid.value:
    for open_tag in invalid.open_tag:
      for bound_left in valid.other:
        for gap_left in invalid.gap:
          for name in invalid.name:
            for gap_right in invalid.gap:
              for bound_right in valid.other:
                for close_tag in invalid.close_tag:
                  let l = TestLine(
                    open_tag: open_tag,
                    bound_left: bound_left,
                    gap_left: gap_left,
                    name: name,
                    gap_right: gap_right,
                    bound_right: bound_right,
                    close_tag: close_tag
                  ).join()
                  let r = rendered(new_template l, %* {name: [value]})
                  check r == l

  for `ref` in valid.`ref`:
    for value in valid.value:
      for bound_left in valid.other:
        for gap_left in valid.gap:
          for gap_right in valid.gap:
            for bound_right in valid.other:
              let r = rendered(
                new_template TestLine(
                  expression: syntax.`ref`,
                  name: "R",
                  bound_left: bound_left,
                  gap_left: gap_left,
                  gap_right: gap_right,
                  bound_right: bound_right
                ).join(),
                %* {"R": [{"p": [value]}]},
                {"R": new_template `ref`}.to_table
              )
              check r == bound_left & value & bound_right
