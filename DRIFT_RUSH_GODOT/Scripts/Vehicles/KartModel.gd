class_name KartModel
extends Node3D
## Procedural stylized kart: chassis, 4 wheels (spin + steer), driver with
## helmet, spoiler, neon-blue exhaust, headlights, drift sparks, boost flames,
## shield bubble. Forward is -Z. Origin = ground contact center.

var paint_mat: StandardMaterial3D
var helmet_mat: StandardMaterial3D
var body: Node3D            # leans / drift-yaws / spins
var wheels: Array[Node3D] = []      # spin nodes
var front_pivots: Array[Node3D] = []
var spark_emitters: Array[CPUParticles3D] = []
var flame_emitters: Array[CPUParticles3D] = []
var smoke_emitters: Array[CPUParticles3D] = []
var exhaust_glow: Array[MeshInstance3D] = []
var shield_bubble: MeshInstance3D
var name_tag: Label3D
var headlights: Array[SpotLight3D] = []
var _wheel_angle := 0.0
var particle_scale := 1.0


func build(color: Color, with_lights := false, particles := 1.0) -> void:
	particle_scale = particles
	paint_mat = MeshFactory.unique_mat(color, 0.38, 0.25)
	helmet_mat = MeshFactory.unique_mat(color.lightened(0.1), 0.3, 0.1)
	var white := MeshFactory.mat(Color(0.96, 0.96, 0.98), 0.45, 0.05)
	var dark := MeshFactory.mat(Color(0.12, 0.13, 0.17), 0.7, 0.2)
	var metal := MeshFactory.mat(Color(0.72, 0.75, 0.82), 0.3, 0.75)
	var tire := MeshFactory.mat(Color(0.08, 0.08, 0.1), 0.9, 0.0, 0.0, 0.0)
	var neon := MeshFactory.mat(Color(0.2, 0.75, 1.0), 0.2, 0.0, 3.0)
	var skin := MeshFactory.mat(Color(1.0, 0.82, 0.68), 0.7, 0.0)
	var visor := MeshFactory.mat(Color(0.08, 0.15, 0.35), 0.1, 0.6)

	body = Node3D.new()
	body.name = "Body"
	add_child(body)

	# --- chassis
	MeshFactory.add(body, MeshFactory.box(Vector3(1.45, 0.16, 2.3)), dark, Vector3(0, 0.32, 0))
	MeshFactory.add(body, MeshFactory.tapered_box(Vector2(1.3, 2.1), Vector2(0.95, 1.35), 0.34, 0.15), paint_mat, Vector3(0, 0.4, 0))
	MeshFactory.add(body, MeshFactory.tapered_box(Vector2(1.05, 0.85), Vector2(0.45, 0.45), 0.24, -0.15), paint_mat, Vector3(0, 0.38, -1.2))
	# white racing stripes
	MeshFactory.add(body, MeshFactory.box(Vector3(0.14, 0.02, 1.25)), white, Vector3(-0.14, 0.745, 0.15))
	MeshFactory.add(body, MeshFactory.box(Vector3(0.14, 0.02, 1.25)), white, Vector3(0.14, 0.745, 0.15))
	MeshFactory.add(body, MeshFactory.box(Vector3(0.1, 0.02, 0.5)), white, Vector3(0, 0.63, -1.15))
	# front wing
	MeshFactory.add(body, MeshFactory.box(Vector3(1.85, 0.07, 0.36)), white, Vector3(0, 0.3, -1.5))
	MeshFactory.add(body, MeshFactory.box(Vector3(0.06, 0.22, 0.4)), paint_mat, Vector3(-0.92, 0.36, -1.5))
	MeshFactory.add(body, MeshFactory.box(Vector3(0.06, 0.22, 0.4)), paint_mat, Vector3(0.92, 0.36, -1.5))
	# side pods
	for sx in [-1.0, 1.0]:
		MeshFactory.add(body, MeshFactory.tapered_box(Vector2(0.38, 1.25), Vector2(0.3, 0.9), 0.3, 0.1), white, Vector3(sx * 0.74, 0.36, 0.1))
		MeshFactory.add(body, MeshFactory.box(Vector3(0.05, 0.12, 0.8)), paint_mat, Vector3(sx * 0.9, 0.5, 0.1))
	# seat + engine
	MeshFactory.add(body, MeshFactory.box(Vector3(0.62, 0.55, 0.14)), dark, Vector3(0, 0.95, 0.5), Vector3(-12, 0, 0))
	MeshFactory.add(body, MeshFactory.box(Vector3(0.9, 0.42, 0.6)), dark, Vector3(0, 0.66, 0.95))
	MeshFactory.add(body, MeshFactory.box(Vector3(0.7, 0.12, 0.45)), metal, Vector3(0, 0.92, 0.95))
	for ex in [-0.26, 0.26]:
		MeshFactory.add(body, MeshFactory.cylinder(0.08, 0.1, 0.4, 10), metal, Vector3(ex, 0.62, 1.32), Vector3(90, 0, 0))
		var glow := MeshFactory.add(body, MeshFactory.cylinder(0.075, 0.075, 0.05, 10), neon, Vector3(ex, 0.62, 1.53), Vector3(90, 0, 0))
		exhaust_glow.append(glow)
	# spoiler
	for sx in [-0.48, 0.48]:
		MeshFactory.add(body, MeshFactory.box(Vector3(0.06, 0.42, 0.08)), dark, Vector3(sx, 1.05, 1.18))
	MeshFactory.add(body, MeshFactory.tapered_box(Vector2(1.7, 0.42), Vector2(1.7, 0.3), 0.07, 0.05), paint_mat, Vector3(0, 1.25, 1.2))
	MeshFactory.add(body, MeshFactory.box(Vector3(0.05, 0.28, 0.46)), white, Vector3(-0.86, 1.3, 1.2))
	MeshFactory.add(body, MeshFactory.box(Vector3(0.05, 0.28, 0.46)), white, Vector3(0.86, 1.3, 1.2))
	# headlights
	var hl_mat := MeshFactory.mat(Color(0.75, 0.92, 1.0), 0.2, 0.0, 2.5)
	for hx in [-0.33, 0.33]:
		MeshFactory.add(body, MeshFactory.box(Vector3(0.22, 0.07, 0.04)), hl_mat, Vector3(hx, 0.5, -1.62), Vector3(-20, 0, 0))
		if with_lights:
			var sl := SpotLight3D.new()
			sl.light_color = Color(0.85, 0.95, 1.0)
			sl.light_energy = 1.5
			sl.spot_range = 14.0
			sl.spot_angle = 28.0
			sl.position = Vector3(hx, 0.5, -1.65)
			body.add_child(sl)
			headlights.append(sl)
	# steering wheel
	var sw := TorusMesh.new()
	sw.inner_radius = 0.11
	sw.outer_radius = 0.15
	MeshFactory.add(body, sw, dark, Vector3(0, 0.98, -0.2), Vector3(60, 0, 0))
	# driver (chibi proportions: big helmet)
	MeshFactory.add(body, MeshFactory.capsule(0.26, 0.75), paint_mat, Vector3(0, 1.0, 0.2))
	MeshFactory.add(body, MeshFactory.capsule(0.08, 0.5), white, Vector3(-0.22, 1.05, -0.08), Vector3(70, 0, 15))
	MeshFactory.add(body, MeshFactory.capsule(0.08, 0.5), white, Vector3(0.22, 1.05, -0.08), Vector3(70, 0, -15))
	MeshFactory.add(body, MeshFactory.sphere(0.25), skin, Vector3(0, 1.48, 0.12))
	var helmet := MeshFactory.add(body, MeshFactory.sphere(0.34, 18, 10), helmet_mat, Vector3(0, 1.56, 0.14))
	helmet.name = "Helmet"
	MeshFactory.add(body, MeshFactory.sphere(0.345, 18, 10), white, Vector3(0, 1.58, 0.16), Vector3.ZERO, Vector3(0.35, 1.0, 1.0))
	MeshFactory.add(body, MeshFactory.box(Vector3(0.44, 0.15, 0.1)), visor, Vector3(0, 1.52, -0.17), Vector3(8, 0, 0))

	# --- wheels
	var wheel_defs := [
		[Vector3(-0.8, 0.32, -0.88), 0.32, 0.3, true],
		[Vector3(0.8, 0.32, -0.88), 0.32, 0.3, true],
		[Vector3(-0.82, 0.38, 0.82), 0.38, 0.4, false],
		[Vector3(0.82, 0.38, 0.82), 0.38, 0.4, false],
	]
	for wd in wheel_defs:
		var pivot := Node3D.new()
		pivot.position = wd[0]
		body.add_child(pivot)
		var spin := Node3D.new()
		pivot.add_child(spin)
		var r: float = wd[1]
		var w: float = wd[2]
		MeshFactory.add(spin, MeshFactory.cylinder(r, r, w, 14), tire, Vector3.ZERO, Vector3(0, 0, 90))
		MeshFactory.add(spin, MeshFactory.cylinder(r * 0.6, r * 0.6, w + 0.02, 10), metal, Vector3.ZERO, Vector3(0, 0, 90))
		MeshFactory.add(spin, MeshFactory.cylinder(r * 0.25, r * 0.25, w + 0.05, 6), paint_mat, Vector3.ZERO, Vector3(0, 0, 90))
		# tread block so rotation is visible
		MeshFactory.add(spin, MeshFactory.box(Vector3(w + 0.01, 0.06, 0.12)), MeshFactory.mat(Color(0.25, 0.25, 0.28), 0.9), Vector3(0, r - 0.02, 0))
		wheels.append(spin)
		if wd[3]:
			front_pivots.append(pivot)
		# drift sparks + tire smoke at rear wheels
		if not wd[3]:
			var sp := _make_sparks()
			sp.position = Vector3(wd[0].x, 0.05, wd[0].z + 0.3)
			add_child(sp)
			spark_emitters.append(sp)
			var sm := _make_smoke()
			sm.position = Vector3(wd[0].x, 0.15, wd[0].z + 0.3)
			add_child(sm)
			smoke_emitters.append(sm)

	for ex in [-0.26, 0.26]:
		var fl := _make_flame()
		fl.position = Vector3(ex, 0.62, 1.6)
		body.add_child(fl)
		flame_emitters.append(fl)

	shield_bubble = MeshFactory.add(self, MeshFactory.sphere(1.7, 20, 10), MeshFactory.mat(Color(0.3, 0.8, 1.0, 0.28), 0.1, 0.0, 1.2, 0.0), Vector3(0, 0.8, 0))
	shield_bubble.visible = false

	name_tag = MeshFactory.label3d("", 48, Color.WHITE)
	name_tag.position = Vector3(0, 2.4, 0)
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.no_depth_test = false
	name_tag.visible = false
	add_child(name_tag)


func set_paint(color: Color) -> void:
	if paint_mat:
		paint_mat.albedo_color = color
		helmet_mat.albedo_color = color.lightened(0.1)


func set_name_tag(text: String, col := Color.WHITE) -> void:
	name_tag.text = text
	name_tag.modulate = col
	name_tag.visible = text != ""


func _make_sparks() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(4, int(24 * particle_scale))
	p.lifetime = 0.35
	p.emitting = false
	p.local_coords = false
	p.direction = Vector3(0, 0.6, 1)
	p.spread = 35.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -9, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	p.mesh = q
	p.material_override = MeshFactory.particle_material(Color.WHITE, true)
	p.color = Color(1.0, 0.7, 0.2)
	p.color_ramp = MeshFactory.fade_gradient(Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	return p


func _make_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(4, int(16 * particle_scale))
	p.lifetime = 0.8
	p.emitting = false
	p.local_coords = false
	p.direction = Vector3(0, 1, 0.5)
	p.spread = 30.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.5
	p.gravity = Vector3(0, 0.5, 0)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	p.mesh = q
	p.material_override = MeshFactory.particle_material(Color.WHITE, false)
	p.color = Color(0.95, 0.95, 1.0, 0.5)
	p.color_ramp = MeshFactory.fade_gradient(Color(1, 1, 1, 0.55), Color(1, 1, 1, 0))
	return p


func _make_flame() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(6, int(28 * particle_scale))
	p.lifetime = 0.25
	p.emitting = false
	p.local_coords = false
	p.direction = Vector3(0, 0, 1)
	p.spread = 8.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.0
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	p.mesh = q
	p.material_override = MeshFactory.particle_material(Color.WHITE, true)
	p.color = Color(0.25, 0.7, 1.0)
	var g := Gradient.new()
	g.set_color(0, Color(0.9, 1.0, 1.0, 1.0))
	g.set_color(1, Color(0.2, 0.3, 1.0, 0.0))
	p.color_ramp = g
	return p


## Called every frame by KartController.
func animate(dt: float, speed: float, steer: float, drift_dir: int, drift_charge: float, boosting: bool, spin_t: float) -> void:
	_wheel_angle += speed * dt / 0.36
	for w in wheels:
		w.rotation.x = -_wheel_angle
	for fp in front_pivots:
		fp.rotation.y = lerpf(fp.rotation.y, -steer * 0.45, minf(1.0, dt * 12.0))
	var target_yaw := -float(drift_dir) * 0.38
	var target_roll := steer * 0.06 + float(drift_dir) * 0.05
	if spin_t > 0.0:
		body.rotation.y += dt * 14.0
	else:
		body.rotation.y = lerp_angle(body.rotation.y, target_yaw, minf(1.0, dt * 8.0))
	body.rotation.z = lerpf(body.rotation.z, target_roll, minf(1.0, dt * 6.0))
	var drifting := drift_dir != 0
	var spark_col := Color(1.0, 0.65, 0.2)
	if drift_charge >= 0.9:
		spark_col = Color(0.75, 0.35, 1.0)
	elif drift_charge >= 0.45:
		spark_col = Color(0.3, 0.75, 1.0)
	for s in spark_emitters:
		s.emitting = drifting and particle_scale > 0.0
		s.color = spark_col
	for s in smoke_emitters:
		s.emitting = drifting and particle_scale > 0.3
	for f in flame_emitters:
		f.emitting = boosting and particle_scale > 0.0
	for g in exhaust_glow:
		g.scale = Vector3.ONE * (1.8 if boosting else 1.0)
