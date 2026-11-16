#!/usr/bin/env bash
# Multi-process network tests on localhost.
#   Tools/run_net_test.sh [latency_ms] [loss] [client_leave_after_sec]      LAN host + 1 client
#   SCENARIO=dedicated Tools/run_net_test.sh                                 dedicated server + 2 clients (code discovery)
#   SCENARIO=items     Tools/run_net_test.sh                                 LAN item race (server-judged items)
#   SCENARIO=cheat     Tools/run_net_test.sh                                 client teleports → server correction
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
LAT=${1:-0}; LOSS=${2:-0}; LEAVE=${3:--1}
SCENARIO=${SCENARIO:-lan}
PORT=$((7800 + RANDOM % 100))
OUT=Tests/output; mkdir -p $OUT
run() { $GODOT --headless --path . res://Tools/NetTest.tscn -- --autopilot --port=$PORT "$@"; }
PIDS=()
case $SCENARIO in
  dedicated)
    run --role=server --mode=speed --laps=1 > $OUT/net_server.log 2>&1 & PIDS+=($!)
    sleep 2
    run --role=client --discover > $OUT/net_client1.log 2>&1 & PIDS+=($!)
    run --role=client --latency=100 --loss=0.02 > $OUT/net_client2.log 2>&1 & PIDS+=($!)
    LOGS="$OUT/net_server.log $OUT/net_client1.log $OUT/net_client2.log" ;;
  items)
    run --role=host --mode=item --laps=2 > $OUT/net_host.log 2>&1 & PIDS+=($!)
    sleep 2
    run --role=client > $OUT/net_client.log 2>&1 & PIDS+=($!)
    LOGS="$OUT/net_host.log $OUT/net_client.log" ;;
  cheat)
    run --role=host --laps=1 > $OUT/net_host.log 2>&1 & PIDS+=($!)
    sleep 2
    run --role=client --cheat=8 > $OUT/net_client.log 2>&1 & PIDS+=($!)
    LOGS="$OUT/net_host.log $OUT/net_client.log" ;;
  *)
    run --role=host > $OUT/net_host.log 2>&1 & PIDS+=($!)
    sleep 2
    run --role=client --latency=$LAT --loss=$LOSS --leave-after=$LEAVE > $OUT/net_client.log 2>&1 & PIDS+=($!)
    LOGS="$OUT/net_host.log $OUT/net_client.log" ;;
esac
FAIL=0
for p in "${PIDS[@]}"; do wait $p || FAIL=1; done
grep -h "NETTEST RESULT\|discovered\|CHEAT\|rejected" $LOGS
grep -hE "SCRIPT ERROR|at: GDScript" $LOGS | head
echo "scenario=$SCENARIO fail=$FAIL"
exit $FAIL
