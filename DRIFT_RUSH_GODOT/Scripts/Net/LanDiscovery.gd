class_name LanDiscovery
extends Node
## Finds rooms on the local network by 6-char room code (no IP typing).
## Hosts broadcast a small UDP beacon once per second on PORT; joiners listen.
## Beacons go to 255.255.255.255 (LAN) and 127.0.0.1 (same machine / tests).
## Mobile notes (unverified on devices): Android may need a Wi-Fi multicast lock
## on some devices; iOS 14+ needs the multicast networking entitlement for
## broadcast — otherwise joiners can still use "IP로 참가".

signal rooms_changed(rooms: Dictionary)

const PORT := 7779
const MAGIC := "DRIFTRUSH1"
const EXPIRE_SEC := 4.0

var rooms: Dictionary = {}          # code -> {ip, port, name, players, capacity, mode, map, started, seen}
var listening := false
var _tx: PacketPeerUDP
var _rx: PacketPeerUDP
var _payload_fn: Callable
var _beacon_accum := 0.0
var _t := 0.0


static func encode(info: Dictionary) -> String:
	return "|".join([MAGIC, info.get("code", ""), str(info.get("port", 7777)), String(info.get("name", "")).replace("|", "/"),
		str(info.get("players", 0)), str(info.get("capacity", 8)), info.get("mode", "speed"), info.get("map", ""),
		"1" if info.get("started", false) else "0"])


static func decode(text: String) -> Dictionary:
	var f := text.split("|")
	if f.size() != 9 or f[0] != MAGIC or f[1].length() != 6:
		return {}
	return {"code": f[1], "port": int(f[2]), "name": f[3], "players": int(f[4]), "capacity": int(f[5]),
		"mode": f[6], "map": f[7], "started": f[8] == "1"}


func start_beacon(payload_fn: Callable) -> void:
	_payload_fn = payload_fn
	_tx = PacketPeerUDP.new()
	_tx.set_broadcast_enabled(true)
	_beacon_accum = 1.0


func stop_beacon() -> void:
	_payload_fn = Callable()
	if _tx:
		_tx.close()
	_tx = null


func start_listen() -> bool:
	if listening:
		return true
	_rx = PacketPeerUDP.new()
	var err := _rx.bind(PORT)
	listening = err == OK
	if not listening:
		push_warning("LanDiscovery: cannot listen on UDP %d (err %d)" % [PORT, err])
	return listening


func stop_listen() -> void:
	if _rx:
		_rx.close()
	_rx = null
	listening = false
	rooms.clear()


func find(code: String) -> Dictionary:
	return rooms.get(code.strip_edges().to_upper(), {})


func _process(delta: float) -> void:
	_t += delta
	if _tx and _payload_fn.is_valid():
		_beacon_accum += delta
		if _beacon_accum >= 1.0:
			_beacon_accum = 0.0
			var data := String(_payload_fn.call()).to_utf8_buffer()
			for target in ["255.255.255.255", "127.0.0.1"]:
				_tx.set_dest_address(target, PORT)
				_tx.put_packet(data)
	if _rx:
		var changed := false
		while _rx.get_available_packet_count() > 0:
			var pkt := _rx.get_packet()
			var ip := _rx.get_packet_ip()
			var info := decode(pkt.get_string_from_utf8())
			if info.is_empty():
				continue
			info["ip"] = ip
			info["seen"] = _t
			if not rooms.has(info["code"]):
				changed = true
			rooms[info["code"]] = info
		for code in rooms.keys():
			if _t - float(rooms[code]["seen"]) > EXPIRE_SEC:
				rooms.erase(code)
				changed = true
		if changed:
			rooms_changed.emit(rooms)
