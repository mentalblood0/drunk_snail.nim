import drunk_snail

assert rendered(new_template "one <!-- (optional)(param)p1 --> two") == "one  two"

