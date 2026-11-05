#!/bin/bash
# Host starts the game ALONE with late join on; a second player joins afterwards, picks a ship and jumps in (~16 s, localhost).
G=${GODOT:-godot}
cd "$(dirname "$0")/.."
timeout 24 $G --headless --path . res://tests/late_test.tscn -- host > /tmp/late_host.log 2>&1 &
sleep 5
timeout 14 $G --headless --path . res://tests/late_test.tscn -- late > /tmp/late_late.log 2>&1 &
wait
for r in host late; do echo "=== $r"; grep -E "^\[|ERROR|SCRIPT" /tmp/late_$r.log | head -25; done
