#!/bin/bash
# Runs a host and a client headless against each other on localhost (~30 s).
G=${GODOT:-godot}
cd "$(dirname "$0")/.."
timeout ${T:-36} $G --headless --path . res://tests/net_test.tscn -- host ${HOST_SHIP:-Dart} > /tmp/net_host.log 2>&1 &
sleep 1.5
timeout ${T:-36} $G --headless --path . res://tests/net_test.tscn -- client ${CLIENT_SHIP:-Brick} > /tmp/net_client.log 2>&1 &
wait
echo "=== host"; grep -vE "^Godot Engine" /tmp/net_host.log | head -40
echo "=== client"; grep -vE "^Godot Engine" /tmp/net_client.log | head -40
