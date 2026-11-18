class_name RaceSession
extends Node
## Bridges RaceWorld and the Net autoload during an online race:
## - publishes the local kart state each physics frame (not on a dedicated server)
## - buffers server snapshots and interpolates remote karts
##   (render time = server time - INTERP_DELAY, linear interpolation between
##   the two surrounding snapshots, short extrapolation when packets are late)
## - SERVER: validates every client state (speed / teleport / off-track) and
##   sends a position correction when it rejects one
## - CLIENT: applies corrections from the server to its own kart
## - SERVER: broadcasts authoritative results from its RaceManager

signal corrected

const INTERP_DELAY := 0.12
const MAX_EXTRAPOLATE := 0.25
## Generous physical limit: boost (42 m/s) + turbo item + network jitter.
const MAX_SPEED_MPS := 60.0
const TELEPORT_SLACK_M := 4.0

var local_kart: KartController
var karts_by_peer: Dictionary = {}   # peer_id -> KartController
var race: RaceManager
var track: TrackBuilder
var _buffers: Dictionary = {}        # peer_id -> Array[{t, s}]
var _clock_offset := INF             # local_clock - server_time (min filtered)
var _last_valid: Dictionary = {}     # peer_id -> {p, h, t, off}
var snapshots_applied := 0
var violations: Dictionary = {}      # peer_id -> count
var corrections_received := 0


func setup(r: RaceManager, local: KartController, by_peer: Dictionary) -> void:
	race = r
	track = r.track
	local_kart = local
	karts_by_peer = by_peer
	Net.states_received.connect(_on_states)
	Net.correction_received.connect(_on_correction)
	if Net.is_host():
		Net.state_validator = validate
		race.race_finished.connect(_on_race_finished)


func _exit_tree() -> void:
	if Net.states_received.is_connected(_on_states):
		Net.states_received.disconnect(_on_states)
	if Net.correction_received.is_connected(_on_correction):
		Net.correction_received.disconnect(_on_correction)
	if Net.state_validator.is_valid() and Net.state_validator.get_object() == self:
		Net.state_validator = Callable()


# ------------------------------------------------------------- server validation
## Returns the state when plausible, {} when rejected (a correction is sent).
func validate(peer_id: int, s: Dictionary, now: float) -> Dictionary:
	var p: Vector3 = s["p"]
	var prev: Dictionary = _last_valid.get(peer_id, {})
	var reason := check_state(prev, p, now)
	if reason == "":
		_last_valid[peer_id] = {"p": p, "h": float(s["h"]), "t": now, "off": track.closest_offset(p)}
		return s
	violations[peer_id] = int(violations.get(peer_id, 0)) + 1
	# Correct to the last accepted position, or onto the track centre line.
	var t: Transform3D
	if prev.is_empty() or reason == "off_track":
		var off := track.closest_offset(p) if prev.is_empty() else float(prev["off"])
		t = track.transform_at(off, 0.0, 0.3)
		_last_valid[peer_id] = {"p": t.origin, "h": KartController.yaw_of_basis(t.basis), "t": now, "off": off}
	else:
		t = Transform3D(Basis(Vector3.UP, float(prev["h"])), prev["p"])
		prev["t"] = now
	print("[Server] rejected state from %d (%s) → correction" % [peer_id, reason])
	Net.send_correction(peer_id, t.origin, KartController.yaw_of_basis(t.basis))
	return {}


## Pure plausibility check (unit-tested). Returns "" or a reason.
func check_state(prev: Dictionary, p: Vector3, now: float) -> String:
	if p.y < track.min_y - 8.0:
		return "below_world"
	var off := track.closest_offset(p)
	var lat := absf(track.lateral_distance(p, off))
	if lat > track.half_width() + TrackBuilder.KERB_W + 4.0:
		return "off_track"
	if prev.is_empty():
		return ""
	var dt := maxf(now - float(prev["t"]), 0.05)
	var dist := p.distance_to(prev["p"])
	if dist <= MAX_SPEED_MPS * dt + TELEPORT_SLACK_M:
		return ""
	# Legit respawn: lands on the centre line slightly BEHIND the last position.
	var back := fposmod(float(prev["off"]) - off, track.length)
	if lat < 1.5 and back < 40.0:
		return ""
	return "teleport"


# ------------------------------------------------------------- snapshots
func _on_states(all: Dictionary, server_time: float) -> void:
	var off := Net.clock() - server_time
	_clock_offset = minf(_clock_offset, off) if _clock_offset < INF else off
	# Let the offset drift up slowly so a one-off fast packet does not pin it.
	_clock_offset += 0.0005
	for id in all.keys():
		if int(id) == Net.my_id() and Net.has_local_player():
			continue
		if not karts_by_peer.has(int(id)):
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
			"b": local_kart.boost.active, "sh": local_kart.shield_timer > 0.0, "sp": local_kart.spin_timer > 0.0,
			"gh": local_kart.ghost_timer > 0.0,
		})
	if _clock_offset == INF:
		return
	var render_t := Net.clock() - _clock_offset - INTERP_DELAY
	for id in _buffers.keys():
		var k: KartController = karts_by_peer.get(id)
		if k == null or not is_instance_valid(k) or not k.is_remote:
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
				"s": lerpf(float(sa["s"]), float(sb["s"]), w), "d": sb["d"], "b": sb["b"],
				"sh": sb.get("sh", false), "sp": sb.get("sp", false), "gh": sb.get("gh", false)}
	# Late: extrapolate from the last snapshot along its heading for a short time.
	var last: Dictionary = buf[-1]["s"]
	var dt := minf(render_t - float(buf[-1]["t"]), MAX_EXTRAPOLATE)
	var h := float(last["h"])
	var p: Vector3 = last["p"] + Vector3(-sin(h), 0, -cos(h)) * float(last["s"]) * dt
	return {"p": p, "h": h, "s": last["s"], "d": last["d"], "b": last["b"], "sh": last.get("sh", false), "sp": last.get("sp", false), "gh": last.get("gh", false)}


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
	k.spin_timer = 0.5 if s["sp"] else 0.0
	k.ghost_timer = 1.0 if s.get("gh", false) else 0.0
	snapshots_applied += 1


# ------------------------------------------------------------- client side
func _on_correction(pos: Vector3, heading: float) -> void:
	if local_kart == null:
		return
	corrections_received += 1
	local_kart.place(Transform3D(Basis(Vector3.UP, heading), pos))
	corrected.emit()


func _on_race_finished(results: Array) -> void:
	Net.broadcast_results(results)
