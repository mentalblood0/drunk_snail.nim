<h1 align="center">🌪️ drunk snail</h1>

Pure [nim](https://nim-lang.org/) implementation of template language originally presented in [drunk snail](https://github.com/mentalblood0/drunk_snail)

Uses standard library modules only

## Why this language?

- Easy syntax
- Separates logic and data

## Why better then Python / C implementations?

- Compiled and statically typed yet memory safe
- Small codebase
- Allow for parser configuration

## Example

Row:

```html
<tr>
  <td><!-- (param)cell --></td>
</tr>
```

Table:

```html
<table>
  <!-- (ref)Row -->
</table>
```

Arguments:

```json
{
  "Row": [
    {
      "cell": ["1", "2"]
    },
    {
      "cell": ["3", "4"]
    }
  ]
}
```

Result:

```html
<table>
  <tr>
    <td>1</td>
    <td>2</td>
  </tr>
  <tr>
    <td>3</td>
    <td>4</td>
  </tr>
</table>
```

## Installation

Download and import [drunk_snail.nim](https://github.com/mentalblood0/drunk_snail.nim/blob/main/drunk_snail.nim) into your project

## Usage

```nim
import std/json
import std/tables
import std/unittest

import drunk_snail

check """<table>
    <!-- (ref)Row -->
</table>""".new_template.rendered(
    %*{"Row": [{"cell": ["1.1", "2.1"]}, {"cell": ["1.2", "2.2"]}]},
    {
      "Row": """<tr>
    <td><!-- (param)cell --></td>
</tr>""".new_template
    }.to_table,
) == """<table>
    <tr>
        <td>1.1</td>
        <td>2.1</td>
    </tr>
    <tr>
        <td>1.2</td>
        <td>2.2</td>
    </tr>
</table>"""
```

## Testing/Benchmarking

Build [drunk_snail.nim](https://github.com/mentalblood0/drunk_snail.nim/blob/main/drunk_snail.nim) as main file and run, or call it's exported `test` and `benchmark` methods from another module
