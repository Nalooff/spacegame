#!/bin/bash
# Real-window screenshots with a virtual display. Usage: GODOT=... tools/shots.sh <scene.tscn> <out.png> [seconds]
cd "$(dirname "$0")/.."
SCENE=$1; OUT=$2; WAIT=${3:-9}
xvfb-run -a -s "-screen 0 1600x900x24" bash -c "
$GODOT --path . --resolution 1600x900 $SCENE > /tmp/shot_run.log 2>&1 &
sleep $WAIT
import -window root $OUT
kill %1"
