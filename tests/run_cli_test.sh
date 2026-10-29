#!/bin/bash
# The ship command line used by the editor plugin: create, copy, info, validate, delete without starting any game scene.
G=${GODOT:-godot}
cd "$(dirname "$0")/.."
fail=0
run() { $G --headless --path . res://tools/ship_cli.tscn -- "$@" 2>&1 | grep -v "^Godot Engine"; }
expect() { if echo "$2" | grep -q "$3"; then echo "ok   $1"; else echo "FAIL $1 -> $2"; fail=1; fi; }
expect "new ship"            "$(run new 'Cli Probe')"            "Created 'Cli Probe'"
expect "no duplicate name"   "$(run new 'Cli Probe')"            "already exists"
expect "info"                "$(run info 'Cli Probe')"           "valid"
expect "copy"                "$(run copy 'Cli Probe' 'Cli Probe 2')" "Copied"
expect "listed"              "$(run list)"                       "Cli Probe 2"
expect "all ships valid"     "$(run validate)"                   "valid"
expect "delete"              "$(run delete 'Cli Probe 2')"       "Deleted"
expect "delete the other"    "$(run delete 'Cli Probe')"         "Deleted"
expect "unknown ship"        "$(run info 'Nope')"                "ERROR"
expect "no premade changed"  "$(run list)"                       "Dart"
[ $fail = 0 ] && echo "RESULT: PASS" || { echo "RESULT: FAIL"; exit 1; }
