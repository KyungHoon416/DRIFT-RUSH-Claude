class_name KartModel
extends Node3D
## Procedural stylized kart: chassis, 4 wheels (spin + steer), driver with
## helmet, spoiler, neon-blue exhaust, headlights, drift sparks, boost flames,
## shield bubble. Forward is -Z. Origin = ground contact center.

var paint_mat: StandardMaterial3D
var helmet_mat: StandardMaterial3D
var accent_mat: StandardMaterial3D
var number_label: Label3D
var underglow: MeshInstance3D
var kart_type := "rocket"
var exhaust_points: Array = []
var driver_offset := Vector3.ZERO

## Wheel layout per kart type: [position, radius, width, is_front]
const WHEELS := {
	"rocket": [[Vector3(-0.82, 0.32, -0.9), 0.32, 0.28, true], [Vector3(0.82, 0.32, -0.9), 0.32, 0.28, true],
		[Vector3(-0.85, 0.38, 0.84), 0.38, 0.38, false], [Vector3(0.85, 0.38, 0.84), 0.38, 0.38, false]],
	"bolt": [[Vector3(-0.8, 0.28, -1.05), 0.28, 0.26, true], [Vector3(0.8, 0.28, -1.05), 0.28, 0.26, true],
		[Vector3(-0.84, 0.34, 0.95), 0.34, 0.42, false], [Vector3(0.84, 0.34, 0.95), 0.34, 0.42, false]],
	"bubble": [[Vector3(-0.78, 0.36, -0.78), 0.36, 0.34, true], [Vector3(0.78, 0.36, -0.78), 0.36, 0.34, true],
		[Vector3(-0.78, 0.36, 0.78), 0.36, 0.34, false], [Vector3(0.78, 0.36, 0.78), 0.36, 0.34, false]],
	"drifter": [[Vector3(-0.84, 0.3, -0.92), 0.3, 0.3, true], [Vector3(0.84, 0.3, -0.92), 0.3, 0.3, true],
		[Vector3(-0.9, 0.44, 0.86), 0.44, 0.5, false], [Vector3(0.9, 0.44, 0.86), 0.44, 0.5, false]],
}
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


func build(color: Color, with_lights := false, particles := 1.0, type_id := "rocket") -> void:
	kart_type = type_id if WHEELS.has(type_id) else "rocket"
	particle_scale = particles
	paint_mat = MeshFactory.unique_mat(color, 0.3, 0.3)
	paint_mat.clearcoat_enabled = true
	paint_mat.clearcoat = 0.6
	paint_mat.clearcoat_roughness = 0.2
	accent_mat = MeshFactory.unique_mat(color.darkened(0.35), 0.4, 0.2)
	helmet_mat = MeshFactory.unique_mat(color.lightened(0.08), 0.22, 0.15)
	var white := MeshFactory.mat(Color(0.97, 0.97, 0.99), 0.35, 0.05)
	var carbon := MeshFactory.mat(Color(0.1, 0.11, 0.15), 0.55, 0.35)
	var metal := MeshFactory.mat(Color(0.78, 0.8, 0.86), 0.22, 0.85)
	var chrome := MeshFactory.mat(Color(0.9, 0.92, 0.96), 0.12, 0.95)
	var tire := MeshFactory.mat(Color(0.07, 0.07, 0.09), 0.85, 0.0, 0.0, 0.0)
	var neon := MeshFactory.mat(Color(0.2, 0.75, 1.0), 0.2, 0.0, 3.5)
	var skin := MeshFactory.mat(Color(1.0, 0.83, 0.7), 0.7, 0.0)
	var visor := MeshFactory.mat(Color(0.06, 0.12, 0.3), 0.05, 0.7, 0.0, 0.6)
	var glove := MeshFactory.mat(Color(0.2, 0.22, 0.3), 0.6)

	body = Node3D.new()
	body.name = "Body"
	add_child(body)

	match kart_type:
		"bolt":
			_body_bolt(white, carbon, metal, chrome, neon, with_lights)
		"bubble":
			_body_bubble(white, carbon, metal, chrome, neon, with_lights)
		"drifter":
			_body_drifter(white, carbon, metal, chrome, neon, with_lights)
		_:
			_body_rocket(white, carbon, metal, chrome, neon, with_lights)

	# --- driver (chibi: big glossy helmet)
	var drv := Node3D.new()
	drv.name = "Driver"
	drv.position = driver_offset
	body.add_child(drv)
	MeshFactory.add(drv, MeshFactory.capsule(0.27, 0.72), paint_mat, Vector3(0, 1.0, 0.22))
	MeshFactory.add(drv, MeshFactory.box(Vector3(0.36, 0.08, 0.03)), white, Vector3(0, 1.12, -0.04))
	for sx in [-1.0, 1.0]:
		MeshFactory.add(drv, MeshFactory.capsule(0.08, 0.48), white, Vector3(sx * 0.21, 1.03, -0.05), Vector3(68, 0, -sx * 15.0))
		MeshFactory.add(drv, MeshFactory.sphere(0.08, 8, 5), glove, Vector3(sx * 0.12, 0.99, -0.24))
	MeshFactory.add(drv, MeshFactory.sphere(0.24), skin, Vector3(0, 1.47, 0.12))
	var helmet := MeshFactory.add(drv, MeshFactory.sphere(0.36, 20, 12), helmet_mat, Vector3(0, 1.58, 0.15))
	helmet.name = "Helmet"
	var band := TorusMesh.new()
	band.inner_radius = 0.33
	band.outer_radius = 0.37
	band.rings = 24
	MeshFactory.add(drv, band, white, Vector3(0, 1.6, 0.15), Vector3(90, 90, 0), Vector3(1.0, 1.0, 0.35))
	MeshFactory.add(drv, MeshFactory.sphere(0.3, 16, 8), visor, Vector3(0, 1.55, -0.03), Vector3.ZERO, Vector3(0.95, 0.5, 0.55))
	MeshFactory.add(drv, MeshFactory.sphere(0.06, 8, 5), white, Vector3(0, 1.95, 0.18))
	# little spoiler fin on the helmet
	MeshFactory.add(drv, MeshFactory.box(Vector3(0.04, 0.1, 0.3)), accent_mat, Vector3(0, 1.93, 0.3))

	# --- wheels: rounded torus tyres + spoked rims (layout per kart type)
	var wheel_defs: Array = WHEELS.get(kart_type, WHEELS["rocket"])
	for wd in wheel_defs:
		var pivot := Node3D.new()
		pivot.position = wd[0]
		body.add_child(pivot)
		var spin := Node3D.new()
		pivot.add_child(spin)
		var r: float = wd[1]
		var w: float = wd[2]
		var tor := TorusMesh.new()
		tor.inner_radius = r * 0.5
		tor.outer_radius = r
		tor.rings = 22
		tor.ring_segments = 10
		MeshFactory.add(spin, tor, tire, Vector3.ZERO, Vector3(0, 0, 90), Vector3(1.0, w / (r * 0.5), 1.0))
		MeshFactory.add(spin, MeshFactory.cylinder(r * 0.62, r * 0.62, w * 0.8, 16), tire, Vector3.ZERO, Vector3(0, 0, 90))
		var side := signf(float(wd[0].x))
		MeshFactory.add(spin, MeshFactory.cylinder(r * 0.52, r * 0.52, 0.04, 16), metal, Vector3(side * w * 0.42, 0, 0), Vector3(0, 0, 90))
		for k in 5:
			var spoke := Node3D.new()
			spoke.rotation.x = TAU * k / 5.0
			spoke.position.x = side * w * 0.45
			spin.add_child(spoke)
			MeshFactory.add(spoke, MeshFactory.box(Vector3(0.03, r * 0.85, 0.07)), chrome, Vector3(0, r * 0.2, 0))
		MeshFactory.add(spin, MeshFactory.cylinder(r * 0.16, r * 0.16, 0.06, 10), paint_mat, Vector3(side * w * 0.47, 0, 0), Vector3(0, 0, 90))
		wheels.append(spin)
		if wd[3]:
			front_pivots.append(pivot)
		else:
			var sp := _make_sparks()
			sp.position = Vector3(wd[0].x, 0.05, wd[0].z + 0.3)
			add_child(sp)
			spark_emitters.append(sp)
			var sm := _make_smoke()
			sm.position = Vector3(wd[0].x, 0.15, wd[0].z + 0.3)
			add_child(sm)
			smoke_emitters.append(sm)

	for ep in exhaust_points:
		var fl := _make_flame()
		fl.position = ep
		body.add_child(fl)
		flame_emitters.append(fl)

	# soft contact shadow (cheap, helps when real shadows are off on "low")
	var blob := MeshFactory.add(self, MeshFactory.cylinder(1.1, 1.1, 0.01, 20), MeshFactory.mat(Color(0, 0, 0, 0.35), 1.0, 0.0, 0.0, 0.0), Vector3(0, 0.03, 0.05), Vector3.ZERO, Vector3(0.85, 1.0, 1.25))
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	shield_bubble = MeshFactory.add(self, MeshFactory.sphere(1.7, 20, 10), MeshFactory.mat(Color(0.3, 0.8, 1.0, 0.28), 0.1, 0.0, 1.2, 0.0), Vector3(0, 0.8, 0))
	shield_bubble.visible = false

	name_tag = MeshFactory.label3d("", 48, Color.WHITE)
	name_tag.position = Vector3(0, 2.45, 0)
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.no_depth_test = false
	name_tag.visible = false
	add_child(name_tag)


## Night tracks: coloured neon glow under the kart + a small fill light.
func set_underglow(on: bool, col := Color(0.2, 0.8, 1.0)) -> void:
	if on and underglow == null:
		underglow = MeshFactory.add(self, MeshFactory.cylinder(1.0, 1.0, 0.01, 24), MeshFactory.mat(Color(col.r, col.g, col.b, 0.55), 1.0, 0.0, 3.0, 0.0), Vector3(0, 0.05, 0.05), Vector3.ZERO, Vector3(0.95, 1.0, 1.35))
		underglow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var fill := OmniLight3D.new()
		fill.light_color = col.lightened(0.3)
		fill.light_energy = 1.2
		fill.omni_range = 3.5
		fill.position = Vector3(0, 1.6, 0.6)
		underglow.add_child(fill)
	if underglow:
		underglow.visible = on


func set_number(n: int) -> void:
	if number_label:
		number_label.text = str(n)


func set_paint(color: Color) -> void:
	if paint_mat:
		paint_mat.albedo_color = color
		accent_mat.albedo_color = color.darkened(0.35)
		helmet_mat.albedo_color = color.lightened(0.08)


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


# ------------------------------------------------------------- kart bodies
func _body_rocket(white: Material, carbon: Material, metal: Material, chrome: Material, neon: Material, with_lights: bool) -> void:
	# --- chassis: carbon floor + rounded paint tub (capsules/spheres = toy look)
	MeshFactory.add(body, MeshFactory.box(Vector3(1.5, 0.12, 2.35)), carbon, Vector3(0, 0.3, 0.02))
	MeshFactory.add(body, MeshFactory.capsule(0.36, 2.35), paint_mat, Vector3(0, 0.55, 0.05), Vector3(90, 0, 0), Vector3(1.75, 1.0, 0.72))
	# nose cone + front bumper
	MeshFactory.add(body, MeshFactory.sphere(0.5, 18, 10), paint_mat, Vector3(0, 0.5, -1.12), Vector3.ZERO, Vector3(1.05, 0.55, 1.1))
	MeshFactory.add(body, MeshFactory.sphere(0.2, 12, 6), white, Vector3(0, 0.55, -1.62), Vector3.ZERO, Vector3(1.6, 0.6, 0.6))
	# racing stripes over the tub (thin white capsules)
	for sx in [-0.16, 0.16]:
		MeshFactory.add(body, MeshFactory.capsule(0.06, 2.0), white, Vector3(sx, 0.81, -0.1), Vector3(90, 0, 0), Vector3(1.0, 1.0, 0.25))
	# number roundel on the nose
	MeshFactory.add(body, MeshFactory.cylinder(0.17, 0.17, 0.02, 20), white, Vector3(0, 0.79, -1.05), Vector3(-12, 0, 0))
	number_label = MeshFactory.label3d("1", 40, Color(0.1, 0.1, 0.18), Color.WHITE)
	number_label.outline_size = 0
	number_label.position = Vector3(0, 0.805, -1.05)
	number_label.rotation_degrees = Vector3(-102, 0, 0)
	body.add_child(number_label)
	# front wing with endplates
	MeshFactory.add(body, MeshFactory.box(Vector3(1.9, 0.06, 0.34)), carbon, Vector3(0, 0.26, -1.58))
	MeshFactory.add(body, MeshFactory.box(Vector3(1.7, 0.05, 0.16)), accent_mat, Vector3(0, 0.33, -1.5))
	for sx in [-0.96, 0.96]:
		MeshFactory.add(body, MeshFactory.box(Vector3(0.05, 0.24, 0.42)), paint_mat, Vector3(sx, 0.33, -1.57))
	# side pods with air intakes
	for sx in [-1.0, 1.0]:
		MeshFactory.add(body, MeshFactory.capsule(0.2, 1.2), white, Vector3(sx * 0.68, 0.46, 0.15), Vector3(90, 0, 0), Vector3(1.0, 1.0, 1.0))
		MeshFactory.add(body, MeshFactory.cylinder(0.13, 0.13, 0.05, 14), carbon, Vector3(sx * 0.68, 0.46, -0.44), Vector3(90, 0, 0))
		MeshFactory.add(body, MeshFactory.box(Vector3(0.04, 0.1, 0.9)), accent_mat, Vector3(sx * 0.885, 0.48, 0.15))
		# suspension arms
		MeshFactory.add(body, MeshFactory.cylinder(0.035, 0.035, 0.5, 6), metal, Vector3(sx * 0.6, 0.34, -0.88), Vector3(0, 0, 90))
		MeshFactory.add(body, MeshFactory.cylinder(0.035, 0.035, 0.45, 6), metal, Vector3(sx * 0.62, 0.38, 0.82), Vector3(0, 0, 90))
	# cockpit rim, seat, roll hoop
	var rim := TorusMesh.new()
	rim.inner_radius = 0.34
	rim.outer_radius = 0.42
	rim.rings = 20
	MeshFactory.add(body, rim, carbon, Vector3(0, 0.82, 0.15), Vector3.ZERO, Vector3(1.0, 0.5, 1.25))
	MeshFactory.add(body, MeshFactory.box(Vector3(0.6, 0.55, 0.14)), carbon, Vector3(0, 1.0, 0.52), Vector3(-14, 0, 0))
	var hoop := TorusMesh.new()
	hoop.inner_radius = 0.26
	hoop.outer_radius = 0.32
	MeshFactory.add(body, hoop, chrome, Vector3(0, 1.1, 0.62), Vector3(90, 0, 0), Vector3(1.0, 1.0, 1.4))
	# engine block + chrome exhausts with neon tips
	MeshFactory.add(body, MeshFactory.box(Vector3(0.85, 0.38, 0.55)), carbon, Vector3(0, 0.62, 0.98))
	for ex in [-0.24, 0.0, 0.24]:
		MeshFactory.add(body, MeshFactory.cylinder(0.05, 0.05, 0.22, 8), chrome, Vector3(ex, 0.88, 0.95))
	for ex in [-0.27, 0.27]:
		MeshFactory.add(body, MeshFactory.cylinder(0.08, 0.1, 0.42, 12), chrome, Vector3(ex, 0.6, 1.33), Vector3(90, 0, 0))
		var glow := MeshFactory.add(body, MeshFactory.cylinder(0.072, 0.072, 0.05, 12), neon, Vector3(ex, 0.6, 1.55), Vector3(90, 0, 0))
		exhaust_glow.append(glow)
	# rear spoiler: twin pylons + curved wing + endplates
	for sx in [-0.45, 0.45]:
		MeshFactory.add(body, MeshFactory.box(Vector3(0.05, 0.45, 0.1)), carbon, Vector3(sx, 1.03, 1.2), Vector3(-10, 0, 0))
	MeshFactory.add(body, MeshFactory.capsule(0.1, 1.75), paint_mat, Vector3(0, 1.27, 1.24), Vector3(0, 0, 90), Vector3(1.0, 1.0, 2.2))
	for sx in [-0.88, 0.88]:
		MeshFactory.add(body, MeshFactory.box(Vector3(0.05, 0.34, 0.5)), white, Vector3(sx, 1.26, 1.24))
	# headlights + tail light bar
	var hl_mat := MeshFactory.mat(Color(0.75, 0.92, 1.0), 0.2, 0.0, 3.0)
	for hx in [-0.32, 0.32]:
		MeshFactory.add(body, MeshFactory.sphere(0.09, 10, 6), hl_mat, Vector3(hx, 0.55, -1.5), Vector3.ZERO, Vector3(1.6, 0.7, 0.6))
		if with_lights:
			var sl := SpotLight3D.new()
			sl.light_color = Color(0.85, 0.95, 1.0)
			sl.light_energy = 1.5
			sl.spot_range = 14.0
			sl.spot_angle = 28.0
			sl.position = Vector3(hx, 0.5, -1.65)
			body.add_child(sl)
			headlights.append(sl)
	MeshFactory.add(body, MeshFactory.box(Vector3(0.8, 0.05, 0.04)), MeshFactory.mat(Color(1.0, 0.15, 0.25), 0.2, 0.0, 3.0), Vector3(0, 0.82, 1.27))
	# steering wheel
	var sw := TorusMesh.new()
	sw.inner_radius = 0.1
	sw.outer_radius = 0.14
	MeshFactory.add(body, sw, carbon, Vector3(0, 0.98, -0.18), Vector3(65, 0, 0))
	exhaust_points = [Vector3(-0.27, 0.6, 1.6), Vector3(0.27, 0.6, 1.6)]
	driver_offset = Vector3.ZERO


## BOLT — low, long wedge with a sharp nose and a big flat rear wing.
func _body_bolt(white: Material, carbon: Material, metal: Material, chrome: Material, neon: Material, with_lights: bool) -> void:
	MeshFactory.add(body, MeshFactory.box(Vector3(1.4, 0.1, 2.7)), carbon, Vector3(0, 0.26, 0.0))
	MeshFactory.add(body, MeshFactory.tapered_box(Vector2(1.2, 2.6), Vector2(0.7, 1.6), 0.3, 0.35), paint_mat, Vector3(0, 0.3, 0.05))
	MeshFactory.add(body, MeshFactory.tapered_box(Vector2(0.9, 1.1), Vector2(0.18, 0.5), 0.2, -0.3), paint_mat, Vector3(0, 0.3, -1.45))
	MeshFactory.add(body, MeshFactory.box(Vector3(0.12, 0.02, 2.6)), white, Vector3(0, 0.61, -0.2))
	MeshFactory.add(body, MeshFactory.box(Vector3(2.0, 0.05, 0.3)), carbon, Vector3(0, 0.22, -1.95))
	MeshFactory.add(body, MeshFactory.box(Vector3(1.8, 0.04, 0.12)), accent_mat, Vector3(0, 0.27, -1.88))
	for sx in [-1.0, 1.0]:
		MeshFactory.add(body, MeshFactory.tapered_box(Vector2(0.32, 1.3), Vector2(0.2, 1.0), 0.32, 0.15), white, Vector3(sx * 0.62, 0.28, 0.25))
		MeshFactory.add(body, MeshFactory.cylinder(0.03, 0.03, 0.5, 6), metal, Vector3(sx * 0.58, 0.3, -1.05), Vector3(0, 0, 90))
		MeshFactory.add(body, MeshFactory.box(Vector3(0.05, 0.38, 0.55)), paint_mat, Vector3(sx * 0.95, 0.95, 1.33))
	MeshFactory.add(body, MeshFactory.box(Vector3(1.95, 0.06, 0.55)), paint_mat, Vector3(0, 1.1, 1.33), Vector3(-6, 0, 0))
	MeshFactory.add(body, MeshFactory.box(Vector3(1.95, 0.04, 0.2)), white, Vector3(0, 1.15, 1.12), Vector3(-6, 0, 0))
	MeshFactory.add(body, MeshFactory.box(Vector3(0.08, 0.6, 0.12)), carbon, Vector3(0, 0.82, 1.3))
	MeshFactory.add(body, MeshFactory.box(Vector3(0.8, 0.32, 0.5)), carbon, Vector3(0, 0.5, 1.05))
	var hl := MeshFactory.mat(Color(0.75, 0.92, 1.0), 0.2, 0.0, 3.0)
	for hx in [-0.22, 0.22]:
		MeshFactory.add(body, MeshFactory.box(Vector3(0.22, 0.04, 0.05)), hl, Vector3(hx, 0.42, -1.55), Vector3(-20, 0, 0))
	for ex in [-0.2, 0.2]:
		MeshFactory.add(body, MeshFactory.cylinder(0.07, 0.09, 0.35, 10), chrome, Vector3(ex, 0.48, 1.35), Vector3(90, 0, 0))
		exhaust_glow.append(MeshFactory.add(body, MeshFactory.cylinder(0.065, 0.065, 0.04, 10), neon, Vector3(ex, 0.48, 1.54), Vector3(90, 0, 0)))
	MeshFactory.add(body, MeshFactory.box(Vector3(0.9, 0.04, 0.04)), MeshFactory.mat(Color(1.0, 0.15, 0.25), 0.2, 0.0, 3.0), Vector3(0, 1.08, 1.6))
	var sw := TorusMesh.new()
	sw.inner_radius = 0.1
	sw.outer_radius = 0.14
	MeshFactory.add(body, sw, carbon, Vector3(0, 0.82, -0.3), Vector3(65, 0, 0))
	MeshFactory.add(body, MeshFactory.box(Vector3(0.55, 0.5, 0.12)), carbon, Vector3(0, 0.82, 0.38), Vector3(-20, 0, 0))
	number_label = _nose_number(Vector3(0, 0.52, -1.2), -100.0)
	exhaust_points = [Vector3(-0.2, 0.48, 1.62), Vector3(0.2, 0.48, 1.62)]
	driver_offset = Vector3(0, -0.15, 0.05)


## BUBBLE — round toy buggy with a glossy dome hood and chunky bumpers.
func _body_bubble(white: Material, carbon: Material, metal: Material, chrome: Material, neon: Material, with_lights: bool) -> void:
	MeshFactory.add(body, MeshFactory.box(Vector3(1.45, 0.14, 2.0)), carbon, Vector3(0, 0.34, 0))
	MeshFactory.add(body, MeshFactory.sphere(0.95, 22, 12), paint_mat, Vector3(0, 0.62, 0.0), Vector3.ZERO, Vector3(0.85, 0.42, 1.12))
	MeshFactory.add(body, MeshFactory.sphere(0.5, 18, 10), paint_mat, Vector3(0, 0.62, -0.85), Vector3.ZERO, Vector3(1.25, 0.6, 0.8))
	for z in [-1.18, 1.12]:
		MeshFactory.add(body, MeshFactory.capsule(0.13, 1.7), white, Vector3(0, 0.42, z), Vector3(0, 0, 90))
	for sx in [-1.0, 1.0]:
		var arch := TorusMesh.new()
		arch.inner_radius = 0.38
		arch.outer_radius = 0.48
		for z in [-0.78, 0.78]:
			MeshFactory.add(body, arch, accent_mat, Vector3(sx * 0.78, 0.4, z), Vector3(0, 0, 90), Vector3(1.0, 0.6, 1.0))
		MeshFactory.add(body, MeshFactory.sphere(0.13, 10, 6), white, Vector3(sx * 0.4, 0.98, -0.75))
	# polka dots
	for d in [Vector3(0.35, 0.95, 0.35), Vector3(-0.42, 0.93, 0.1), Vector3(0.1, 1.0, -0.35)]:
		MeshFactory.add(body, MeshFactory.cylinder(0.12, 0.12, 0.02, 14), white, d)
	var roll := TorusMesh.new()
	roll.inner_radius = 0.48
	roll.outer_radius = 0.56
	MeshFactory.add(body, roll, chrome, Vector3(0, 1.0, 0.55), Vector3(90, 0, 0), Vector3(1.0, 1.0, 1.1))
	var hl := MeshFactory.mat(Color(1.0, 0.95, 0.75), 0.2, 0.0, 3.0)
	for hx in [-0.42, 0.42]:
		MeshFactory.add(body, MeshFactory.sphere(0.12, 12, 8), hl, Vector3(hx, 0.7, -1.22))
	MeshFactory.add(body, MeshFactory.cylinder(0.1, 0.12, 0.4, 10), chrome, Vector3(0, 0.6, 1.25), Vector3(90, 0, 0))
	exhaust_glow.append(MeshFactory.add(body, MeshFactory.cylinder(0.09, 0.09, 0.04, 10), neon, Vector3(0, 0.6, 1.46), Vector3(90, 0, 0)))
	MeshFactory.add(body, MeshFactory.box(Vector3(0.62, 0.5, 0.14)), carbon, Vector3(0, 1.0, 0.45), Vector3(-12, 0, 0))
	var sw := TorusMesh.new()
	sw.inner_radius = 0.1
	sw.outer_radius = 0.14
	MeshFactory.add(body, sw, carbon, Vector3(0, 1.0, -0.22), Vector3(60, 0, 0))
	number_label = _nose_number(Vector3(0, 0.89, -0.92), -60.0)
	exhaust_points = [Vector3(0, 0.6, 1.5)]
	driver_offset = Vector3(0, 0.02, 0.0)


## DRIFTER — wide muscle kart: fat rear tyres, hood scoop, twin pipes, ducktail.
func _body_drifter(white: Material, carbon: Material, metal: Material, chrome: Material, neon: Material, with_lights: bool) -> void:
	MeshFactory.add(body, MeshFactory.box(Vector3(1.75, 0.14, 2.45)), carbon, Vector3(0, 0.32, 0.02))
	MeshFactory.add(body, MeshFactory.tapered_box(Vector2(1.7, 2.4), Vector2(1.35, 1.7), 0.42, 0.1), paint_mat, Vector3(0, 0.38, 0.0))
	MeshFactory.add(body, MeshFactory.tapered_box(Vector2(1.5, 0.7), Vector2(1.2, 0.4), 0.3, -0.1), paint_mat, Vector3(0, 0.38, -1.4))
	MeshFactory.add(body, MeshFactory.box(Vector3(0.5, 0.16, 0.6)), carbon, Vector3(0, 0.88, -0.75))
	MeshFactory.add(body, MeshFactory.box(Vector3(0.42, 0.04, 0.05)), MeshFactory.mat(Color(0.05, 0.05, 0.07), 0.9), Vector3(0, 0.9, -1.06))
	for sx in [-0.3, 0.3]:
		MeshFactory.add(body, MeshFactory.box(Vector3(0.16, 0.02, 2.35)), white, Vector3(sx, 0.81, 0.0))
	MeshFactory.add(body, MeshFactory.box(Vector3(1.9, 0.12, 0.3)), white, Vector3(0, 0.36, -1.78))
	for sx in [-1.0, 1.0]:
		MeshFactory.add(body, MeshFactory.box(Vector3(0.28, 0.38, 0.95)), accent_mat, Vector3(sx * 0.95, 0.55, 0.86))
		MeshFactory.add(body, MeshFactory.box(Vector3(0.22, 0.28, 0.75)), accent_mat, Vector3(sx * 0.9, 0.48, -0.92))
		MeshFactory.add(body, MeshFactory.box(Vector3(0.04, 0.12, 1.2)), white, Vector3(sx * 0.86, 0.6, 0.0))
	MeshFactory.add(body, MeshFactory.tapered_box(Vector2(1.6, 0.5), Vector2(1.6, 0.25), 0.22, 0.12), paint_mat, Vector3(0, 0.8, 1.15))
	var hl := MeshFactory.mat(Color(1.0, 0.95, 0.8), 0.2, 0.0, 3.0)
	for hx in [-0.55, 0.55]:
		MeshFactory.add(body, MeshFactory.cylinder(0.11, 0.11, 0.05, 12), hl, Vector3(hx, 0.58, -1.76), Vector3(90, 0, 0))
	for ex in [-0.4, -0.25, 0.25, 0.4]:
		MeshFactory.add(body, MeshFactory.cylinder(0.06, 0.07, 0.4, 8), chrome, Vector3(ex, 0.45, 1.3), Vector3(90, 0, 0))
		exhaust_glow.append(MeshFactory.add(body, MeshFactory.cylinder(0.055, 0.055, 0.04, 8), neon, Vector3(ex, 0.45, 1.51), Vector3(90, 0, 0)))
	MeshFactory.add(body, MeshFactory.box(Vector3(1.3, 0.05, 0.04)), MeshFactory.mat(Color(1.0, 0.15, 0.25), 0.2, 0.0, 3.0), Vector3(0, 0.8, 1.42))
	MeshFactory.add(body, MeshFactory.box(Vector3(0.62, 0.55, 0.14)), carbon, Vector3(0, 1.0, 0.5), Vector3(-14, 0, 0))
	var sw := TorusMesh.new()
	sw.inner_radius = 0.1
	sw.outer_radius = 0.14
	MeshFactory.add(body, sw, carbon, Vector3(0, 1.0, -0.2), Vector3(65, 0, 0))
	number_label = _nose_number(Vector3(0, 0.69, -1.45), -75.0)
	exhaust_points = [Vector3(-0.32, 0.45, 1.55), Vector3(0.32, 0.45, 1.55)]
	driver_offset = Vector3(0, 0.02, 0.05)


func _nose_number(pos: Vector3, tilt_deg: float) -> Label3D:
	MeshFactory.add(body, MeshFactory.cylinder(0.16, 0.16, 0.02, 20), MeshFactory.mat(Color(0.97, 0.97, 0.99), 0.35, 0.05), pos, Vector3(tilt_deg + 90.0, 0, 0))
	var l := MeshFactory.label3d("1", 40, Color(0.1, 0.1, 0.18), Color.WHITE)
	l.outline_size = 0
	l.position = pos + Vector3(0, 0.015, 0)
	l.rotation_degrees = Vector3(tilt_deg, 0, 0)
	body.add_child(l)
	return l
