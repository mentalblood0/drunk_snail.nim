import std/tables
import std/times
import std/json

import drunk_snail as ds

let table = "<table>\n\t<!-- (ref)Row -->\n</table>".new_template
let templates =
  {"Row": "<tr>\n\t<td><!-- (param)cell --></td>\n</tr>".new_template}.to_table

proc benchmark_table(size: int, n: int) =
  let params = block:
    var r = %* {"Row": []}
    for y in 0 ..< size:
      var rc = %* {"cell": []}
      for x in 0 ..< size:
        rc["cell"].elems.add( % $(x + y * size))
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
