#!/usr/bin/env bash
# Runs host + client Godot processes on localhost and checks the race syncs.
# Usage: Tools/run_net_test.sh [latency_ms] [loss] [client_leave_after_sec]
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
LAT=${1:-0}; LOSS=${2:-0}; LEAVE=${3:--1}
PORT=$((7800 + RANDOM % 100))
OUT=Tests/output; mkdir -p $OUT
$GODOT --headless --path . res://Tools/NetTest.tscn -- --autopilot --role=host --port=$PORT > $OUT/net_host.log 2>&1 &
H=$!
sleep 2
$GODOT --headless --path . res://Tools/NetTest.tscn -- --autopilot --role=client --port=$PORT --latency=$LAT --loss=$LOSS --leave-after=$LEAVE > $OUT/net_client.log 2>&1 &
C=$!
wait $C; CE=$?
wait $H; HE=$?
grep -h "NETTEST RESULT" $OUT/net_host.log $OUT/net_client.log
grep -hE "SCRIPT ERROR|at: GDScript" $OUT/net_host.log $OUT/net_client.log | head
echo "host exit=$HE client exit=$CE"
[ $HE -eq 0 ] && [ $CE -eq 0 ]
