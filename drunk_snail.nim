# Regular expression support is provided by the PCRE library package,
# which is open source software, written by Philip Hazel, and copyright
# by the University of Cambridge, England. Source can be found at
# ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/

import std/tables
import std/times
import std/sequtils
import std/unittest
import std/sugar
import std/json
import std/strutils
import std/nre

type
  Parser* =
    tuple[
      open: string,
      close: string,
      param: string,
      `ref`: string,
      optional: string,
      param_regex: Regex,
      ref_regex: Regex,
    ]
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

func expression_regex(
    open: string, operator: string, close: string, optional: string
): auto =
  return re(
    escape_re(open) & r" *(?P<optional>\(" & escape_re(optional) & r"\))?\(" &
      escape_re(operator) & r"\)(?P<name>[A-Za-z0-9]+) *" & escape_re(close)
  )

func new_parser*(
    open: string = "<!--",
    close: string = "-->",
    param: string = "param",
    `ref`: string = "ref",
    optional: string = "optional",
): Parser =
  (
    open,
    close,
    param,
    `ref`,
    optional,
    expression_regex(open, param, close, optional),
    expression_regex(open, `ref`, close, optional),
  )

func new_expression(line: string, m: RegexMatch): Expression =
  return (name: m.captures["name"], optional: "optional" in m.captures)

func new_bounds(line: string, m: RegexMatch): Bounds =
  (line[0 ..< m.match_bounds.a], line[m.match_bounds.b + 1 .. ^1])

func `&`(a: Bounds, b: Bounds): Bounds =
  (b.left & a.left, a.right & b.right)
func `&`(a: string, b: Bounds): string =
  b.left & a & b.right

func new_line(parser: Parser, line: string): Line =
  let refs = collect(
    for m in line.find_iter(parser.ref_regex):
      m
  )
  let params = collect(
    for m in line.find_iter(parser.param_regex):
      m
  )
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
      Line(kind: lRef, expression: new_expression(line, r), bounds: new_bounds(line, r))
  elif len(params) > 0:
    result = Line(kind: lParams)
    var b = 0
    for p in params:
      let plain = line[b ..< p.match_bounds.a]
      if len(plain) > 0:
        result.tokens.add ParamLineToken(kind: pltPlain, value: plain)
      b = p.match_bounds.b + 1
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
          let n = block:
            if params[e.name].kind == JArray:
              len(params[e.name])
            elif params[e.name].kind == JString:
              1
            else:
              0
          if r == 1 or n < r:
            r = n
          if r == 0:
            break
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
              (not (e.name in params)) or
              (params[e.name].kind != JArray and params[e.name].kind != JString) or
              (params[e.name].kind == JArray and len(params[e.name].elems) == 0)
            )
          ):
            if params[e.name].kind == JArray:
              result &= params[e.name].elems[i].str
            elif params[e.name].kind == JString:
              result &= params[e.name].str
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
          "Parameters for non-optional subtemplate `" & e.name & "` not provided",
        )

func new_template*(text: string, parser: Parser = new_parser()): Template =
  for l in split_lines text:
    result.lines.add parser.new_line l

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

proc test*() =
  check rendered(
    new_template "one <!-- (ref)r --> two",
    %*{"r": [{}]},
    {"r": new_template("three")}.to_table,
  ) == "one three two"

  check """<table>
    <!-- (ref)Row -->
</table>""".new_template.rendered(
    %*{"Row": [{"cell": ["1.1", "2.1"]}, {"cell": ["1.2", "2.2"]}]},
    {
      "Row":
        """<tr>
    <td><!-- (param)cell --></td>
</tr>""".new_template
    }.to_table,
  ) ==
    """<table>
    <tr>
        <td>1.1</td>
        <td>2.1</td>
    </tr>
    <tr>
        <td>1.2</td>
        <td>2.2</td>
    </tr>
</table>"""

  check rendered(new_template "one <!-- (optional)(param)p1 --> two") == "one  two"

  check rendered(
    new_template "one <!-- (ref)r --> two",
    %*{"r": [{"p": "three"}]},
    {"r": new_template "<!-- (param)p -->"}.to_table,
  ) == "one three two"

  check rendered(new_template "one <!-- (param)p1 --> two", %*{"p1": ["v1", "v2"]}) ==
    "one v1 two\none v2 two"

  check rendered(
    new_template "one <!-- (param)p1 --> two <!-- (param)p2 --> three",
    %*{"p1": "v1", "p2": "v2"},
  ) == "one v1 two v2 three"

  check rendered(
    new_template "one <!-- (ref)r --> two",
    %*{"r": [{"p": "three"}, {"p": "four"}]},
    {"r": new_template "<!-- (param)p -->"}.to_table,
  ) == "one three two\none four two"

  check rendered(
    new_template "one <!-- (param)p1 --> two <!-- (param)p2 --> three",
    %*{"p1": ["v1", "v3"], "p2": ["v2", "v4", "v5"]},
  ) == "one v1 two v2 three\none v3 two v4 three"

  let parser = new_parser()

  let syntax = (
    opening: parser.open,
    close: parser.close,
    optional: "(" & parser.optional & ")",
    param: "(" & parser.param & ")",
    `ref`: "(" & parser.`ref` & ")",
  )

  type TestLine = ref object
    expression*: string
    name*: string
    bound_left*: string
    open_tag*: string
    gap_left*: string
    flag*: string
    gap_right*: string
    close_tag*: string
    bound_right*: string

  func join(l: TestLine): string =
    l.bound_left & l.open_tag & l.gap_left & l.flag & l.expression & l.name & l.gap_right &
      l.close_tag & l.bound_right

  let valid = (
    other: ["", " ", "la"],
    gap: ["", " ", "  "],
    value: ["", "l", "la", "\n"],
    `ref`: [syntax.opening & syntax.param & "p" & syntax.close],
    one_line_params_number: [2, 3],
  )

  let invalid = (
    gap: ["l", "la"],
    open_tag: block:
      collect:
        for n in 1 .. len(syntax.opening):
          $syntax.opening[0 ..< n],
    close_tag: block:
      collect:
        for n in 1 .. len(syntax.close):
          $syntax.close[0 ..< n],
    name: ["1", "-", "1l"],
  )

  for value in valid.value:
    for bound_left in concat(@(valid.other), @[syntax.opening]):
      for gap_left in valid.gap:
        for gap_right in valid.gap:
          for bound_right in concat(@(valid.other), @[syntax.close]):
            let r = rendered(
              new_template TestLine(
                open_tag: syntax.opening,
                close_tag: syntax.close,
                expression: syntax.param,
                name: "p",
                bound_left: bound_left,
                gap_left: gap_left,
                gap_right: gap_right,
                bound_right: bound_right,
              ).join(),
              %*{"p": value},
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
                    close_tag: close_tag,
                  ).join()
                  let r = rendered(new_template l, %*{name: value})
                  check r == l

  for `ref` in valid.`ref`:
    for value in valid.value:
      for bound_left in valid.other:
        for gap_left in valid.gap:
          for gap_right in valid.gap:
            for bound_right in valid.other:
              let r = rendered(
                new_template TestLine(
                  open_tag: syntax.opening,
                  close_tag: syntax.close,
                  expression: syntax.`ref`,
                  name: "R",
                  bound_left: bound_left,
                  gap_left: gap_left,
                  gap_right: gap_right,
                  bound_right: bound_right,
                ).join(),
                %*{"R": [{"p": value}]},
                {"R": new_template `ref`}.to_table,
              )
              check r == bound_left & value & bound_right

proc benchmark*() =
  let table = "<table>\n\t<!-- (ref)Row -->\n</table>".new_template
  let templates =
    {"Row": "<tr>\n\t<td><!-- (param)cell --></td>\n</tr>".new_template}.to_table

  proc benchmark_table(size: int, n: int) =
    let params = block:
      var r = %*{"Row": []}
      for y in 0 ..< size:
        var rc = %*{"cell": []}
        for x in 0 ..< size:
          rc["cell"].elems.add(% $(x + y * size))
        r["Row"].elems.add rc
      r

    let start_time = cpu_time()
    for i in 0 ..< n:
      discard table.rendered(params, templates)
    let end_time = cpu_time()
    echo "rendered " & $size & "x" & $size & " table in " &
      $((end_time - start_time) / n.float) & " seconds (cpu time mean of " & $n &
      " experiments)"

  benchmark_table(10, 10000)
  benchmark_table(100, 100)
  benchmark_table(1000, 1)

when is_main_module:
  test()
  benchmark()
