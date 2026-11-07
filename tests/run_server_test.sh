#!/bin/bash
# A dedicated server (no player of its own) + one client that joins and picks nothing: the server starts the round by itself. ~25 s.
G=${GODOT:-godot}
cd "$(dirname "$0")/.."
timeout 25 $G --headless --path . -- --server "--name=Test Lobby" --password=secret --wait=6 > /tmp/dedi_server.log 2>&1 &
sleep 2
timeout 22 $G --headless --path . res://tests/lobby_test.tscn -- idle > /tmp/dedi_client.log 2>&1 &
wait
echo "=== server"; grep -E "^\[server\]|ERROR|SCRIPT" /tmp/dedi_server.log | head -10
echo "=== client"; grep -E "^\[|ERROR|SCRIPT" /tmp/dedi_client.log | head -10
