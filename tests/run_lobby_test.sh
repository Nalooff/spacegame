#!/bin/bash
# Host (private lobby) + a client that discovers it and joins as crew + an idle client. ~25 s, all on localhost.
G=${GODOT:-godot}
cd "$(dirname "$0")/.."
timeout 30 $G --headless --path . res://tests/lobby_test.tscn -- host > /tmp/lobby_host.log 2>&1 &
sleep 1.5
timeout 28 $G --headless --path . res://tests/lobby_test.tscn -- crew > /tmp/lobby_crew.log 2>&1 &
timeout 28 $G --headless --path . res://tests/lobby_test.tscn -- idle > /tmp/lobby_idle.log 2>&1 &
wait
for r in host crew idle; do echo "=== $r"; grep -E "^\[|ERROR|SCRIPT" /tmp/lobby_$r.log | head -22; done
