#!/bin/bash
# Internet lobby board against a local fake ntfy server.
G=${GODOT:-godot}
cd "$(dirname "$0")/.."
python3 tests/mock_ntfy.py 8099 & SRV=$!
sleep 0.5
timeout 60 $G --headless --path . res://tests/board_test.tscn 2>&1 | grep -vE "^Godot Engine"
kill $SRV
