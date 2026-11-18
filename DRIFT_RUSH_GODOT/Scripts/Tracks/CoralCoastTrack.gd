extends TrackBuilder
## Coral Coast — sunset seaside circuit: beach straight, climb to a lighthouse
## cliff (+5 m), descending chicane, and a bridge across the lagoon.
## All scenery is original procedural geometry.

const OCEAN_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 deep : source_color = vec4(0.05, 0.35, 0.6, 1.0);
uniform vec4 shallow : source_color = vec4(0.25, 0.75, 0.85, 1.0);
uniform vec4 sunset : source_color = vec4(1.0, 0.6, 0.4, 1.0);
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(wpos.x * 0.08 + TIME * 1.2) * 0.12 + sin(wpos.z * 0.11 + TIME * 0.9) * 0.1;
}
void fragment() {
	float w = sin(wpos.x * 0.35 + TIME * 1.6) * sin(wpos.z * 0.3 - TIME * 1.1);
	float foam = smoothstep(0.82, 1.0, w);
	vec3 c = mix(deep.rgb, shallow.rgb, 0.45 + 0.25 * w);
	c = mix(c, sunset.rgb, 0.18 * (0.5 + 0.5 * sin(wpos.x * 0.02)));
	ALBEDO = mix(c, vec3(1.0), foam * 0.7);
	ROUGHNESS = 0.06;
	METALLIC = 0.2;
	SPECULAR = 0.8;
}
"""

var spinners: Array[Node3D] = []
var bobbers: Array[Dictionary] = []
var _t := 0.0


func _define_track() -> void:
	track_id = "coral_coast"
	display_name = "Coral Coast"
	road_width = 14.0
	checkpoint_count = 8
	xz_scale = 1.4
	control_points = PackedVector3Array([
		Vector3(0, 0, 50), Vector3(0, 0, -30), Vector3(-15, 0.5, -85), Vector3(-55, 2.5, -110),
		Vector3(-100, 4.5, -100), Vector3(-125, 5.0, -60), Vector3(-120, 4.5, -15), Vector3(-95, 3.0, 15),
		Vector3(-70, 1.5, 10), Vector3(-50, 0.5, 35), Vector3(-60, 0, 80), Vector3(-35, 0, 120),
		Vector3(5, 2.5, 140), Vector3(40, 3.0, 125), Vector3(55, 1.5, 95), Vector3(35, 0, 70),
	])
	theme.merge({
		"sky_top": Color(0.36, 0.58, 0.92), "sky_horizon": Color(1.0, 0.8, 0.62),
		"ground": Color(0.93, 0.83, 0.6), "ground_horizon": Color(0.98, 0.85, 0.66),
		"asphalt": Color(0.38, 0.38, 0.4), "lines": Color(0.98, 0.97, 0.94), "center": Color(1.0, 0.8, 0.3),
		"kerb_a": Color(0.1, 0.65, 0.85), "kerb_b": Color(0.98, 0.98, 0.98),
		"wall_a": Color(1.0, 0.55, 0.3), "wall_b": Color(0.98, 0.96, 0.9),
		"sun_color": Color(1.0, 0.86, 0.68), "sun_energy": 1.3, "sun_angle": Vector3(-32, 150, 0),
		"ambient_energy": 0.85, "fog_color": Color(1.0, 0.88, 0.78), "fog_density": 0.0011,
		"glow": 0.55, "night": false, "petals": false,
	}, true)


func _process(delta: float) -> void:
	_t += delta
	for s in spinners:
		s.rotate_y(delta * 1.2)
	for b in bobbers:
		var n: Node3D = b["node"]
		n.position.y = float(b["y"]) + sin(_t * float(b["speed"]) + float(b["phase"])) * float(b["amp"])
		n.rotation.z = sin(_t * float(b["speed"]) * 0.8 + float(b["phase"])) * 0.06


func _decorate() -> void:
	var density := float(quality.get("tree_density", 1.0))
	add_grandstand(30.0, -1.0, 40.0, Color(1.0, 0.5, 0.3))
	add_bunting(8.0, 95.0, 1.0)
	add_tire_barriers(Color(0.1, 0.6, 0.85), Color(0.98, 0.98, 0.98))
	_ocean()
	_lagoon()
	_cliff_rocks()
	_lighthouse(Vector3(-208, 0, -92))
	_beach_props()
	_palms(density)
	_boats()
	_sea_arch(Vector3(190, 0, 30))
	_banners()


func _water_mat() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = OCEAN_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _ocean() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 1400)
	pm.subdivide_width = 48
	pm.subdivide_depth = 72
	var mi := MeshFactory.add(decor_root, pm, _water_mat(), Vector3(565, 0.03, 0))
	mi.name = "Ocean"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# wet sand strip along the shore
	var shore := PlaneMesh.new()
	shore.size = Vector2(14, 1400)
	MeshFactory.add(decor_root, shore, MeshFactory.mat(Color(0.78, 0.68, 0.48), 0.4, 0.0, 0.0, 0.0), Vector3(110, 0.015, 0))


func _lagoon() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 46)
	pm.subdivide_width = 12
	pm.subdivide_depth = 8
	var mi := MeshFactory.add(decor_root, pm, _water_mat(), Vector3(30, 0.03, 192))
	mi.name = "Lagoon"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Rocky cliff faces outside the raised western section.
func _cliff_rocks() -> void:
	var rock := MeshFactory.mat(Color(0.62, 0.5, 0.42), 0.95)
	var rock2 := MeshFactory.mat(Color(0.5, 0.42, 0.36), 0.95)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = MeshFactory.sphere(1.0, 9, 6)
	var xs: Array[Transform3D] = []
	var d := 0.0
	while d < length:
		var f := frame_at(d)
		var y: float = f["pos"].y
		if y > 1.8:
			for side in [-1.0, 1.0]:
				var p: Vector3 = f["pos"] + f["right"] * side * (half_width() + KERB_W + _rng.randf_range(2.0, 5.0))
				var sc := Vector3(_rng.randf_range(4.0, 7.0), y + _rng.randf_range(0.5, 2.0), _rng.randf_range(4.0, 7.0))
				xs.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(sc), Vector3(p.x, 0.0, p.z)))
		d += 5.0
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		mm.set_instance_color(i, Color(0.66, 0.53, 0.43).darkened(_rng.randf() * 0.25))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = MeshFactory.vertex_color_mat(0.95)
	decor_root.add_child(mi)
	# a few big boulders on the beach
	for i in 8:
		var p := Vector3(_rng.randf_range(80, 105), 0, _rng.randf_range(-150, 160))
		if is_clear_of_road(p, 6.0):
			MeshFactory.add(decor_root, MeshFactory.sphere(1.0, 10, 6), rock if i % 2 == 0 else rock2, p, Vector3(0, _rng.randf() * 360, 0), Vector3(_rng.randf_range(2, 4), _rng.randf_range(1.2, 2.5), _rng.randf_range(2, 4)))


func _lighthouse(pos: Vector3) -> void:
	var n := Node3D.new()
	n.name = "Lighthouse"
	decor_root.add_child(n)
	n.position = pos
	var red := MeshFactory.mat(Color(0.9, 0.2, 0.22), 0.6)
	var white := MeshFactory.mat(Color(0.97, 0.96, 0.92), 0.6)
	MeshFactory.add(n, MeshFactory.cylinder(6.0, 7.5, 3.0, 12), MeshFactory.mat(Color(0.55, 0.47, 0.4), 0.95), Vector3(0, 1.5, 0))
	for i in 6:
		var r0 := lerpf(3.2, 2.2, i / 6.0)
		var r1 := lerpf(3.2, 2.2, (i + 1) / 6.0)
		MeshFactory.add(n, MeshFactory.cylinder(r1, r0, 3.4, 16), red if i % 2 == 0 else white, Vector3(0, 3.0 + 1.7 + i * 3.4, 0))
	var top := 3.0 + 6 * 3.4
	MeshFactory.add(n, MeshFactory.cylinder(3.0, 3.0, 0.4, 16), MeshFactory.mat(Color(0.2, 0.2, 0.25), 0.4, 0.6), Vector3(0, top + 0.2, 0))
	MeshFactory.add(n, MeshFactory.cylinder(1.7, 1.7, 2.6, 16), MeshFactory.mat(Color(1.0, 0.92, 0.6), 0.2, 0.0, 4.0), Vector3(0, top + 1.7, 0))
	MeshFactory.add(n, MeshFactory.cylinder(0.0, 2.3, 2.0, 16), red, Vector3(0, top + 4.0, 0))
	var beam_root := Node3D.new()
	beam_root.position = Vector3(0, top + 1.7, 0)
	n.add_child(beam_root)
	var beam_m := MeshFactory.mat(Color(1.0, 0.95, 0.7, 0.1), 1.0, 0.0, 0.7, 0.0)
	for dir in [1.0, -1.0]:
		var b := MeshFactory.add(beam_root, MeshFactory.cylinder(0.6, 6.0, 60.0, 12), beam_m, Vector3(dir * 30.0, 0, 0), Vector3(0, 0, 90.0 * dir))
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spinners.append(beam_root)


func _beach_props() -> void:
	var cols := [Color(1.0, 0.35, 0.35), Color(0.2, 0.7, 1.0), Color(1.0, 0.8, 0.2), Color(0.5, 0.9, 0.5), Color(1.0, 0.55, 0.8)]
	var placed := 0
	var tries := 0
	while placed < 16 and tries < 200:
		tries += 1
		var p := Vector3(_rng.randf_range(35, 100), 0, _rng.randf_range(-120, 140))
		if not is_clear_of_road(p, 5.0) or is_excluded(p):
			continue
		var col: Color = cols[placed % cols.size()]
		if placed % 4 == 0:
			# beach hut
			var h := Node3D.new()
			decor_root.add_child(h)
			h.position = p
			h.rotation.y = _rng.randf() * TAU
			MeshFactory.add(h, MeshFactory.box(Vector3(4.0, 2.6, 3.4)), MeshFactory.mat(Color(0.95, 0.88, 0.72), 0.8), Vector3(0, 1.3, 0))
			var roof := PrismMesh.new()
			roof.size = Vector3(4.6, 1.6, 3.9)
			MeshFactory.add(h, roof, MeshFactory.mat(col, 0.7), Vector3(0, 3.4, 0))
			MeshFactory.add(h, MeshFactory.box(Vector3(1.0, 1.8, 0.1)), MeshFactory.mat(col.darkened(0.3), 0.7), Vector3(0, 0.9, 1.72))
		else:
			# umbrella + towel + surfboard
			var u := Node3D.new()
			decor_root.add_child(u)
			u.position = p
			MeshFactory.add(u, MeshFactory.cylinder(0.06, 0.06, 2.6, 6), MeshFactory.mat(Color(0.9, 0.9, 0.9), 0.5), Vector3(0, 1.3, 0))
			MeshFactory.add(u, MeshFactory.cylinder(0.05, 1.6, 0.6, 12), MeshFactory.mat(col, 0.6), Vector3(0, 2.6, 0))
			MeshFactory.add(u, MeshFactory.box(Vector3(1.0, 0.03, 1.9)), MeshFactory.mat(cols[(placed + 2) % cols.size()], 0.8), Vector3(0.8, 0.02, 0.6), Vector3(0, 20, 0))
			MeshFactory.add(u, MeshFactory.capsule(0.28, 2.2), MeshFactory.mat(cols[(placed + 1) % cols.size()], 0.4), Vector3(-0.9, 1.0, 0.2), Vector3(0, 0, 12), Vector3(1.0, 1.0, 0.25))
		exclusions.append({"pos": p, "r": 4.0})
		placed += 1


func _palms(density: float) -> void:
	var spots := roadside_points(13.0 / density, 3.0, 14.0, 3.0)
	for i in int(70 * density):
		var p := Vector3(_rng.randf_range(-200, 105), 0, _rng.randf_range(-200, 230))
		if is_clear_of_road(p, 6.0) and not is_excluded(p):
			spots.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p))
	var trunk := MultiMesh.new()
	trunk.transform_format = MultiMesh.TRANSFORM_3D
	trunk.mesh = MeshFactory.cylinder(0.22, 0.38, 1.0, 8)
	var leaf := MultiMesh.new()
	leaf.transform_format = MultiMesh.TRANSFORM_3D
	leaf.use_colors = true
	var lm := MeshFactory.box(Vector3(0.9, 0.08, 3.6))
	leaf.mesh = lm
	var nut := MultiMesh.new()
	nut.transform_format = MultiMesh.TRANSFORM_3D
	nut.mesh = MeshFactory.sphere(0.22, 8, 5)
	var t_x: Array[Transform3D] = []
	var l_x: Array[Transform3D] = []
	var l_c: Array[Color] = []
	var n_x: Array[Transform3D] = []
	for sp in spots:
		var h := _rng.randf_range(6.0, 9.0)
		var lean := _rng.randf_range(0.08, 0.22)
		var yaw := _rng.randf() * TAU
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		# trunk: 4 segments bending outward
		var prev := sp.origin
		for k in 4:
			var seg_top := sp.origin + Vector3.UP * h * (k + 1) / 4.0 + dir * lean * h * pow((k + 1) / 4.0, 2.0)
			var mid := (prev + seg_top) / 2.0
			var axis := (seg_top - prev).normalized()
			var b := Basis(Vector3.UP.cross(axis).normalized(), Vector3.UP.angle_to(axis)) if axis.cross(Vector3.UP).length() > 0.001 else Basis()
			t_x.append(Transform3D(b.scaled(Vector3(1.0 - k * 0.12, prev.distance_to(seg_top), 1.0 - k * 0.12)), mid))
			prev = seg_top
		var crown := prev
		for k in 8:
			var a := TAU * k / 8.0 + _rng.randf_range(-0.2, 0.2)
			var b2 := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, _rng.randf_range(0.35, 0.6))
			l_x.append(Transform3D(b2, crown + b2 * Vector3(0, 0, 1.6) + Vector3.UP * 0.1))
			l_c.append(Color(0.25, 0.7, 0.3).lightened(_rng.randf() * 0.15))
		for k in 3:
			n_x.append(Transform3D(Basis(), crown + Vector3(cos(k * 2.1) * 0.35, -0.35, sin(k * 2.1) * 0.35)))
	trunk.instance_count = t_x.size()
	for i in t_x.size():
		trunk.set_instance_transform(i, t_x[i])
	leaf.instance_count = l_x.size()
	for i in l_x.size():
		leaf.set_instance_transform(i, l_x[i])
		leaf.set_instance_color(i, l_c[i])
	nut.instance_count = n_x.size()
	for i in n_x.size():
		nut.set_instance_transform(i, n_x[i])
	for pair in [[trunk, MeshFactory.mat(Color(0.6, 0.45, 0.3), 0.9)], [leaf, MeshFactory.vertex_color_mat(0.75)], [nut, MeshFactory.mat(Color(0.4, 0.28, 0.15), 0.7)]]:
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = pair[0]
		mi.material_override = pair[1]
		decor_root.add_child(mi)


func _boats() -> void:
	var sails := [Color(1.0, 1.0, 1.0), Color(1.0, 0.5, 0.4), Color(0.4, 0.75, 1.0), Color(1.0, 0.85, 0.3)]
	for i in 6:
		var b := Node3D.new()
		decor_root.add_child(b)
		b.position = Vector3(_rng.randf_range(150, 330), 0.1, _rng.randf_range(-250, 260))
		b.rotation.y = _rng.randf() * TAU
		MeshFactory.add(b, MeshFactory.tapered_box(Vector2(2.2, 7.0), Vector2(3.0, 8.0), 1.2, 0.0), MeshFactory.mat(Color(0.95, 0.95, 0.97), 0.5), Vector3(0, -0.3, 0))
		MeshFactory.add(b, MeshFactory.box(Vector3(3.05, 0.25, 8.05)), MeshFactory.mat(Color(0.2, 0.4, 0.8), 0.5), Vector3(0, 0.75, 0))
		MeshFactory.add(b, MeshFactory.cylinder(0.12, 0.12, 9.0, 6), MeshFactory.mat(Color(0.5, 0.35, 0.25), 0.8), Vector3(0, 5.3, 0.5))
		var sail := PrismMesh.new()
		sail.size = Vector3(0.1, 7.0, 4.5)
		sail.left_to_right = 0.0
		MeshFactory.add(b, sail, MeshFactory.mat(sails[i % sails.size()], 0.7), Vector3(0, 5.0, -1.8))
		bobbers.append({"node": b, "y": 0.1, "amp": 0.25, "speed": 0.9 + i * 0.1, "phase": i * 1.7})


func _sea_arch(pos: Vector3) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 14.0
	ring.outer_radius = 22.0
	ring.rings = 24
	ring.ring_segments = 10
	var mi := MeshFactory.add(decor_root, ring, MeshFactory.mat(Color(0.6, 0.5, 0.42), 0.95), pos, Vector3(90, 30, 0), Vector3(1.0, 1.0, 1.4))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	MeshFactory.add(decor_root, MeshFactory.sphere(6.0, 10, 6), MeshFactory.mat(Color(0.35, 0.6, 0.35), 0.9), pos + Vector3(0, 22.0, 0), Vector3.ZERO, Vector3(1.6, 0.5, 1.4))


func _banners() -> void:
	var cols := [Color(0.1, 0.6, 0.9), Color(1.0, 0.5, 0.3)]
	var d := 120.0
	var i := 0
	while d < length - 40.0:
		var side := 1.0 if i % 2 == 0 else -1.0
		var t := transform_at(d, side * (half_width() + KERB_W + 0.9), 0.0)
		var n := Node3D.new()
		decor_root.add_child(n)
		n.global_transform = t
		n.rotate_object_local(Vector3.UP, deg_to_rad(side * 90.0))
		var col: Color = cols[i % 2]
		MeshFactory.add(n, MeshFactory.box(Vector3(9.0, 1.6, 0.15)), MeshFactory.mat(col, 0.5), Vector3(0, 1.9, 0))
		for face in [1.0, -1.0]:
			var l := MeshFactory.label3d("DRIFT RUSH  |  CORAL COAST", 90, Color.WHITE, col.darkened(0.5))
			l.position = Vector3(0, 1.9, 0.09 * face)
			if face < 0.0:
				l.rotation_degrees = Vector3(0, 180, 0)
			n.add_child(l)
		d += 140.0
		i += 1
