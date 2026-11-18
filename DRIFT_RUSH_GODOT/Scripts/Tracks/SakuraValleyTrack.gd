extends TrackBuilder
## Sakura Valley — bright cherry-blossom valley: S-bend, raised bridge section,
## hairpin, windmill, waterfall, stone viaduct, mountains, hot-air balloons.
## All scenery is original procedural geometry.

const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 water : source_color = vec4(0.45, 0.8, 1.0, 1.0);
uniform float speed = 1.6;
uniform float falling = 1.0;
void fragment() {
	float wav = sin(UV.x * 24.0 + TIME * 2.0) * 0.08;
	float s = fract(UV.y * 5.0 * falling + TIME * speed * falling + wav + (1.0 - falling) * (sin(UV.x * 12.0 + TIME) * 0.5));
	vec3 c = mix(water.rgb, vec3(1.0), smoothstep(0.55, 1.0, s) * (0.4 + 0.5 * falling));
	ALBEDO = c;
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	EMISSION = c * 0.18;
	ALPHA = 0.92;
}
"""

var spinners: Array[Node3D] = []
var bobbers: Array[Dictionary] = []
var _t := 0.0
var cloud_layer: Node3D


func _define_track() -> void:
	track_id = "sakura_valley"
	display_name = "Sakura Valley"
	road_width = 14.0
	checkpoint_count = 8
	xz_scale = 1.25
	control_points = PackedVector3Array([
		Vector3(0, 0, 40), Vector3(0, 0, -40), Vector3(10, 0, -90), Vector3(45, 0, -115),
		Vector3(90, 0, -100), Vector3(110, 0, -60), Vector3(95, 0, -20), Vector3(110, 0, 20),
		Vector3(150, 1.5, 40), Vector3(175, 3.0, 80), Vector3(160, 3.0, 125), Vector3(115, 1.5, 140),
		Vector3(70, 0, 120), Vector3(40, 0, 135), Vector3(0, 0, 120), Vector3(-15, 0, 85),
	])


func _process(delta: float) -> void:
	_t += delta
	for s in spinners:
		s.rotate_object_local(Vector3.FORWARD, delta * 0.7)
	if cloud_layer:
		cloud_layer.rotate_y(delta * 0.006)
	for b in bobbers:
		var n: Node3D = b["node"]
		n.position.y = float(b["y"]) + sin(_t * float(b["speed"]) + float(b["phase"])) * float(b["amp"])


func _decorate() -> void:
	var density := float(quality.get("tree_density", 1.0))
	add_grandstand(42.0, -1.0, 40.0, Color(1.0, 0.45, 0.65))
	add_grandstand(length * 0.79, 1.0, 30.0, Color(0.3, 0.55, 1.0))
	add_bunting(8.0, 95.0, 1.0)
	add_bunting(length - 60.0, length - 12.0, -1.0)
	add_tire_barriers()
	_cherry_trees(density)
	_flowers(density)
	_bushes(density)
	_windmill(Vector3(-55, 0, -120))
	_waterfall(Vector3(70, 0, -245))
	_creek()
	_viaduct(Vector3(-110, 0, -300), Vector3(180, 0, -300))
	_mountains()
	_balloons()
	_clouds()
	_chevrons()
	_banners()


func _tree_multimeshes(transforms: Array[Transform3D]) -> void:
	var trunk_mm := MultiMesh.new()
	trunk_mm.transform_format = MultiMesh.TRANSFORM_3D
	trunk_mm.mesh = MeshFactory.cylinder(0.22, 0.38, 3.2, 7)
	trunk_mm.instance_count = transforms.size()
	var canopy_mm := MultiMesh.new()
	canopy_mm.transform_format = MultiMesh.TRANSFORM_3D
	canopy_mm.use_colors = true
	canopy_mm.mesh = MeshFactory.sphere(1.0, 10, 6)
	var blobs := [[Vector3(0, 3.8, 0), 2.3], [Vector3(1.3, 3.3, 0.5), 1.6], [Vector3(-1.2, 3.4, -0.4), 1.7], [Vector3(0.2, 4.7, -0.3), 1.5]]
	canopy_mm.instance_count = transforms.size() * blobs.size()
	var shades := [Color(1.0, 0.72, 0.85), Color(1.0, 0.62, 0.8), Color(1.0, 0.8, 0.9), Color(0.98, 0.55, 0.75), Color(1.0, 0.86, 0.93)]
	var petal_mm := MultiMesh.new()
	petal_mm.transform_format = MultiMesh.TRANSFORM_3D
	petal_mm.mesh = MeshFactory.cylinder(1.0, 1.0, 0.04, 10)
	petal_mm.instance_count = transforms.size()
	for i in transforms.size():
		var t: Transform3D = transforms[i]
		var s := _rng.randf_range(0.85, 1.35)
		var ts := t.scaled_local(Vector3.ONE * s)
		trunk_mm.set_instance_transform(i, ts * Transform3D(Basis(), Vector3(0, 1.6, 0)))
		for j in blobs.size():
			var bl: Array = blobs[j]
			var off: Vector3 = bl[0]
			var r: float = float(bl[1]) * _rng.randf_range(0.85, 1.15)
			canopy_mm.set_instance_transform(i * blobs.size() + j, ts * Transform3D(Basis().scaled(Vector3.ONE * r), off))
			canopy_mm.set_instance_color(i * blobs.size() + j, shades[_rng.randi() % shades.size()])
		petal_mm.set_instance_transform(i, ts * Transform3D(Basis().scaled(Vector3(2.6, 1, 2.6)), Vector3(0, 0.03, 0)))
	var trunk := MultiMeshInstance3D.new()
	trunk.multimesh = trunk_mm
	trunk.material_override = MeshFactory.mat(Color(0.45, 0.3, 0.25), 0.9)
	decor_root.add_child(trunk)
	var canopy := MultiMeshInstance3D.new()
	canopy.multimesh = canopy_mm
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.roughness = 0.85
	cm.rim_enabled = true
	cm.rim = 0.4
	cm.rim_tint = 0.2
	canopy.material_override = cm
	decor_root.add_child(canopy)
	var petals := MultiMeshInstance3D.new()
	petals.multimesh = petal_mm
	petals.material_override = MeshFactory.mat(Color(1.0, 0.8, 0.88), 0.9, 0.0, 0.0, 0.0)
	petals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	decor_root.add_child(petals)


func _cherry_trees(density: float) -> void:
	var spots := roadside_points(11.0 / density, 3.5, 12.0, 3.0)
	# Scattered groves in open fields.
	var tries := int(160 * density)
	for i in tries:
		var p := Vector3(_rng.randf_range(-170, 330), 0, _rng.randf_range(-230, 250))
		if is_clear_of_road(p, 6.0) and not is_excluded(p) and p.distance_to(Vector3(-55, 0, -120)) > 14.0 and p.distance_to(Vector3(70, 0, -245)) > 30.0:
			spots.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p))
	_tree_multimeshes(spots)


func _flowers(density: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = MeshFactory.sphere(0.18, 6, 3)
	var cols := [Color(1.0, 0.55, 0.75), Color(1.0, 0.9, 0.35), Color(1.0, 1.0, 1.0), Color(0.75, 0.55, 1.0), Color(1.0, 0.4, 0.4)]
	var xs: Array[Transform3D] = []
	var cs: Array[Color] = []
	var patches := int(70 * density)
	for i in patches:
		var c := Vector3(_rng.randf_range(-160, 320), 0, _rng.randf_range(-220, 240))
		if not is_clear_of_road(c, 4.0) or is_excluded(c):
			continue
		var col: Color = cols[_rng.randi() % cols.size()]
		for k in 14:
			var p := c + Vector3(_rng.randf_range(-3.5, 3.5), 0.12, _rng.randf_range(-3.5, 3.5))
			xs.append(Transform3D(Basis().scaled(Vector3.ONE * _rng.randf_range(0.7, 1.3)), p))
			cs.append(col)
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		mm.set_instance_color(i, cs[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = MeshFactory.vertex_color_mat(0.8)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	decor_root.add_child(mi)


func _bushes(density: float) -> void:
	var spots := roadside_points(7.0 / density, 1.0, 2.5, 2.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = MeshFactory.sphere(1.0, 8, 5)
	mm.instance_count = spots.size()
	for i in spots.size():
		var s := _rng.randf_range(0.6, 1.1)
		mm.set_instance_transform(i, spots[i] * Transform3D(Basis().scaled(Vector3(s * 1.3, s * 0.8, s * 1.3)), Vector3(0, 0.3, 0)))
		var flower := _rng.randf() < 0.3
		mm.set_instance_color(i, Color(1.0, 0.85, 0.4) if flower else Color(0.35, 0.7, 0.3).lightened(_rng.randf() * 0.2))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = MeshFactory.vertex_color_mat(0.9)
	decor_root.add_child(mmi)


func _windmill(pos: Vector3) -> void:
	var w := Node3D.new()
	w.name = "Windmill"
	decor_root.add_child(w)
	w.position = pos
	w.rotation_degrees = Vector3(0, 35, 0)
	var cream := MeshFactory.mat(Color(0.98, 0.93, 0.85), 0.8)
	var roof := MeshFactory.mat(Color(0.75, 0.3, 0.25), 0.7)
	var wood := MeshFactory.mat(Color(0.55, 0.38, 0.28), 0.8)
	MeshFactory.add(w, MeshFactory.cylinder(2.4, 3.6, 13.0, 10), cream, Vector3(0, 6.5, 0))
	MeshFactory.add(w, MeshFactory.cylinder(0.0, 3.2, 4.0, 10), roof, Vector3(0, 15.0, 0))
	MeshFactory.add(w, MeshFactory.box(Vector3(1.6, 2.6, 0.3)), wood, Vector3(0, 1.3, 3.45))
	for wy in [5.0, 9.0]:
		MeshFactory.add(w, MeshFactory.box(Vector3(1.0, 1.2, 0.3)), MeshFactory.mat(Color(0.4, 0.65, 0.9), 0.2), Vector3(0, wy, 3.0 - wy * 0.06))
	var hub := Node3D.new()
	hub.position = Vector3(0, 12.0, 3.4)
	w.add_child(hub)
	MeshFactory.add(hub, MeshFactory.cylinder(0.5, 0.5, 0.8, 8), wood, Vector3.ZERO, Vector3(90, 0, 0))
	for k in 4:
		var arm := Node3D.new()
		arm.rotation_degrees = Vector3(0, 0, k * 90.0)
		hub.add_child(arm)
		MeshFactory.add(arm, MeshFactory.box(Vector3(0.25, 8.0, 0.15)), wood, Vector3(0, 4.2, 0.3))
		MeshFactory.add(arm, MeshFactory.box(Vector3(1.6, 6.0, 0.08)), cream, Vector3(0.95, 4.8, 0.32))
	spinners.append(hub)


func _waterfall(pos: Vector3) -> void:
	var wf := Node3D.new()
	wf.name = "Waterfall"
	decor_root.add_child(wf)
	wf.position = pos
	var rock := MeshFactory.mat(Color(0.55, 0.58, 0.6), 0.95)
	var moss := MeshFactory.mat(Color(0.45, 0.68, 0.38), 0.95)
	MeshFactory.add(wf, MeshFactory.box(Vector3(70, 28, 18)), rock, Vector3(0, 14, -6))
	MeshFactory.add(wf, MeshFactory.box(Vector3(72, 3, 20)), moss, Vector3(0, 29, -6))
	MeshFactory.add(wf, MeshFactory.box(Vector3(30, 20, 14)), rock, Vector3(-38, 10, -2), Vector3(0, 20, 0))
	MeshFactory.add(wf, MeshFactory.box(Vector3(26, 16, 14)), rock, Vector3(36, 8, -1), Vector3(0, -15, 0))
	for k in 6:
		MeshFactory.add(wf, MeshFactory.sphere(_rng.randf_range(2.5, 5.0), 8, 5), moss, Vector3(_rng.randf_range(-30, 30), 29.5, _rng.randf_range(-12, 2)))
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var fall_mat := ShaderMaterial.new()
	fall_mat.shader = sh
	fall_mat.set_shader_parameter("falling", 1.0)
	var fall := QuadMesh.new()
	fall.size = Vector2(12, 28)
	MeshFactory.add(wf, fall, fall_mat, Vector3(0, 14, 3.2))
	var pool_mat := ShaderMaterial.new()
	pool_mat.shader = sh
	pool_mat.set_shader_parameter("falling", 0.0)
	pool_mat.set_shader_parameter("speed", 0.4)
	var pool := PlaneMesh.new()
	pool.size = Vector2(40, 26)
	MeshFactory.add(wf, pool, pool_mat, Vector3(0, 0.08, 15))
	if float(quality.get("particles", 1.0)) > 0.3:
		var mist := CPUParticles3D.new()
		mist.amount = 30
		mist.lifetime = 2.0
		mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		mist.emission_box_extents = Vector3(6, 0.5, 2)
		mist.direction = Vector3(0, 1, 0.4)
		mist.initial_velocity_min = 1.0
		mist.initial_velocity_max = 3.0
		mist.gravity = Vector3(0, 0.3, 0)
		mist.scale_amount_min = 3.0
		mist.scale_amount_max = 6.0
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		mist.mesh = q
		mist.material_override = MeshFactory.particle_material(Color.WHITE)
		mist.color = Color(1, 1, 1, 0.35)
		mist.color_ramp = MeshFactory.fade_gradient(Color(1, 1, 1, 0.5), Color(1, 1, 1, 0))
		mist.position = Vector3(0, 1, 6)
		wf.add_child(mist)


func _creek() -> void:
	# Stream passing under the raised bridge section (decorative).
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("falling", 0.0)
	m.set_shader_parameter("speed", 0.6)
	var f := frame_at(length * 0.56)
	var p: Vector3 = f["pos"]
	var pm := PlaneMesh.new()
	pm.size = Vector2(10, 120)
	var mi := MeshFactory.add(decor_root, pm, m, Vector3(p.x, 0.05, p.z))
	mi.look_at(mi.global_position + f["right"], Vector3.UP)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _viaduct(a: Vector3, b: Vector3) -> void:
	var v := Node3D.new()
	v.name = "Viaduct"
	decor_root.add_child(v)
	var stone := MeshFactory.mat(Color(0.9, 0.84, 0.74), 0.9)
	var dark_stone := MeshFactory.mat(Color(0.78, 0.7, 0.6), 0.9)
	var dir := (b - a).normalized()
	var total := a.distance_to(b)
	var span := 16.0
	var h := 18.0
	var count := int(total / span)
	var basis := Basis.looking_at(dir, Vector3.UP)
	v.transform = Transform3D(basis, a)
	for k in count + 1:
		var z := -k * span
		MeshFactory.add(v, MeshFactory.box(Vector3(5, h, 3.2)), dark_stone, Vector3(0, h / 2.0, z), Vector3(0, 90, 0))
		if k < count:
			# arch: semicircle approximated with 10 blocks
			var cz := z - span / 2.0
			var r := span / 2.0 - 1.4
			for s in 11:
				var ang := PI * float(s) / 10.0
				var pz := cz + cos(ang) * r
				var py := h - 4.5 + sin(ang) * 3.2
				MeshFactory.add(v, MeshFactory.box(Vector3(3.0, 1.2, 2.2)), stone, Vector3(0, py, pz), Vector3(rad_to_deg(-cos(ang) * 0.6), 0, 0))
	MeshFactory.add(v, MeshFactory.box(Vector3(5.4, 1.6, total + 4)), stone, Vector3(0, h + 0.8, -total / 2.0))
	MeshFactory.add(v, MeshFactory.box(Vector3(0.5, 1.2, total + 4)), dark_stone, Vector3(-2.5, h + 2.0, -total / 2.0))
	MeshFactory.add(v, MeshFactory.box(Vector3(0.5, 1.2, total + 4)), dark_stone, Vector3(2.5, h + 2.0, -total / 2.0))


func _mountains() -> void:
	var green := MeshFactory.mat(Color(0.42, 0.62, 0.55), 1.0, 0.0, 0.0, 0.1)
	var far := MeshFactory.mat(Color(0.55, 0.66, 0.82), 1.0, 0.0, 0.0, 0.1)
	var snow := MeshFactory.mat(Color(0.97, 0.97, 1.0), 0.8)
	var center := Vector3(70, 0, 0)
	for i in 18:
		var ang := TAU * float(i) / 18.0 + _rng.randf_range(-0.1, 0.1)
		var dist := _rng.randf_range(430, 560)
		var hgt := _rng.randf_range(90, 180)
		var rad := hgt * _rng.randf_range(0.9, 1.3)
		var p := center + Vector3(cos(ang) * dist, 0, sin(ang) * dist)
		var m := MeshFactory.add(decor_root, MeshFactory.cylinder(0.0, rad, hgt, 7), far if i % 2 == 0 else green, p + Vector3(0, hgt / 2.0 - 2.0, 0))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if hgt > 130.0:
			var cap_h := hgt * 0.25
			var c := MeshFactory.add(decor_root, MeshFactory.cylinder(0.0, rad * 0.25 + 1.0, cap_h, 7), snow, p + Vector3(0, hgt - cap_h / 2.0 - 1.5, 0))
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _balloons() -> void:
	var cols := [Color(1.0, 0.45, 0.5), Color(0.35, 0.7, 1.0), Color(1.0, 0.8, 0.3), Color(0.6, 0.45, 1.0), Color(0.4, 0.9, 0.6)]
	var spots := [Vector3(-40, 45, -180), Vector3(140, 60, -200), Vector3(260, 50, 40), Vector3(60, 70, 220), Vector3(-120, 55, 60)]
	for i in spots.size():
		var b := Node3D.new()
		decor_root.add_child(b)
		b.position = spots[i]
		var col: Color = cols[i % cols.size()]
		MeshFactory.add(b, MeshFactory.sphere(4.5, 14, 8), MeshFactory.mat(col, 0.5), Vector3(0, 0, 0), Vector3.ZERO, Vector3(1, 1.15, 1))
		MeshFactory.add(b, MeshFactory.sphere(4.55, 14, 8), MeshFactory.mat(Color(1, 1, 1), 0.5), Vector3(0, 0, 0), Vector3.ZERO, Vector3(0.3, 1.16, 1.01))
		MeshFactory.add(b, MeshFactory.cylinder(1.2, 0.9, 1.4, 8), MeshFactory.mat(Color(0.55, 0.38, 0.25), 0.9), Vector3(0, -6.8, 0))
		bobbers.append({"node": b, "y": b.position.y, "amp": 1.5, "speed": 0.4 + i * 0.07, "phase": i * 1.3})


func _clouds() -> void:
	var m := MeshFactory.mat(Color(1, 1, 1), 1.0, 0.0, 0.25, 0.0)
	cloud_layer = Node3D.new()
	cloud_layer.name = "Clouds"
	cloud_layer.position = Vector3(70, 0, 0)
	decor_root.add_child(cloud_layer)
	for i in 10:
		var c := Node3D.new()
		cloud_layer.add_child(c)
		var ang := TAU * float(i) / 10.0
		c.position = Vector3(cos(ang) * 320, _rng.randf_range(90, 130), sin(ang) * 320)
		for k in 5:
			var s := _rng.randf_range(8, 14)
			var mi := MeshFactory.add(c, MeshFactory.sphere(1.0, 10, 6), m, Vector3(k * 9.0 - 18.0, _rng.randf_range(-2, 3), _rng.randf_range(-4, 4)), Vector3.ZERO, Vector3(s, s * 0.7, s))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _chevrons() -> void:
	var board := MeshFactory.mat(Color(1.0, 0.82, 0.1), 0.6)
	var d := 0.0
	var last := -100.0
	while d < length:
		var a: Vector3 = frame_at(d - 12.0)["flat"]
		var b: Vector3 = frame_at(d + 12.0)["flat"]
		var ang := a.angle_to(b)
		if ang > 0.55 and d - last > 30.0:
			last = d
			var f := frame_at(d - 10.0)
			var turn_right := (b - a).dot(f["right"]) > 0.0
			var side := -1.0 if turn_right else 1.0
			var t := transform_at(d - 10.0, side * (half_width() + KERB_W + 1.4), 0.0)
			var n := Node3D.new()
			decor_root.add_child(n)
			n.global_transform = t
			n.rotate_object_local(Vector3.UP, deg_to_rad(-side * 25.0))
			MeshFactory.add(n, MeshFactory.box(Vector3(5.0, 1.5, 0.2)), board, Vector3(0, 2.0, 0))
			MeshFactory.add(n, MeshFactory.box(Vector3(0.2, 1.4, 0.2)), MeshFactory.mat(Color(0.3, 0.3, 0.35)), Vector3(-2.0, 0.7, 0))
			MeshFactory.add(n, MeshFactory.box(Vector3(0.2, 1.4, 0.2)), MeshFactory.mat(Color(0.3, 0.3, 0.35)), Vector3(2.0, 0.7, 0))
			var l := MeshFactory.label3d(">>>" if turn_right else "<<<", 150, Color(0.1, 0.1, 0.15), Color(1, 0.9, 0.3))
			l.position = Vector3(0, 2.0, 0.12)
			n.add_child(l)
		d += 6.0


func _banners() -> void:
	var cols := [Color(1.0, 0.45, 0.7), Color(0.25, 0.5, 1.0)]
	var d := 60.0
	var i := 0
	while d < length - 30.0:
		var side := 1.0 if i % 2 == 0 else -1.0
		var t := transform_at(d, side * (half_width() + KERB_W + 0.9), 0.0)
		var n := Node3D.new()
		decor_root.add_child(n)
		n.global_transform = t
		n.rotate_object_local(Vector3.UP, deg_to_rad(side * 90.0))
		var col: Color = cols[i % 2]
		MeshFactory.add(n, MeshFactory.box(Vector3(9.0, 1.6, 0.15)), MeshFactory.mat(col, 0.5), Vector3(0, 1.9, 0))
		for face in [1.0, -1.0]:
			var l := MeshFactory.label3d("DRIFT RUSH  |  SAKURA VALLEY", 90, Color.WHITE, col.darkened(0.5))
			l.position = Vector3(0, 1.9, 0.09 * face)
			if face < 0.0:
				l.rotation_degrees = Vector3(0, 180, 0)
			n.add_child(l)
		d += 130.0
		i += 1
