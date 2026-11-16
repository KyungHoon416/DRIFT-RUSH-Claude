class_name ItemManager
extends Node3D
## Item race (offline vs bots): item boxes, rank-weighted item rolls, missiles,
## shields, turbo, petal traps. Rules/tuning live in Data/items.json.
## Online item race is NOT implemented yet (needs server-side hit validation).

signal item_used(kart: KartController, item: String)
signal item_hit(target: KartController, item: String)

var track: TrackBuilder
var race: RaceManager
var rules: Dictionary = {}
var rng := RandomNumberGenerator.new()
var boxes: Array[Area3D] = []
var projectiles: Array[Dictionary] = []   # {node, owner, target, kind, life, offset}
var traps: Array[Dictionary] = []          # {node, owner, life, armed}
var _box_timers: Dictionary = {}
var _t := 0.0


func setup(t: TrackBuilder, r: RaceManager) -> void:
	track = t
	race = r
	rules = GameFlow.item_rules
	rng.randomize()
	for spot in track.item_box_spots:
		_spawn_box(spot)


func _spawn_box(t: Transform3D) -> void:
	var a := Area3D.new()
	a.collision_layer = KartController.LAYER_TRIGGERS
	a.collision_mask = KartController.LAYER_KARTS
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


func _on_box_entered(body: Node3D, box: Area3D) -> void:
	if not box.visible or not (body is KartController):
		return
	var k := body as KartController
	box.visible = false
	box.set_deferred("monitoring", false)
	_box_timers[box] = float(rules.get("box_respawn_sec", 3.0))
	if k.held_item == "":
		k.give_item(roll_item(race.rank_of(k), race.karts.size()))
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


func use_item(k: KartController) -> void:
	if k.held_item == "" or k.item_cooldown > 0.0:
		return
	var it := k.consume_item()
	var def: Dictionary = rules.get("items", {}).get(it, {})
	match it:
		"turbo":
			k.apply_turbo(float(def.get("duration", 1.6)), float(def.get("bonus", 14.0)))
		"shield":
			k.shield_timer = float(def.get("duration", 6.0))
		"missile":
			_fire_missile(k, def)
		"trap":
			_drop_trap(k, def)
	item_used.emit(k, it)


func _fire_missile(owner: KartController, def: Dictionary) -> void:
	var order := race.standings()
	var idx := order.find(owner)
	var target: KartController = order[idx - 1] if idx > 0 else null
	var n := Node3D.new()
	MeshFactory.add(n, MeshFactory.capsule(0.22, 1.1), MeshFactory.mat(Color(1.0, 0.3, 0.3), 0.3, 0.3, 0.5), Vector3.ZERO, Vector3(90, 0, 0))
	MeshFactory.add(n, MeshFactory.sphere(0.2), MeshFactory.mat(Color(1.0, 0.8, 0.3), 0.2, 0.0, 4.0), Vector3(0, 0, 0.6))
	add_child(n)
	n.global_position = owner.global_position + owner.forward() * 2.5 + Vector3.UP * 0.8
	projectiles.append({"node": n, "owner": owner, "target": target, "life": float(def.get("lifetime", 6.0)),
		"speed": float(def.get("speed", 55.0)), "spin": float(def.get("spin_sec", 1.2)),
		"offset": track.closest_offset(n.global_position)})


func _drop_trap(owner: KartController, def: Dictionary) -> void:
	var n := Node3D.new()
	var petal := MeshFactory.mat(Color(1.0, 0.5, 0.75), 0.4, 0.0, 0.6)
	for k in 5:
		var ang := TAU * k / 5.0
		MeshFactory.add(n, MeshFactory.sphere(0.45, 8, 4), petal, Vector3(cos(ang) * 0.5, 0.15, sin(ang) * 0.5), Vector3.ZERO, Vector3(1, 0.3, 1))
	MeshFactory.add(n, MeshFactory.sphere(0.3, 8, 4), MeshFactory.mat(Color(1.0, 0.9, 0.3), 0.4), Vector3(0, 0.2, 0))
	add_child(n)
	n.global_position = owner.global_position - owner.forward() * 2.8
	traps.append({"node": n, "owner": owner, "life": float(def.get("lifetime", 25.0)), "armed": 0.6, "spin": float(def.get("spin_sec", 1.0))})


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
				b.monitoring = true
	for k in race.karts:
		if k.item_request:
			k.item_request = false
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
		var hit: KartController = null
		for k in race.karts:
			if k != p["owner"] and k.global_position.distance_to(n.global_position) < 1.6:
				hit = k
				break
		if hit:
			if hit.apply_item_hit(float(p["spin"])):
				item_hit.emit(hit, "missile")
			_free_proj(p)
		elif float(p["life"]) <= 0.0:
			_free_proj(p)


func _free_proj(p: Dictionary) -> void:
	projectiles.erase(p)
	(p["node"] as Node3D).queue_free()


func _update_traps(delta: float) -> void:
	for tr in traps.duplicate():
		tr["life"] = float(tr["life"]) - delta
		tr["armed"] = float(tr["armed"]) - delta
		var n: Node3D = tr["node"]
		n.rotate_y(delta)
		if float(tr["armed"]) <= 0.0:
			for k in race.karts:
				if k.global_position.distance_to(n.global_position) < 1.5:
					if k.apply_item_hit(float(tr["spin"])):
						item_hit.emit(k, "trap")
					tr["life"] = 0.0
					break
		if float(tr["life"]) <= 0.0:
			traps.erase(tr)
			n.queue_free()
