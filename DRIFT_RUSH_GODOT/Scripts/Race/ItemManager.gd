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
var bombs: Array[Dictionary] = []          # {id, node, puddle, from, to, t, flight, life, radius, landed, visual, owner}
var beams: Array[Dictionary] = []          # {node, a, b, life}
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
		"bomb":
			_throw_bomb(k, def)
		"emp":
			_emp(k, def)
		"magnet":
			_magnet(k, def)
		"storm":
			_storm(k, def)
		"ghost":
			if role != "server" or not k.is_remote:
				k.start_ghost(float(def.get("duration", 3.5)))
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
				elif mine and ev["item"] == "ghost":
					k.start_ghost(float(def.get("duration", 3.5)))
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
		"bomb":
			if role == "client":
				_spawn_bomb_visual(int(ev["id"]), ev["from"], ev["to"], float(ev.get("radius", 3.6)), true)
		"emp":
			if role == "client":
				_emp_ring(ev["pos"], float(ev.get("radius", 25.0)))
		"magnet":
			if role == "client":
				_magnet_beam(_kart(int(ev["peer"])), _kart(int(ev.get("target", 0))), float(ev.get("sec", 3.0)))
			if mine and role == "client":
				k.apply_turbo(float(ev.get("sec", 3.0)), float(ev.get("bonus", 7.0)))
		"slow":
			if mine:
				k.apply_slow(float(ev.get("sec", 1.0)))
		"blind":
			if k:
				_petal_burst(k)
			if mine:
				k.apply_blind(float(ev.get("sec", 3.5)))
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
	_update_bombs(delta)
	_update_beams(delta)


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


# ------------------------------------------------------------- new items
## WATER BOMB: lobbed ~22 m ahead; the puddle slows karts that drive through.
func _throw_bomb(owner: KartController, def: Dictionary) -> void:
	var off := track.closest_offset(owner.global_position)
	var lat := track.lateral_distance(owner.global_position, off)
	var from := owner.global_position + Vector3.UP * 1.2
	# Land well ahead of where the thrower will be when it comes down.
	var dist := float(def.get("distance", 22.0)) + absf(owner.speed) * 0.7
	var to := track.transform_at(off + dist, clampf(lat, -4.0, 4.0)).origin
	var id := _new_id()
	var b := _spawn_bomb_visual(id, from, to, float(def.get("radius", 3.6)), false)
	b["owner"] = owner
	b["life"] = float(def.get("puddle_sec", 7.0))
	b["life0"] = b["life"]
	b["slow"] = float(def.get("slow_sec", 1.2))
	if role == "server":
		Net.send_item_event({"t": "bomb", "id": id, "from": from, "to": to, "radius": b["radius"]})


func _spawn_bomb_visual(id: int, from: Vector3, to: Vector3, radius: float, visual: bool) -> Dictionary:
	var n := Node3D.new()
	MeshFactory.add(n, MeshFactory.sphere(0.45, 14, 8), MeshFactory.mat(Color(0.3, 0.65, 1.0, 0.85), 0.1, 0.0, 0.6))
	MeshFactory.add(n, MeshFactory.sphere(0.15, 8, 4), MeshFactory.mat(Color(1, 1, 1), 0.1, 0.0, 1.0), Vector3(0.15, 0.25, -0.2))
	add_child(n)
	n.global_position = from
	var b := {"id": id, "node": n, "puddle": null, "from": from, "to": to, "t": 0.0, "flight": 0.7,
		"life": 8.0, "radius": radius, "landed": false, "visual": visual, "owner": null, "slow": 1.2}
	bombs.append(b)
	return b


func _update_bombs(delta: float) -> void:
	for b in bombs.duplicate():
		if not b["landed"]:
			b["t"] = float(b["t"]) + delta
			var k := clampf(float(b["t"]) / float(b["flight"]), 0.0, 1.0)
			var p: Vector3 = (b["from"] as Vector3).lerp(b["to"], k) + Vector3.UP * sin(k * PI) * 5.0
			(b["node"] as Node3D).global_position = p
			if k >= 1.0:
				b["landed"] = true
				(b["node"] as Node3D).visible = false
				var puddle := MeshFactory.add(self, MeshFactory.cylinder(float(b["radius"]), float(b["radius"]), 0.04, 28),
					MeshFactory.mat(Color(0.25, 0.6, 1.0, 0.6), 0.05, 0.2, 0.5, 0.0))
				puddle.global_position = (b["to"] as Vector3) + Vector3.UP * 0.05
				puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				b["puddle"] = puddle
				AudioFeedback.play_at("splash", b["to"])
			continue
		b["life"] = float(b["life"]) - delta
		var puddle_node: MeshInstance3D = b["puddle"]
		if puddle_node:
			puddle_node.scale = Vector3.ONE * (1.0 + 0.03 * sin(_t * 4.0))
		if not b["visual"]:
			for kk in race.karts:
				if kk == b["owner"] and float(b["life"]) > float(b.get("life0", 7.0)) - 1.5:
					continue   # thrower is immune to its own fresh puddle
				if Vector2(kk.global_position.x - (b["to"] as Vector3).x, kk.global_position.z - (b["to"] as Vector3).z).length() < float(b["radius"]):
					if role == "server" and kk.is_remote:
						if float(_server_invuln.get("slow_%d" % kk.peer_id, 0.0)) <= 0.0:
							_server_invuln["slow_%d" % kk.peer_id] = 0.8
							Net.send_item_event({"t": "slow", "peer": _peer_of(kk), "sec": b["slow"]})
					else:
						kk.apply_slow(float(b["slow"]))
		if float(b["life"]) <= 0.0:
			bombs.erase(b)
			(b["node"] as Node3D).queue_free()
			if b["puddle"]:
				(b["puddle"] as Node3D).queue_free()
			if role == "server":
				Net.send_item_event({"t": "end", "id": b["id"]})


## EMP: shock ring around the user; every kart within the radius spins briefly.
func _emp(owner: KartController, def: Dictionary) -> void:
	var r := float(def.get("radius", 25.0))
	_emp_ring(owner.global_position, r)
	if role == "server":
		Net.send_item_event({"t": "emp", "pos": owner.global_position, "radius": r})
	for k in race.karts:
		if k != owner and k.global_position.distance_to(owner.global_position) <= r:
			_resolve_hit(k, "emp", float(def.get("spin_sec", 0.8)))


func _emp_ring(pos: Vector3, radius: float) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.86
	ring.outer_radius = 1.0
	ring.rings = 48
	var m := MeshFactory.mat(Color(0.55, 0.95, 1.0, 0.9), 0.1, 0.0, 6.0, 0.0)
	var mi := MeshFactory.add(self, ring, m)
	mi.global_position = pos + Vector3.UP * 0.8
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flash := MeshFactory.add(self, MeshFactory.sphere(1.0, 16, 8), MeshFactory.mat(Color(0.6, 0.95, 1.0, 0.35), 0.1, 0.0, 3.0, 0.0))
	flash.global_position = pos + Vector3.UP * 0.8
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3(radius, 12.0, radius), 0.5).from(Vector3(1, 12.0, 1))
	tw.parallel().tween_property(flash, "scale", Vector3.ONE * 4.0, 0.25).from(Vector3.ONE)
	tw.tween_callback(mi.queue_free)
	tw.tween_callback(flash.queue_free)
	AudioFeedback.play_at("zap", pos)


## MAGNET: locks onto the kart ahead and pulls you along (stronger when far).
func _magnet(owner: KartController, def: Dictionary) -> void:
	var order := race.standings()
	var idx := order.find(owner)
	var target: KartController = order[idx - 1] if idx > 0 else null
	var dist := owner.global_position.distance_to(target.global_position) if target else 0.0
	var sec := float(def.get("duration", 3.0))
	var bonus := float(def.get("bonus", 7.0)) + clampf(dist / 60.0, 0.0, 1.0) * 5.0
	_magnet_beam(owner, target, sec)
	if role == "server":
		Net.send_item_event({"t": "magnet", "peer": _peer_of(owner), "target": _peer_of(target) if target else 0, "sec": sec, "bonus": bonus})
		if owner.is_remote:
			return
	owner.apply_turbo(sec, bonus)


func _magnet_beam(a: KartController, b: KartController, sec: float) -> void:
	if a == null:
		return
	var n := MeshFactory.add(self, MeshFactory.cylinder(0.12, 0.12, 1.0, 8), MeshFactory.mat(Color(1.0, 0.3, 0.5, 0.6), 0.1, 0.0, 3.0, 0.0))
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.visible = b != null
	beams.append({"node": n, "a": a, "b": b, "life": sec})
	AudioFeedback.play_at("magnet", a.global_position)


func _update_beams(delta: float) -> void:
	for bm in beams.duplicate():
		bm["life"] = float(bm["life"]) - delta
		var n: MeshInstance3D = bm["node"]
		var a: KartController = bm["a"]
		var b: KartController = bm["b"]
		if float(bm["life"]) <= 0.0 or not is_instance_valid(a):
			beams.erase(bm)
			n.queue_free()
			continue
		if b and is_instance_valid(b):
			var pa := a.global_position + Vector3.UP * 1.0
			var pb := b.global_position + Vector3.UP * 1.0
			var mid := (pa + pb) / 2.0
			var dir := pb - pa
			if dir.length() > 0.1:
				n.global_transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP) * Basis(Vector3.RIGHT, PI / 2.0), mid)
				n.scale = Vector3(1.0, dir.length(), 1.0)


## PETAL STORM: every kart ahead of you gets a petal cloud over its view.
func _storm(owner: KartController, def: Dictionary) -> void:
	var order := race.standings()
	var idx := order.find(owner)
	var sec := float(def.get("duration", 3.5))
	for i in idx:
		var k := order[i]
		if role == "server":
			# the event reaches every peer (incl. this one): burst + blind there
			Net.send_item_event({"t": "blind", "peer": _peer_of(k), "sec": sec})
		else:
			_petal_burst(k)
			if k.apply_blind(sec):
				item_hit.emit(k, "storm")


func _petal_burst(k: KartController) -> void:
	if k == null or not is_instance_valid(k):
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 60
	p.lifetime = 2.5
	p.explosiveness = 0.7
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 2.5
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -0.8, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.22)
	p.mesh = q
	p.material_override = MeshFactory.particle_material(Color(1.0, 0.6, 0.8))
	p.color = Color(1.0, 0.62, 0.82)
	k.add_child(p)
	p.position = Vector3(0, 1.6, 0)
	p.emitting = true
	get_tree().create_timer(3.0).timeout.connect(p.queue_free)
