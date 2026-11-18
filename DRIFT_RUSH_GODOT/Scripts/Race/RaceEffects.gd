class_name RaceEffects
extends Node3D
## Visual race effects that are not part of a single kart:
##  · tyre skid marks left on the road while drifting (ring-buffer MultiMesh)
##  · start lights on the gantry (red 3-2-1, green on GO)
##  · finish celebration: confetti burst + fireworks over the line
##  · map ambience: seagulls (Coral Coast), rain streaks (Neon City),
##    drifting cloud layer (Sakura Valley)

const MAX_MARKS := 900
const MARK_SPACING := 0.55

var race: RaceManager
var track: TrackBuilder
var camera: Camera3D
var skid_mm: MultiMesh
var _next := 0
var marks_placed := 0
var _last_mark: Dictionary = {}       # kart -> [left_pos, right_pos]
var start_lamps: Array[MeshInstance3D] = []
var _red := StandardMaterial3D.new()
var _red_on := StandardMaterial3D.new()
var _green_on := StandardMaterial3D.new()
var _gulls: Array[Dictionary] = []
var _t := 0.0
var quality: Dictionary = {}


func setup(r: RaceManager, t: TrackBuilder, cam: Camera3D) -> void:
	race = r
	track = t
	camera = cam
	quality = GameFlow.quality_profile()
	_build_skids()
	_build_start_lights()
	r.countdown_tick.connect(_on_countdown)
	r.kart_finished.connect(_on_kart_finished)
	match track.track_id:
		"coral_coast":
			_seagulls()
		"neon_city":
			_rain()


# ------------------------------------------------------------- skid marks
func _build_skids() -> void:
	skid_mm = MultiMesh.new()
	skid_mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2(0.32, MARK_SPACING + 0.05)
	q.orientation = PlaneMesh.FACE_Y
	skid_mm.mesh = q
	skid_mm.instance_count = MAX_MARKS
	skid_mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = "SkidMarks"
	mi.multimesh = skid_mm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.06, 0.06, 0.08, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _physics_process(_delta: float) -> void:
	if race == null:
		return
	for k in race.karts:
		if not is_instance_valid(k):
			continue
		if not (k.drift.drifting and k.is_on_floor()) and not (k.is_remote and k.drift.drifting):
			_last_mark.erase(k)
			continue
		var b := k.global_transform.basis
		var rear := k.global_position + b * Vector3(0, 0.07, 0.85)
		var right := (b * Vector3.RIGHT).normalized()
		var lp := rear - right * 0.82
		var rp := rear + right * 0.82
		if _last_mark.has(k):
			var prev: Array = _last_mark[k]
			if (prev[0] as Vector3).distance_to(lp) < MARK_SPACING:
				continue
			_place(prev[0], lp)
			_place(prev[1], rp)
		_last_mark[k] = [lp, rp]


func _place(a: Vector3, b: Vector3) -> void:
	var dir := b - a
	if dir.length() < 0.05:
		return
	var basis := Basis.looking_at(dir.normalized(), Vector3.UP)
	skid_mm.set_instance_transform(_next, Transform3D(basis.scaled(Vector3(1, 1, dir.length() / MARK_SPACING)), (a + b) / 2.0))
	_next = (_next + 1) % MAX_MARKS
	marks_placed += 1
	skid_mm.visible_instance_count = mini(marks_placed, MAX_MARKS)


# ------------------------------------------------------------- start lights
func _build_start_lights() -> void:
	var g := track.get_node_or_null("StartGantry") as Node3D
	if g == null:
		return
	_red.albedo_color = Color(0.25, 0.04, 0.05)
	_red_on.albedo_color = Color(1.0, 0.1, 0.12)
	_red_on.emission_enabled = true
	_red_on.emission = Color(1.0, 0.1, 0.12)
	_red_on.emission_energy_multiplier = 4.0
	_green_on.albedo_color = Color(0.2, 1.0, 0.35)
	_green_on.emission_enabled = true
	_green_on.emission = Color(0.2, 1.0, 0.35)
	_green_on.emission_energy_multiplier = 4.0
	var housing := MeshFactory.mat(Color(0.08, 0.08, 0.12), 0.5, 0.3)
	MeshFactory.add(g, MeshFactory.box(Vector3(4.6, 1.1, 0.5)), housing, Vector3(0, 4.85, 0.1))
	for i in 3:
		var lamp := MeshFactory.add(g, MeshFactory.sphere(0.36, 14, 8), _red, Vector3(-1.4 + i * 1.4, 4.85, 0.42))
		start_lamps.append(lamp)


func set_lights(red_count: int, green: bool) -> void:
	for i in start_lamps.size():
		if green:
			start_lamps[i].material_override = _green_on
		else:
			start_lamps[i].material_override = _red_on if i < red_count else _red


func _on_countdown(n: int) -> void:
	if n > 0:
		set_lights(4 - n, false)
	else:
		set_lights(3, true)


# ------------------------------------------------------------- finish celebration
func _on_kart_finished(k: KartController, _rank: int, _t: float) -> void:
	if not k.is_player:
		return
	var burst := CPUParticles3D.new()
	burst.name = "Confetti"
	burst.one_shot = true
	burst.amount = int(160 * maxf(0.4, float(quality.get("particles", 1.0))))
	burst.lifetime = 3.0
	burst.explosiveness = 0.9
	burst.direction = Vector3(0, 1, 0)
	burst.spread = 85.0
	burst.initial_velocity_min = 3.0
	burst.initial_velocity_max = 7.5
	burst.gravity = Vector3(0, -3.5, 0)
	burst.damping_min = 0.5
	burst.damping_max = 1.5
	burst.angular_velocity_min = -360
	burst.angular_velocity_max = 360
	burst.scale_amount_min = 0.8
	burst.scale_amount_max = 1.6
	var q := QuadMesh.new()
	q.size = Vector2(0.18, 0.1)
	burst.mesh = q
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	burst.material_override = m
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 0.3, 0.4), Color(1, 0.85, 0.2), Color(0.3, 0.8, 1.0), Color(0.6, 1.0, 0.4), Color(1, 0.5, 0.9)])
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	burst.color_initial_ramp = grad
	add_child(burst)
	# In front of the kart so it rains down across the chase camera's view.
	burst.global_position = k.global_position + k.forward() * 5.0 + Vector3.UP * 3.5
	burst.emitting = true
	var gantry := track.get_node_or_null("StartGantry") as Node3D
	var base := gantry.global_position if gantry else k.global_position
	for i in 4:
		get_tree().create_timer(0.3 + i * 0.45).timeout.connect(_firework.bind(base + Vector3(randf_range(-14, 14), randf_range(16, 24), randf_range(-10, 10))))


func _firework(pos: Vector3) -> void:
	if not is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 90
	p.lifetime = 1.6
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 7.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector3(0, -3, 0)
	p.damping_min = 2.0
	p.damping_max = 3.0
	var s := SphereMesh.new()
	s.radius = 0.12
	s.height = 0.24
	s.radial_segments = 6
	s.rings = 3
	p.mesh = s
	var col: Color = [Color(1, 0.4, 0.6), Color(0.4, 0.9, 1), Color(1, 0.9, 0.3), Color(0.7, 0.5, 1)][randi() % 4]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.vertex_color_use_as_albedo = true
	p.material_override = m
	p.color_ramp = MeshFactory.fade_gradient(Color(col.r * 2.0, col.g * 2.0, col.b * 2.0, 1.0), Color(col.r, col.g, col.b, 0.0))
	add_child(p)
	p.global_position = pos
	p.emitting = true
	AudioFeedback.play_at("item", pos, -10.0)


# ------------------------------------------------------------- ambience
func _seagulls() -> void:
	var wing := MeshFactory.mat(Color(0.97, 0.97, 0.97), 0.8)
	for i in 7:
		var g := Node3D.new()
		add_child(g)
		MeshFactory.add(g, MeshFactory.capsule(0.12, 0.6), wing, Vector3.ZERO, Vector3(90, 0, 0))
		var lw := MeshFactory.add(g, MeshFactory.box(Vector3(0.9, 0.03, 0.3)), wing, Vector3(-0.45, 0, 0))
		var rw := MeshFactory.add(g, MeshFactory.box(Vector3(0.9, 0.03, 0.3)), wing, Vector3(0.45, 0, 0))
		_gulls.append({"node": g, "lw": lw, "rw": rw, "c": Vector3(randf_range(40, 160), randf_range(14, 26), randf_range(-120, 150)),
			"r": randf_range(14, 30), "speed": randf_range(0.25, 0.45) * (1 if i % 2 == 0 else -1), "ph": randf() * TAU})


func _rain() -> void:
	if camera == null or float(quality.get("particles", 1.0)) < 0.5:
		return
	var p := CPUParticles3D.new()
	p.name = "Rain"
	p.amount = int(260 * float(quality.get("particles", 1.0)))
	p.lifetime = 0.7
	p.preprocess = 1.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(20, 1, 22)
	p.direction = Vector3(0.1, -1, 0)
	p.spread = 3.0
	p.initial_velocity_min = 26.0
	p.initial_velocity_max = 32.0
	p.gravity = Vector3.ZERO
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.9)
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.albedo_color = Color(0.7, 0.85, 1.0, 0.35)
	p.material_override = m
	p.position = Vector3(0, 12, -10)
	camera.add_child(p)


func _process(delta: float) -> void:
	_t += delta
	for g in _gulls:
		var n: Node3D = g["node"]
		var a := _t * float(g["speed"]) + float(g["ph"])
		var c: Vector3 = g["c"]
		n.position = c + Vector3(cos(a), sin(a * 2.0) * 0.08, sin(a)) * float(g["r"])
		var tangent := Vector3(-sin(a), 0, cos(a)) * signf(float(g["speed"]))
		n.look_at(n.position + tangent, Vector3.UP)
		var flap := sin(_t * 9.0 + float(g["ph"])) * 0.5
		(g["lw"] as Node3D).rotation.z = flap
		(g["rw"] as Node3D).rotation.z = -flap
