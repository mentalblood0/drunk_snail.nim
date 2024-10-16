import std/json
import std/tables

import drunk_snail

assert rendered(
  new_template "<table>\n\t<!-- (ref)Row -->\n</table>",
  %* {"Row": [{"cell": ["1.1", "2.1"]}, {"cell": ["1.2", "2.2"]}]},
  {"Row": new_template "<tr>\n\t<td><!-- (param)cell --></td>\n</tr>"}.to_table,
) == "<table>\n\t<tr>\n\t\t<td>1.1</td>\n\t\t<td>2.1</td>\n\t</tr>\n\t<tr>\n\t\t<td>1.2</td>\n\t\t<td>2.2</td>\n\t</tr>\n</table>"

