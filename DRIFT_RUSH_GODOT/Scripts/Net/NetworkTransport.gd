extends Node
## Multiplayer transport — Godot high-level multiplayer over ENet. Autoload: Net.
##
## Two hosting modes:
##  · LAN listen server: a player hosts (peer 1 is also a racer).
##  · Dedicated server: headless process (`-- --server`), peer 1 is NOT a
##    racer; the race starts automatically when ≥2 players are all READY.
##    Deploy on a VM with UDP open for internet play (cost approval needed).
##
## Authority: the server runs RaceManager (checkpoints, laps, finish order,
## DNF) and ItemManager (box pickups, missiles, traps, hits). Clients send their
## kart state at SEND_HZ; the server VALIDATES each state (RaceSession.validate:
## max speed/teleport/off-track) and sends a position correction when it
## rejects one. Item use is a request; effects are server events.
## Firebase is never used for per-frame data.

signal lobby_updated(players: Dictionary)
signal connection_failed(reason: String)
signal connected
signal disconnected(reason: String)
signal race_start_requested(config: Dictionary)
signal countdown_requested(delay_sec: float)
signal states_received(states: Dictionary, server_time: float)
signal results_received(results: Array)
signal peer_left(peer_id: int)
signal correction_received(position: Vector3, heading: float)
signal item_event(ev: Dictionary)
signal item_request(peer_id: int)

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 8
const SEND_HZ := 20.0
const PROTOCOL_VERSION := 2
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

var players: Dictionary = {}     # peer_id -> {name, color, ready, connected, host, loaded}
var room_settings := {"mode": "speed", "map": "sakura_valley", "laps": 3, "capacity": 8}
var room_code := ""
var dedicated := false
var auto_start_min_players := 2
var in_race := false
var race_config: Dictionary = {}
var local_state: Dictionary = {}
var server_port := DEFAULT_PORT
## Server-side hook: func(peer_id: int, state: Dictionary, server_time: float) -> Dictionary
## Returning {} rejects the state (RaceSession sends a correction).
var state_validator: Callable
var discovery: LanDiscovery
var _host_states: Dictionary = {}
var _send_accum := 0.0
var _clock := 0.0
# Network condition simulation (testing): applies to incoming state packets.
var sim_latency_ms := 0
var sim_loss := 0.0
var _delayed: Array = []
var _rng := RandomNumberGenerator.new()
var stats := {"states_sent": 0, "states_recv": 0, "states_dropped": 0, "states_rejected": 0, "corrections": 0}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	discovery = LanDiscovery.new()
	discovery.name = "LanDiscovery"
	add_child(discovery)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_online() -> bool:
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## True on the process that owns the authoritative simulation (LAN host or dedicated server).
func is_host() -> bool:
	return is_online() and multiplayer.is_server()


## True when this process has a kart of its own (false on a dedicated server).
func has_local_player() -> bool:
	return not (is_host() and dedicated)


func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


func clock() -> float:
	return _clock


func _new_code() -> String:
	var s := ""
	for i in 6:
		s += CODE_ALPHABET[_rng.randi() % CODE_ALPHABET.length()]
	return s


func _beacon_payload() -> String:
	return LanDiscovery.encode({"code": room_code, "port": server_port, "name": _host_name(), "players": _player_count(),
		"capacity": room_settings["capacity"], "mode": room_settings["mode"], "map": room_settings["map"], "started": in_race})


func _host_name() -> String:
	if dedicated:
		return "DEDICATED"
	return String(players.get(1, {}).get("name", "HOST"))


func _player_count() -> int:
	var n := 0
	for p in players.values():
		if p["connected"]:
			n += 1
	return n


# ------------------------------------------------------------- lifecycle
func host_lan(player_name: String, color_id: String, port := DEFAULT_PORT, capacity := MAX_PLAYERS) -> int:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, clampi(capacity, 2, MAX_PLAYERS) - 1)
	if err != OK:
		connection_failed.emit("서버를 열 수 없습니다 (포트 %d, 오류 %d)" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	dedicated = false
	server_port = port
	room_code = _new_code()
	room_settings["capacity"] = clampi(capacity, 2, MAX_PLAYERS)
	players = {1: {"name": player_name, "color": color_id, "ready": false, "connected": true, "host": true, "loaded": false}}
	discovery.start_beacon(_beacon_payload)
	lobby_updated.emit(players)
	return OK


func host_dedicated(port := DEFAULT_PORT, settings := {}) -> int:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("Dedicated server: cannot bind UDP %d (err %d)" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	dedicated = true
	server_port = port
	room_code = _new_code()
	room_settings.merge(settings, true)
	room_settings["capacity"] = clampi(int(room_settings.get("capacity", MAX_PLAYERS)), 2, MAX_PLAYERS)
	players = {}
	discovery.start_beacon(_beacon_payload)
	print("[Server] DRIFT RUSH dedicated server on UDP %d · room code %s · %s" % [port, room_code, str(room_settings)])
	return OK


func join_lan(address: String, player_name: String, color_id: String, port := DEFAULT_PORT) -> int:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		connection_failed.emit("접속을 시작할 수 없습니다 (오류 %d)" % err)
		return err
	multiplayer.multiplayer_peer = peer
	set_meta("pending_profile", {"name": player_name, "color": color_id})
	return OK


## Looks for a LAN room with this code for up to `timeout` seconds.
## Returns the beacon info ({ip, port, ...}) or {} when not found.
func discover_code(code: String, timeout := 3.0) -> Dictionary:
	discovery.start_listen()
	var t := 0.0
	while t < timeout:
		var r := discovery.find(code)
		if not r.is_empty():
			return r
		await get_tree().create_timer(0.2, true).timeout
		t += 0.2
	return {}


func leave() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	discovery.stop_beacon()
	players.clear()
	in_race = false
	dedicated = false
	room_code = ""
	_host_states.clear()
	_delayed.clear()


func local_ip_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254"):
			out.append(a)
	return out


# ------------------------------------------------------------- signals
func _on_peer_connected(id: int) -> void:
	if is_host():
		if in_race or _player_count() >= int(room_settings["capacity"]):
			_reject.rpc_id(id, "RACE_STARTED" if in_race else "ROOM_FULL")
			return
		_sync_lobby.rpc_id(id, players, room_settings, room_code, dedicated)


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		if in_race:
			players[id]["connected"] = false
		else:
			players.erase(id)
		peer_left.emit(id)
		if is_host():
			_sync_lobby.rpc(players, room_settings, room_code, dedicated)
		lobby_updated.emit(players)


func _on_connected() -> void:
	var prof: Dictionary = get_meta("pending_profile", {"name": "PLAYER", "color": "orange"})
	_register.rpc_id(1, prof["name"], prof["color"], PROTOCOL_VERSION)
	connected.emit()


func _on_connection_failed() -> void:
	leave()
	connection_failed.emit("호스트에 연결하지 못했습니다. 주소/같은 Wi-Fi 여부를 확인하세요.")


func _on_server_disconnected() -> void:
	var was_racing := in_race
	leave()
	disconnected.emit("방장(서버)이 나갔거나 연결이 끊겼습니다." + (" 경기가 종료됩니다." if was_racing else ""))


# ------------------------------------------------------------- lobby RPCs
@rpc("any_peer", "call_remote", "reliable")
func _register(player_name: String, color_id: String, version: int) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if version != PROTOCOL_VERSION:
		_reject.rpc_id(id, "VERSION_MISMATCH")
		return
	for p in players.values():
		if p["name"] == player_name and p["connected"]:
			player_name = "%s_%d" % [player_name, id % 100]   # duplicate nickname guard
	players[id] = {"name": player_name.substr(0, 16), "color": color_id, "ready": false, "connected": true, "host": false, "loaded": false}
	_sync_lobby.rpc(players, room_settings, room_code, dedicated)
	lobby_updated.emit(players)


@rpc("authority", "call_remote", "reliable")
func _sync_lobby(p: Dictionary, settings: Dictionary, code: String, is_dedicated: bool) -> void:
	players = p
	room_settings = settings
	room_code = code
	set_meta("server_dedicated", is_dedicated)
	lobby_updated.emit(players)


func server_is_dedicated() -> bool:
	return dedicated if is_host() else bool(get_meta("server_dedicated", false))


@rpc("authority", "call_remote", "reliable")
func _reject(reason: String) -> void:
	var msg: String = {"ROOM_FULL": "방 인원이 가득 찼습니다.", "RACE_STARTED": "이미 경기가 시작된 방입니다.",
		"VERSION_MISMATCH": "게임 버전이 다릅니다. 앱을 업데이트하세요."}.get(reason, reason)
	leave()
	connection_failed.emit(msg)


func set_ready(r: bool) -> void:
	if is_host():
		_apply_ready(1, r)
	else:
		_req_ready.rpc_id(1, r)


@rpc("any_peer", "call_remote", "reliable")
func _req_ready(r: bool) -> void:
	if is_host():
		_apply_ready(multiplayer.get_remote_sender_id(), r)


func _apply_ready(id: int, r: bool) -> void:
	if players.has(id):
		players[id]["ready"] = r
		_sync_lobby.rpc(players, room_settings, room_code, dedicated)
		lobby_updated.emit(players)


func update_room_settings(settings: Dictionary) -> void:
	if not is_host():
		return
	room_settings.merge(settings, true)
	_sync_lobby.rpc(players, room_settings, room_code, dedicated)
	lobby_updated.emit(players)


## LAN host: ≥2 connected players and every non-host player ready.
## Dedicated: ≥auto_start_min_players connected players, all ready.
func can_start() -> Dictionary:
	if not is_host():
		return {"ok": false, "reason": "방장만 시작할 수 있습니다."}
	var count := 0
	for id in players.keys():
		var p: Dictionary = players[id]
		if not p["connected"]:
			continue
		count += 1
		if (dedicated or id != 1) and not p["ready"]:
			return {"ok": false, "reason": "모든 참가자가 준비해야 합니다."}
	if count < (auto_start_min_players if dedicated else 2):
		return {"ok": false, "reason": "2명 이상 필요합니다."}
	return {"ok": true, "reason": ""}


func host_start_race() -> bool:
	if not can_start()["ok"]:
		return false
	var cfg := {"mode": room_settings["mode"], "map": room_settings["map"], "laps": room_settings["laps"],
		"bots": 0, "online": true, "seed": randi()}
	for id in players.keys():
		players[id]["loaded"] = false
	_start_race.rpc(cfg, players)
	_start_race(cfg, players)
	return true


@rpc("authority", "call_remote", "reliable")
func _start_race(cfg: Dictionary, p: Dictionary) -> void:
	players = p
	race_config = cfg
	in_race = true
	_host_states.clear()
	race_start_requested.emit(cfg)
	GameFlow.race_config = cfg
	GameFlow.goto("race")


## Called by RaceWorld when its scene is ready.
func report_loaded() -> void:
	if is_host():
		_mark_loaded(1)
	else:
		_req_loaded.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _req_loaded() -> void:
	if is_host():
		_mark_loaded(multiplayer.get_remote_sender_id())


func _mark_loaded(id: int) -> void:
	if players.has(id):
		players[id]["loaded"] = true
	elif not (dedicated and id == 1):
		return
	for p in players.values():
		if p["connected"] and not p["loaded"]:
			return
	_begin_countdown.rpc(0.5)
	_begin_countdown(0.5)


## Host fallback if someone never finishes loading.
func force_countdown() -> void:
	if is_host():
		_begin_countdown.rpc(0.5)
		_begin_countdown(0.5)


@rpc("authority", "call_remote", "reliable")
func _begin_countdown(delay: float) -> void:
	countdown_requested.emit(delay)


# ------------------------------------------------------------- race state
func set_local_state(s: Dictionary) -> void:
	local_state = s


func _process(_delta: float) -> void:
	# Dedicated server starts the race automatically once everyone is ready.
	if is_host() and dedicated and not in_race and can_start()["ok"]:
		print("[Server] all %d players ready → starting race" % _player_count())
		host_start_race()


func _physics_process(delta: float) -> void:
	_clock += delta
	if not is_online() or not in_race:
		_process_delayed()
		return
	_send_accum += delta
	if _send_accum >= 1.0 / SEND_HZ:
		_send_accum = 0.0
		if is_host():
			if has_local_player() and not local_state.is_empty():
				_host_states[1] = local_state
			_s_states.rpc(_host_states, _clock)
			# The server interpolates remote karts from the same snapshots.
			states_received.emit(_host_states.duplicate(), _clock)
		elif not local_state.is_empty():
			_c_state.rpc_id(1, local_state)
			stats["states_sent"] += 1
	_process_delayed()


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _c_state(s: Dictionary) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id):
		return
	var clean := _sanitize_state(s)
	if state_validator.is_valid():
		clean = state_validator.call(id, clean, _clock)
		if clean.is_empty():
			stats["states_rejected"] += 1
			return
	_host_states[id] = clean
	stats["states_recv"] += 1


@rpc("authority", "call_remote", "unreliable_ordered")
func _s_states(all: Dictionary, server_time: float) -> void:
	if sim_loss > 0.0 and _rng.randf() < sim_loss:
		stats["states_dropped"] += 1
		return
	if sim_latency_ms > 0:
		_delayed.append({"at": Time.get_ticks_msec() + sim_latency_ms, "all": all, "t": server_time})
		return
	stats["states_recv"] += 1
	states_received.emit(all, server_time)


func _process_delayed() -> void:
	if _delayed.is_empty():
		return
	var now := Time.get_ticks_msec()
	while not _delayed.is_empty() and int(_delayed[0]["at"]) <= now:
		var d: Dictionary = _delayed.pop_front()
		stats["states_recv"] += 1
		states_received.emit(d["all"], d["t"])


func _sanitize_state(s: Dictionary) -> Dictionary:
	var out := {}
	out["p"] = s.get("p", Vector3.ZERO) if s.get("p") is Vector3 else Vector3.ZERO
	out["h"] = float(s.get("h", 0.0))
	out["s"] = clampf(float(s.get("s", 0.0)), -10.0, 70.0)   # reject impossible speeds
	out["d"] = clampi(int(s.get("d", 0)), -1, 1)
	out["b"] = bool(s.get("b", false))
	out["sh"] = bool(s.get("sh", false))
	out["sp"] = bool(s.get("sp", false))
	return out


## Server → one client: authoritative position after a rejected state.
func send_correction(peer_id: int, pos: Vector3, heading: float) -> void:
	stats["corrections"] += 1
	if peer_id == my_id():
		correction_received.emit(pos, heading)
	else:
		_correct.rpc_id(peer_id, pos, heading)


@rpc("authority", "call_remote", "reliable")
func _correct(pos: Vector3, heading: float) -> void:
	stats["corrections"] += 1
	correction_received.emit(pos, heading)


# ------------------------------------------------------------- items (online)
## Server → everyone (including itself).
func send_item_event(ev: Dictionary) -> void:
	if not is_host():
		return
	_item_evt.rpc(ev)
	item_event.emit(ev)


@rpc("authority", "call_remote", "reliable")
func _item_evt(ev: Dictionary) -> void:
	item_event.emit(ev)


## Client → server: "I want to use my held item".
func request_item_use() -> void:
	if is_host():
		item_request.emit(my_id())
	else:
		_item_req.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _item_req() -> void:
	if is_host():
		item_request.emit(multiplayer.get_remote_sender_id())


# ------------------------------------------------------------- results
func broadcast_results(results: Array) -> void:
	if not is_host():
		return
	_results.rpc(results)
	_results(results)


@rpc("authority", "call_remote", "reliable")
func _results(results: Array) -> void:
	in_race = false
	for id in players.keys():
		if not players[id]["connected"]:
			players.erase(id)
		else:
			players[id]["ready"] = false
	results_received.emit(results)


## Called after the result screen so the same room can race again.
func back_to_room() -> void:
	in_race = false
	if is_host():
		_sync_lobby.rpc(players, room_settings, room_code, dedicated)
