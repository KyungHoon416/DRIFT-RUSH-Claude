class_name RaceSession
extends Node
## Bridges RaceWorld and the Net autoload during an online race:
## - publishes the local kart state each physics frame
## - buffers host snapshots and interpolates remote karts
##   (render time = server time - INTERP_DELAY, linear interpolation between
##   the two surrounding snapshots, short extrapolation when packets are late)
## - host: broadcasts authoritative results from its RaceManager

const INTERP_DELAY := 0.12
const MAX_EXTRAPOLATE := 0.25

var local_kart: KartController
var karts_by_peer: Dictionary = {}   # peer_id -> KartController
var race: RaceManager
var _buffers: Dictionary = {}        # peer_id -> Array[{t, s}]
var _clock_offset := INF             # local_clock - server_time (min filtered)
var snapshots_applied := 0


func setup(r: RaceManager, local: KartController, by_peer: Dictionary) -> void:
	race = r
	local_kart = local
	karts_by_peer = by_peer
	Net.states_received.connect(_on_states)
	if Net.is_host():
		race.race_finished.connect(_on_race_finished)


func _exit_tree() -> void:
	if Net.states_received.is_connected(_on_states):
		Net.states_received.disconnect(_on_states)


func _on_states(all: Dictionary, server_time: float) -> void:
	var off := Net.clock() - server_time
	_clock_offset = minf(_clock_offset, off) if _clock_offset < INF else off
	# Let the offset drift up slowly so a one-off fast packet does not pin it.
	_clock_offset += 0.0005
	for id in all.keys():
		if int(id) == Net.my_id() or not karts_by_peer.has(int(id)):
			continue
		var buf: Array = _buffers.get(int(id), [])
		buf.append({"t": server_time, "s": all[id]})
		while buf.size() > 30:
			buf.pop_front()
		_buffers[int(id)] = buf


func _physics_process(_delta: float) -> void:
	if local_kart:
		Net.set_local_state({
			"p": local_kart.global_position, "h": local_kart.heading, "s": local_kart.speed,
			"d": local_kart.drift.direction if local_kart.drift.drifting else 0,
			"b": local_kart.boost.active, "sh": local_kart.shield_timer > 0.0,
		})
	if _clock_offset == INF:
		return
	var render_t := Net.clock() - _clock_offset - INTERP_DELAY
	for id in _buffers.keys():
		var k: KartController = karts_by_peer.get(id)
		if k == null or not is_instance_valid(k):
			continue
		apply_interpolated(k, _buffers[id], render_t)


## Pure interpolation helper (unit-tested).
static func sample(buf: Array, render_t: float) -> Dictionary:
	if buf.is_empty():
		return {}
	if render_t <= float(buf[0]["t"]):
		return buf[0]["s"]
	for i in range(buf.size() - 1):
		var a: Dictionary = buf[i]
		var b: Dictionary = buf[i + 1]
		if render_t >= float(a["t"]) and render_t <= float(b["t"]):
			var span := maxf(0.0001, float(b["t"]) - float(a["t"]))
			var w := (render_t - float(a["t"])) / span
			var sa: Dictionary = a["s"]
			var sb: Dictionary = b["s"]
			return {"p": (sa["p"] as Vector3).lerp(sb["p"], w), "h": lerp_angle(float(sa["h"]), float(sb["h"]), w),
				"s": lerpf(float(sa["s"]), float(sb["s"]), w), "d": sb["d"], "b": sb["b"], "sh": sb.get("sh", false)}
	# Late: extrapolate from the last snapshot along its heading for a short time.
	var last: Dictionary = buf[-1]["s"]
	var dt := minf(render_t - float(buf[-1]["t"]), MAX_EXTRAPOLATE)
	var h := float(last["h"])
	var p: Vector3 = last["p"] + Vector3(-sin(h), 0, -cos(h)) * float(last["s"]) * dt
	return {"p": p, "h": h, "s": last["s"], "d": last["d"], "b": last["b"], "sh": last.get("sh", false)}


func apply_interpolated(k: KartController, buf: Array, render_t: float) -> void:
	var s := sample(buf, render_t)
	if s.is_empty():
		return
	k.global_position = s["p"]
	k.heading = float(s["h"])
	k.rotation = Vector3(0, k.heading, 0)
	k.speed = float(s["s"])
	var d := int(s["d"])
	k.drift.drifting = d != 0
	k.drift.direction = d
	k.boost.active = bool(s["b"])
	k.shield_timer = 1.0 if s["sh"] else 0.0
	snapshots_applied += 1


func _on_race_finished(results: Array) -> void:
	Net.broadcast_results(results)
