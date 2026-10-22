#!/bin/bash
# Lists GDScript warnings (everything except "signal never used", which is fine for the BusEvent autoload).
# Works on a temporary copy of the project in which warnings are turned into errors, so Godot prints them
# in headless mode. Usage: GODOT=/path/to/godot tools/check_warnings.sh
G=${GODOT:-godot}
SRC="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
cp -r "$SRC"/. "$TMP"/
rm -rf "$TMP/.godot"
cd "$TMP"
python3 - <<'PY'
keys = """unassigned_variable unassigned_variable_op_assign unused_variable unused_local_constant unused_private_class_variable
unused_parameter shadowed_variable shadowed_variable_base_class shadowed_global_identifier unreachable_code unreachable_pattern
standalone_expression standalone_ternary incompatible_ternary redundant_await assert_always_true assert_always_false integer_division
narrowing_conversion int_as_enum_without_cast int_as_enum_without_match static_called_on_instance confusable_identifier
confusable_local_declaration confusable_local_usage confusable_capture_reassignment get_node_default_without_onready
native_method_override onready_with_export""".split()
t = open("project.godot").read()
t += "\n[debug]\n\n" + "".join("gdscript/warnings/%s=2\n" % k for k in keys)
open("project.godot", "w").write(t)
PY
$G --headless --path . --import >/dev/null 2>&1
$G --headless --path . res://tests/load_all.tscn 2>&1 | grep -A1 "Parse Error\|Compile Error" | grep -v "^--" | paste - - | sort -u
rm -rf "$TMP"
