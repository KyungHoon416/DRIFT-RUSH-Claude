class_name KartController
extends CharacterBody3D
## Arcade kart on CharacterBody3D.
## Physics step order: timers → longitudinal (auto-accel / brake / boost) →
## drift state → steering → grip (travel direction lags heading = slide) →
## gravity → move_and_slide → collision response (wall / kart).
## Inputs are written by a driver node (PlayerInput, AIDriver) or, for network
## ghosts, the kart is driven by RemoteKartSync (is_remote = true).

signal impact(kind: String, strength: float)
signal boost_started(kind: String)
signal drift_boost(tier: int)
signal boost_ended
signal drift_started(direction: int)
signal drift_ended(charge: float, tier: int)
signal item_changed(item: String)
signal respawned

const LAYER_WORLD := 1
const LAYER_WALLS := 2
const LAYER_KARTS := 4
const LAYER_TRIGGERS := 8
## Visible kart footprint used for kart-vs-kart contact (width, height, length).
const BODY_SIZE := Vector3(1.66, 1.1, 2.95)

@export var stats_id := "default"
var stats: Dictionary = {}
var display_name := "PLAYER"
var kart_color := Color(1.0, 0.42, 0.05)
var is_player := false
var is_remote := false
var peer_id := 0
var speed_multiplier := 1.0   # AI difficulty / handicap

# Driver inputs
var control_enabled := false
var steer_input := 0.0
var drift_input := false
var brake_input := false
var boost_request := false
var item_request := false
var respawn_request := false

# State
var speed := 0.0
var heading := 0.0
var travel_heading := 0.0
var vertical_speed := 0.0
var drift := DriftSystem.new()
var boost := BoostSystem.new()
var boost_gauge := 0.0
var spin_timer := 0.0
var shield_timer := 0.0
var invulnerable_timer := 0.0
var held_item := ""
var item_cooldown := 0.0
var offroad := false
var sim_time := 0.0
var impact_count := 0
var last_impact: Dictionary = {}
var model: KartModel
var _impact_cd: Dictionary = {}


func _ready() -> void:
	stats = GameFlow.get_kart_stats(stats_id) if is_instance_valid(GameFlow) else {}
	if stats.is_empty():
		stats = {"max_speed": 30.0, "acceleration": 13.0, "brake_decel": 28.0, "coast_decel": 5.0, "turn_speed": 2.0,
			"drift_turn_bonus": 1.2, "drift_gauge_rate": 0.32, "boost_speed_bonus": 12.0, "boost_accel": 45.0,
			"boost_duration": 2.2, "mini_boost_duration": 0.55, "wall_speed_keep": 0.55, "kart_hit_speed_keep": 0.82,
			"grip": 9.0, "drift_grip": 2.6, "gravity": 30.0, "offroad_max_speed_factor": 0.55}
	drift.configure(stats)
	collision_layer = LAYER_KARTS
	collision_mask = LAYER_WORLD | LAYER_WALLS | LAYER_KARTS
	floor_max_angle = deg_to_rad(40.0)
	floor_snap_length = 0.6
	floor_constant_speed = true
	floor_block_on_wall = false
	wall_min_slide_angle = deg_to_rad(5.0)
	safe_margin = 0.02
	var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs == null:
		cs = CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		var cap := CapsuleShape3D.new()
		cap.radius = 0.65
		cap.height = 2.3
		cs.shape = cap
		add_child(cs)
	cs.position = Vector3(0, 0.65, 0)
	cs.rotation_degrees = Vector3(90, 0, 0)
	# Body box with vertical sides, sized to the visible kart. Without it the
	# rounded capsule acts like a ramp and karts climb over / slide through
	# each other. Its bottom sits above the road so it never snags the floor.
	if get_node_or_null("BodyBox") == null:
		var bb := CollisionShape3D.new()
		bb.name = "BodyBox"
		var box := BoxShape3D.new()
		box.size = BODY_SIZE
		bb.shape = box
		bb.position = Vector3(0, 0.3 + BODY_SIZE.y / 2.0, 0.05)
		add_child(bb)
	if model == null:
		var q: Dictionary = GameFlow.quality_profile() if is_instance_valid(GameFlow) else {"particles": 1.0, "decor_lights": false}
		model = KartModel.new()
		model.name = "Model"
		add_child(model)
		model.build(kart_color, bool(q.get("decor_lights", false)) and is_player, float(q.get("particles", 1.0)))
	add_to_group("karts")


func setup(name_text: String, color: Color, player := false) -> void:
	display_name = name_text
	kart_color = color
	is_player = player
	if model:
		model.set_paint(color)


func forward() -> Vector3:
	return Vector3(-sin(heading), 0.0, -cos(heading))


static func yaw_of_basis(b: Basis) -> float:
	var f := -b.z
	return atan2(-f.x, -f.z)


func place(t: Transform3D) -> void:
	global_position = t.origin
	heading = yaw_of_basis(t.basis)
	travel_heading = heading
	rotation = Vector3(0.0, heading, 0.0)
	speed = 0.0
	vertical_speed = 0.0
	velocity = Vector3.ZERO
	drift.cancel()
	reset_physics_interpolation()


func max_speed_now() -> float:
	var m := float(stats["max_speed"]) * speed_multiplier
	if offroad:
		m *= float(stats["offroad_max_speed_factor"])
	return m


func speed_kmh() -> float:
	return absf(speed) * 3.6


func _physics_process(delta: float) -> void:
	if is_remote:
		# Ghost of another player: position comes from the network; only the
		# server-side item cooldown needs to tick here.
		if item_cooldown > 0.0:
			item_cooldown = maxf(0.0, item_cooldown - delta)
		_animate(delta)
		return
	sim_time += delta
	_tick_timers(delta)
	var bonus := boost.update(delta)
	if boost.just_ended:
		boost_ended.emit()
	var top := max_speed_now() + bonus
	var can_drive := control_enabled and spin_timer <= 0.0

	# --- longitudinal
	if can_drive:
		if brake_input:
			speed = move_toward(speed, 0.0, float(stats["brake_decel"]) * delta)
		elif speed < top:
			var acc := float(stats["acceleration"])
			if boost.active:
				acc += float(stats["boost_accel"])
			# Acceleration tapers near top speed for a natural feel.
			acc *= clampf(1.15 - speed / maxf(top, 1.0) * 0.6, 0.35, 1.15)
			speed = minf(top, speed + acc * delta)
		else:
			speed = move_toward(speed, top, float(stats["coast_decel"]) * 2.0 * delta)
	else:
		var decel := float(stats["coast_decel"]) * (4.0 if spin_timer > 0.0 else 1.0)
		speed = move_toward(speed, 0.0, decel * delta)

	# --- drift
	var steer := clampf(steer_input, -1.0, 1.0) if can_drive else 0.0
	var ev := drift.update(delta, drift_input and can_drive, steer, speed, is_on_floor())
	if ev == "start":
		drift_started.emit(drift.direction)
	elif ev == "end":
		var tier := drift.reward_tier()
		drift_ended.emit(drift.last_charge, tier)
		if tier > 0:
			apply_drift_boost(tier)
	if drift.drifting:
		boost_gauge = minf(1.0, boost_gauge + float(stats["drift_gauge_rate"]) * delta * (0.6 + 0.4 * absf(steer)))

	# --- steering
	var speed_factor := clampf(absf(speed) / 8.0, 0.0, 1.0)
	var hs_damp := 1.0 - 0.3 * clampf(speed / float(stats["max_speed"]), 0.0, 1.0)
	var turn := 0.0
	if drift.drifting:
		var d := float(drift.direction)
		var tight := clampf(0.75 + 0.55 * steer * d, 0.35, 1.3)
		turn = d * tight * float(stats["turn_speed"]) * float(stats["drift_turn_bonus"]) * speed_factor
	else:
		turn = steer * float(stats["turn_speed"]) * speed_factor * hs_damp
	heading = wrapf(heading - turn * delta, -PI, PI)
	var grip := float(stats["drift_grip"]) if drift.drifting else float(stats["grip"])
	travel_heading = lerp_angle(travel_heading, heading, clampf(grip * delta, 0.0, 1.0))

	# --- boost button
	if boost_request:
		boost_request = false
		try_use_boost()

	# --- vertical
	if is_on_floor():
		vertical_speed = -0.5
	else:
		vertical_speed = maxf(vertical_speed - float(stats["gravity"]) * delta, -60.0)

	var dir := Vector3(-sin(travel_heading), 0.0, -cos(travel_heading))
	velocity = dir * speed + Vector3.UP * vertical_speed
	rotation = Vector3(0.0, heading, 0.0)
	var pre_speed := speed
	move_and_slide()
	_handle_collisions(dir, pre_speed)
	_separate_from_karts()
	_animate(delta)


func _tick_timers(delta: float) -> void:
	if spin_timer > 0.0:
		spin_timer = maxf(0.0, spin_timer - delta)
	if shield_timer > 0.0:
		shield_timer = maxf(0.0, shield_timer - delta)
	if invulnerable_timer > 0.0:
		invulnerable_timer = maxf(0.0, invulnerable_timer - delta)
	if item_cooldown > 0.0:
		item_cooldown = maxf(0.0, item_cooldown - delta)
	for k in _impact_cd.keys():
		_impact_cd[k] = float(_impact_cd[k]) - delta


func _handle_collisions(dir: Vector3, pre_speed: float) -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		if absf(n.y) > 0.6:
			continue
		var hn := Vector3(n.x, 0.0, n.z).normalized()
		var into := -dir.dot(hn)
		if into <= 0.08:
			continue
		var strength := clampf(into * pre_speed / maxf(1.0, float(stats["max_speed"])), 0.0, 1.0)
		var other := c.get_collider()
		if other is KartController:
			var ok := other as KartController
			speed *= lerpf(1.0, float(stats["kart_hit_speed_keep"]), into)
			# Rear-end hit: hand some momentum to the kart in front.
			if ok.forward().dot(dir) > 0.5 and pre_speed > ok.speed:
				ok.speed += (pre_speed - ok.speed) * 0.35 * into
			ok.receive_bump(-hn, strength)
			_emit_impact("kart", strength)
		else:
			speed *= lerpf(1.0, float(stats["wall_speed_keep"]), clampf(into, 0.0, 1.0))
			# Deflect along the wall so the kart does not get stuck nose-first.
			var tangent := dir - hn * dir.dot(hn)
			if tangent.length() > 0.05:
				var th := atan2(-tangent.x, -tangent.z)
				heading = lerp_angle(heading, th, 0.55 * into)
				travel_heading = lerp_angle(travel_heading, th, 0.85)
			move_and_collide(hn * 0.04)
			if drift.drifting and into > 0.5:
				drift.cancel()
			_emit_impact("wall", strength)


## Safety net against interpenetration (e.g. two karts steering into each
## other in the same frame, or a network ghost teleporting onto us): push this
## kart out along the axis of least overlap, collision-checked.
func _separate_from_karts() -> void:
	for n in get_tree().get_nodes_in_group("karts"):
		var o := n as KartController
		if o == null or o == self or not o.is_inside_tree():
			continue
		if absf(global_position.y - o.global_position.y) > 1.2:
			continue
		var d := global_position - o.global_position
		var f := o.forward()
		var r := f.cross(Vector3.UP)
		var lat := d.dot(r)
		var lon := d.dot(f)
		var pen_lat := BODY_SIZE.x - absf(lat)
		var pen_lon := BODY_SIZE.z - absf(lon)
		if pen_lat <= 0.0 or pen_lon <= 0.0:
			continue
		var share := 1.0 if o.is_remote else 0.5
		var push: Vector3
		if pen_lat < pen_lon:
			push = r * (1.0 if lat >= 0.0 else -1.0) * pen_lat
		else:
			push = f * (1.0 if lon >= 0.0 else -1.0) * pen_lon
		move_and_collide(push * share)


func receive_bump(push_dir: Vector3, strength: float) -> void:
	if is_remote:
		return
	# Collision-checked push: a kart squeezed against a wall must not be
	# shoved through it.
	move_and_collide(Vector3(push_dir.x, 0.0, push_dir.z) * 0.08 * (0.5 + strength))
	speed *= lerpf(1.0, 0.92, strength)
	_emit_impact("kart", strength * 0.8)


func _emit_impact(kind: String, strength: float) -> void:
	if float(_impact_cd.get(kind, 0.0)) > 0.0:
		return
	_impact_cd[kind] = 0.25
	impact_count += 1
	last_impact = {"kind": kind, "strength": strength, "time": sim_time}
	impact.emit(kind, strength)


func try_use_boost() -> bool:
	if boost_gauge < 1.0 or not control_enabled:
		return false
	boost_gauge = 0.0
	boost.start(float(stats["boost_duration"]), float(stats["boost_speed_bonus"]), "boost")
	boost_started.emit("boost")
	return true


## Instant drift boost: immediate speed kick + short boost, stronger per tier.
func apply_drift_boost(tier: int) -> void:
	var durations: Array = stats.get("drift_boost_durations", [0.4, 0.7, 1.1])
	var kicks: Array = stats.get("drift_boost_kicks", [3.0, 4.5, 6.0])
	var bonus_scale: Array = stats.get("drift_boost_bonus_scale", [0.5, 0.65, 0.85])
	var i := clampi(tier, 1, 3) - 1
	boost.start(float(durations[i]), float(stats["boost_speed_bonus"]) * float(bonus_scale[i]), "mini")
	speed = minf(speed + float(kicks[i]), max_speed_now() + boost.bonus)
	boost_started.emit("mini")
	drift_boost.emit(tier)


func apply_turbo(duration: float, bonus: float) -> void:
	boost.start(duration, bonus, "turbo")
	boost_started.emit("turbo")


## Item hit (missile / trap). Returns false if blocked by shield or invulnerable.
func apply_item_hit(spin_sec: float) -> bool:
	if invulnerable_timer > 0.0:
		return false
	if shield_timer > 0.0:
		shield_timer = 0.0
		invulnerable_timer = 0.5
		return false
	spin_timer = spin_sec
	invulnerable_timer = spin_sec + 1.5
	speed *= 0.3
	drift.cancel()
	boost.stop()
	_emit_impact("item", 0.85)
	return true


func give_item(item: String) -> void:
	held_item = item
	item_changed.emit(item)


func consume_item() -> String:
	var it := held_item
	held_item = ""
	item_cooldown = 1.0
	item_changed.emit("")
	return it


func respawn_at(t: Transform3D) -> void:
	place(Transform3D(t.basis, t.origin + Vector3.UP * 0.8))
	spin_timer = 0.0
	boost.stop()
	invulnerable_timer = 1.5
	respawned.emit()


func _animate(delta: float) -> void:
	if model == null:
		return
	var drift_dir := drift.direction if drift.drifting else 0
	model.animate(delta, speed, steer_input if control_enabled else 0.0, drift_dir, drift.charge, boost.active, spin_timer)
	model.shield_bubble.visible = shield_timer > 0.0
	# Visual pitch/roll to floor normal on slopes.
	if is_on_floor() and not is_remote:
		var n := get_floor_normal()
		var local_n := global_transform.basis.inverse() * n
		var pitch := atan2(local_n.z, local_n.y)
		model.rotation.x = lerp_angle(model.rotation.x, pitch, minf(1.0, delta * 8.0))
