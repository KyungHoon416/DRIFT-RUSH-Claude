class_name ItemManager
extends Node3D
## Item race: item boxes, rank-weighted rolls, missiles, shields, turbo, petal
## traps. Rules/tuning live in Data/items.json.
##
## Roles:
##  "offline" — everything local (vs bots).
##  "server"  — authoritative: decides pickups, item use, projectile hits and
##              broadcasts events through Net.send_item_event().
##  "client"  — never decides anything: asks the server to use an item and
##              renders/applies the server's events (visual projectiles only).

signal item_used(kart: KartController, item: String)
signal item_hit(target: KartController, item: String)

var track: TrackBuilder
var race: RaceManager
var role := "offline"
var karts_by_peer: Dictionary = {}
var rules: Dictionary = {}
var rng := RandomNumberGenerator.new()
var boxes: Array[Area3D] = []
var projectiles: Array[Dictionary] = []   # {id, node, owner, target, life, speed, spin, offset, visual}
var traps: Array[Dictionary] = []          # {id, node, owner, life, armed, spin, visual}
var events_seen := 0
var _box_timers: Dictionary = {}
var _next_id := 1
var _server_invuln: Dictionary = {}       # kart -> seconds (server-side guard against double hits)
var _t := 0.0


func setup(t: TrackBuilder, r: RaceManager, net_role := "offline", by_peer := {}) -> void:
	track = t
	race = r
	role = net_role
	karts_by_peer = by_peer
	rules = GameFlow.item_rules
	rng.randomize()
	for spot in track.item_box_spots:
		_spawn_box(spot)
	if role != "offline":
		Net.item_event.connect(_on_item_event)
	if role == "server":
		Net.item_request.connect(_on_item_request)


func _exit_tree() -> void:
	if Net.item_event.is_connected(_on_item_event):
		Net.item_event.disconnect(_on_item_event)
	if Net.item_request.is_connected(_on_item_request):
		Net.item_request.disconnect(_on_item_request)


func _peer_of(k: KartController) -> int:
	return k.peer_id


func _kart(peer: int) -> KartController:
	return karts_by_peer.get(peer)


func _spawn_box(t: Transform3D) -> void:
	var a := Area3D.new()
	a.collision_layer = KartController.LAYER_TRIGGERS
	a.collision_mask = KartController.LAYER_KARTS
	a.monitoring = role != "client"
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = Vector3(1.8, 2.0, 1.8)
	cs.shape = s
	a.add_child(cs)
	var vis := Node3D.new()
	vis.name = "Vis"
	a.add_child(vis)
	var m := MeshFactory.mat(Color(0.35, 0.6, 1.0, 0.55), 0.1, 0.2, 1.2)
	MeshFactory.add(vis, MeshFactory.box(Vector3(1.3, 1.3, 1.3)), m)
	MeshFactory.add(vis, MeshFactory.box(Vector3(0.9, 0.9, 0.9)), MeshFactory.mat(Color(1.0, 1.0, 1.0, 0.5), 0.1, 0.0, 1.0))
	for face in [1.0, -1.0]:
		var l := MeshFactory.label3d("?", 140, Color.WHITE, Color(0.1, 0.2, 0.6))
		l.position = Vector3(0, 0, 0.67 * face)
		if face < 0.0:
			l.rotation_degrees = Vector3(0, 180, 0)
		vis.add_child(l)
	add_child(a)
	a.global_transform = t
	a.body_entered.connect(_on_box_entered.bind(a))
	boxes.append(a)


func _hide_box(box: Area3D) -> void:
	box.visible = false
	box.set_deferred("monitoring", false)
	_box_timers[box] = float(rules.get("box_respawn_sec", 3.0))


func _on_box_entered(body: Node3D, box: Area3D) -> void:
	if role == "client" or not box.visible or not (body is KartController):
		return
	var k := body as KartController
	_hide_box(box)
	var got := ""
	if k.held_item == "":
		got = roll_item(race.rank_of(k), race.karts.size())
	if role == "server":
		Net.send_item_event({"t": "box", "i": boxes.find(box), "peer": _peer_of(k), "item": got})
		return
	if got != "":
		k.give_item(got)
		if k.is_player:
			AudioFeedback.play("pickup")


## Rank-weighted roll: back of the pack gets more catch-up items.
func roll_item(rank: int, total: int) -> String:
	var items: Dictionary = rules.get("items", {})
	var back := 0.0 if total <= 1 else float(rank - 1) / float(total - 1)
	var pool: Array = []
	var weights: Array = []
	var sum := 0.0
	for id in items.keys():
		var it: Dictionary = items[id]
		var w := lerpf(float(it.get("weight_front", 1)), float(it.get("weight_back", 1)), back)
		pool.append(id)
		weights.append(w)
		sum += w
	if pool.is_empty():
		return ""
	var r := rng.randf() * sum
	for i in pool.size():
		r -= float(weights[i])
		if r <= 0.0:
			return pool[i]
	return pool[-1]


func _def(it: String) -> Dictionary:
	return rules.get("items", {}).get(it, {})


## Offline + server: apply an item use.
func use_item(k: KartController) -> void:
	if k.held_item == "" or k.item_cooldown > 0.0:
		return
	var it := k.consume_item()
	var def := _def(it)
	if role == "server":
		Net.send_item_event({"t": "use", "peer": _peer_of(k), "item": it})
	match it:
		"turbo":
			if role != "server" or not k.is_remote:
				k.apply_turbo(float(def.get("duration", 1.6)), float(def.get("bonus", 14.0)))
		"shield":
			if role != "server" or not k.is_remote:
				k.shield_timer = float(def.get("duration", 6.0))
		"missile":
			_fire_missile(k, def)
		"trap":
			_drop_trap(k, def)
	item_used.emit(k, it)


func _on_item_request(peer: int) -> void:
	var k := _kart(peer)
	if k:
		use_item(k)


func _new_id() -> int:
	_next_id += 1
	return _next_id


func _missile_node() -> Node3D:
	var n := Node3D.new()
	MeshFactory.add(n, MeshFactory.capsule(0.22, 1.1), MeshFactory.mat(Color(1.0, 0.3, 0.3), 0.3, 0.3, 0.5), Vector3.ZERO, Vector3(90, 0, 0))
	MeshFactory.add(n, MeshFactory.sphere(0.2), MeshFactory.mat(Color(1.0, 0.8, 0.3), 0.2, 0.0, 4.0), Vector3(0, 0, 0.6))
	add_child(n)
	return n


func _trap_node() -> Node3D:
	var n := Node3D.new()
	var petal := MeshFactory.mat(Color(1.0, 0.5, 0.75), 0.4, 0.0, 0.6)
	for k in 5:
		var ang := TAU * k / 5.0
		MeshFactory.add(n, MeshFactory.sphere(0.45, 8, 4), petal, Vector3(cos(ang) * 0.5, 0.15, sin(ang) * 0.5), Vector3.ZERO, Vector3(1, 0.3, 1))
	MeshFactory.add(n, MeshFactory.sphere(0.3, 8, 4), MeshFactory.mat(Color(1.0, 0.9, 0.3), 0.4), Vector3(0, 0.2, 0))
	add_child(n)
	return n


func _fire_missile(owner: KartController, def: Dictionary) -> void:
	var order := race.standings()
	var idx := order.find(owner)
	var target: KartController = order[idx - 1] if idx > 0 else null
	var n := _missile_node()
	n.global_position = owner.global_position + owner.forward() * 2.5 + Vector3.UP * 0.8
	var p := {"id": _new_id(), "node": n, "owner": owner, "target": target, "life": float(def.get("lifetime", 6.0)),
		"speed": float(def.get("speed", 55.0)), "spin": float(def.get("spin_sec", 1.2)),
		"offset": track.closest_offset(n.global_position), "visual": false}
	projectiles.append(p)
	if role == "server":
		Net.send_item_event({"t": "missile", "id": p["id"], "owner": _peer_of(owner),
			"target": _peer_of(target) if target else 0, "pos": n.global_position, "off": p["offset"]})


func _drop_trap(owner: KartController, def: Dictionary) -> void:
	var n := _trap_node()
	n.global_position = owner.global_position - owner.forward() * 2.8
	var tr := {"id": _new_id(), "node": n, "owner": owner, "life": float(def.get("lifetime", 25.0)), "armed": 0.6,
		"spin": float(def.get("spin_sec", 1.0)), "visual": false}
	traps.append(tr)
	if role == "server":
		Net.send_item_event({"t": "trap", "id": tr["id"], "pos": n.global_position})


## Server/offline: resolve a hit (shield + invulnerability rules).
func _resolve_hit(k: KartController, item: String, spin: float) -> void:
	if role == "server":
		if float(_server_invuln.get(k, 0.0)) > 0.0:
			return
		if k.shield_timer > 0.0:
			_server_invuln[k] = 0.5
			Net.send_item_event({"t": "blocked", "peer": _peer_of(k)})
			return
		_server_invuln[k] = spin + float(rules.get("hit_invulnerable_sec", 1.5))
		Net.send_item_event({"t": "hit", "peer": _peer_of(k), "item": item, "spin": spin})
		item_hit.emit(k, item)
		return
	if k.apply_item_hit(spin):
		item_hit.emit(k, item)


# ------------------------------------------------------------- client events
func _on_item_event(ev: Dictionary) -> void:
	events_seen += 1
	var t := String(ev.get("t", ""))
	var k := _kart(int(ev.get("peer", 0)))
	var mine := k != null and not k.is_remote
	match t:
		"box":
			var i := int(ev.get("i", -1))
			if role == "client" and i >= 0 and i < boxes.size():
				_hide_box(boxes[i])
			if k and String(ev.get("item", "")) != "":
				k.give_item(String(ev["item"]))
				if mine:
					AudioFeedback.play("pickup")
		"use":
			if k and role == "client":
				k.consume_item()
				var def := _def(String(ev.get("item", "")))
				if mine and ev["item"] == "turbo":
					k.apply_turbo(float(def.get("duration", 1.6)), float(def.get("bonus", 14.0)))
				elif mine and ev["item"] == "shield":
					k.shield_timer = float(def.get("duration", 6.0))
		"missile":
			if role == "client":
				var n := _missile_node()
				n.global_position = ev["pos"]
				projectiles.append({"id": int(ev["id"]), "node": n, "owner": _kart(int(ev["owner"])),
					"target": _kart(int(ev["target"])), "life": 6.0, "speed": 55.0, "spin": 0.0,
					"offset": float(ev["off"]), "visual": true})
		"trap":
			if role == "client":
				var n2 := _trap_node()
				n2.global_position = ev["pos"]
				traps.append({"id": int(ev["id"]), "node": n2, "owner": null, "life": 30.0, "armed": 9999.0, "spin": 0.0, "visual": true})
		"end":
			if role == "client":
				_remove_by_id(int(ev["id"]))
		"hit":
			if mine:
				k.invulnerable_timer = 0.0
				k.apply_item_hit(float(ev.get("spin", 1.0)))
		"blocked":
			if mine:
				k.shield_timer = 0.0


func _remove_by_id(id: int) -> void:
	for p in projectiles.duplicate():
		if int(p["id"]) == id:
			projectiles.erase(p)
			(p["node"] as Node3D).queue_free()
	for tr in traps.duplicate():
		if int(tr["id"]) == id:
			traps.erase(tr)
			(tr["node"] as Node3D).queue_free()


# ------------------------------------------------------------- simulation
func _physics_process(delta: float) -> void:
	_t += delta
	for b in boxes:
		var vis := b.get_node("Vis") as Node3D
		vis.rotate_y(delta * 1.5)
		vis.position.y = sin(_t * 2.0 + b.global_position.x) * 0.15
		if _box_timers.has(b):
			_box_timers[b] = float(_box_timers[b]) - delta
			if float(_box_timers[b]) <= 0.0:
				_box_timers.erase(b)
				b.visible = true
				b.monitoring = role != "client"
	for k in _server_invuln.keys():
		_server_invuln[k] = float(_server_invuln[k]) - delta
	for k in race.karts:
		if k.item_request:
			k.item_request = false
			if role == "client":
				if k.held_item != "":
					Net.request_item_use()
			elif role == "server" and k.is_remote:
				pass   # remote players request via RPC
			else:
				use_item(k)
	_update_projectiles(delta)
	_update_traps(delta)


func _update_projectiles(delta: float) -> void:
	for p in projectiles.duplicate():
		var n: Node3D = p["node"]
		p["life"] = float(p["life"]) - delta
		var target: KartController = p["target"]
		var spd := float(p["speed"])
		p["offset"] = float(p["offset"]) + spd * delta
		var aim: Vector3 = track.frame_at(float(p["offset"]))["pos"] + Vector3.UP * 0.9
		if target and is_instance_valid(target) and n.global_position.distance_to(target.global_position) < 25.0:
			aim = target.global_position + Vector3.UP * 0.7
		var dir := (aim - n.global_position)
		if dir.length() > 0.01:
			n.look_at(aim, Vector3.UP)
		n.global_position += dir.normalized() * minf(spd * delta, dir.length() + spd * delta * 0.2)
		if p["visual"]:
			if float(p["life"]) <= 0.0:
				_remove_by_id(int(p["id"]))
			continue
		var hit: KartController = null
		for k in race.karts:
			if k != p["owner"] and k.global_position.distance_to(n.global_position) < 1.6:
				hit = k
				break
		if hit:
			_resolve_hit(hit, "missile", float(p["spin"]))
			_end(p, projectiles)
		elif float(p["life"]) <= 0.0:
			_end(p, projectiles)


func _end(entry: Dictionary, list: Array) -> void:
	list.erase(entry)
	(entry["node"] as Node3D).queue_free()
	if role == "server":
		Net.send_item_event({"t": "end", "id": entry["id"]})


func _update_traps(delta: float) -> void:
	for tr in traps.duplicate():
		tr["life"] = float(tr["life"]) - delta
		tr["armed"] = float(tr["armed"]) - delta
		var n: Node3D = tr["node"]
		n.rotate_y(delta)
		if tr["visual"]:
			if float(tr["life"]) <= 0.0:
				_remove_by_id(int(tr["id"]))
			continue
		if float(tr["armed"]) <= 0.0:
			for k in race.karts:
				if k.global_position.distance_to(n.global_position) < 1.5:
					_resolve_hit(k, "trap", float(tr["spin"]))
					tr["life"] = 0.0
					break
		if float(tr["life"]) <= 0.0:
			_end(tr, traps)
