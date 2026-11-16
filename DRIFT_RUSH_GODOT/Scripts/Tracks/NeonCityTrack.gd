extends TrackBuilder
## Neon City — night city circuit with tight 90° corners (playable prototype:
## full race logic, simpler scenery than Sakura Valley).

const WINDOW_SHADER := """
shader_type spatial;
uniform vec4 base : source_color = vec4(0.07, 0.08, 0.16, 1.0);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 c = base.rgb;
	float row = step(0.35, fract(wpos.y / 3.2)) * step(fract(wpos.y / 3.2), 0.8);
	float colx = step(0.25, fract((wpos.x + wpos.z) / 2.6)) * step(fract((wpos.x + wpos.z) / 2.6), 0.7);
	float lit = step(0.45, fract(sin(dot(floor(vec2(wpos.y / 3.2, (wpos.x + wpos.z) / 2.6)), vec2(12.9898, 78.233))) * 43758.5453));
	float w = row * colx * lit * step(1.0, wpos.y);
	vec3 wc = mix(vec3(0.3, 0.8, 1.0), vec3(1.0, 0.45, 0.85), step(0.5, fract(wpos.x * 0.013)));
	ALBEDO = c;
	ROUGHNESS = 0.5;
	EMISSION = wc * w * 2.2 * COLOR.rgb;
}
"""

var _t := 0.0
var _pulse: Array[MeshInstance3D] = []


func _define_track() -> void:
	track_id = "neon_city"
	display_name = "Neon City"
	road_width = 14.0
	checkpoint_count = 8
	xz_scale = 1.6
	control_points = PackedVector3Array([
		Vector3(0, 0, 40), Vector3(0, 0, -60), Vector3(15, 0, -85), Vector3(60, 0, -90),
		Vector3(85, 0, -70), Vector3(90, 0, -20), Vector3(110, 0, 5), Vector3(150, 0, 10),
		Vector3(170, 0, 35), Vector3(165, 0, 80), Vector3(130, 0, 95), Vector3(80, 0, 90),
		Vector3(55, 0, 110), Vector3(20, 0, 115), Vector3(0, 0, 90),
	])
	theme.merge({
		"sky_top": Color(0.05, 0.03, 0.16), "sky_horizon": Color(0.35, 0.12, 0.45),
		"ground": Color(0.12, 0.12, 0.2), "ground_horizon": Color(0.2, 0.08, 0.3),
		"asphalt": Color(0.16, 0.16, 0.22), "lines": Color(0.3, 0.9, 1.0), "center": Color(1.0, 0.35, 0.8),
		"line_emission": 1.5,
		"kerb_a": Color(0.2, 0.85, 1.0), "kerb_b": Color(1.0, 0.25, 0.75),
		"wall_a": Color(0.15, 0.9, 1.0), "wall_b": Color(1.0, 0.3, 0.8), "wall_emission": 0.9,
		"sun_color": Color(0.6, 0.55, 1.0), "sun_energy": 0.45, "sun_angle": Vector3(-60, 40, 0),
		"ambient_energy": 0.55, "fog_color": Color(0.35, 0.15, 0.45), "fog_density": 0.004,
		"glow": 0.9, "night": true, "petals": false,
	}, true)


func _process(delta: float) -> void:
	_t += delta
	for i in _pulse.size():
		_pulse[i].scale = Vector3.ONE * (1.0 + 0.06 * sin(_t * 3.0 + i))


func _decorate() -> void:
	_buildings(float(quality.get("tree_density", 1.0)))
	_neon_gates()
	_street_lights()


func _buildings(density: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = MeshFactory.box(Vector3.ONE)
	var transforms: Array[Transform3D] = []
	for t in roadside_points(16.0 / density, 6.0, 22.0, 4.0):
		var h := _rng.randf_range(14, 60)
		var w := _rng.randf_range(8, 16)
		transforms.append(Transform3D(t.basis.scaled(Vector3(w, h, w)), t.origin + Vector3(0, h / 2.0, 0)))
	for i in int(120 * density):
		var p := Vector3(_rng.randf_range(-150, 330), 0, _rng.randf_range(-230, 260))
		if is_clear_of_road(p, 14.0):
			var h := _rng.randf_range(20, 90)
			var w := _rng.randf_range(10, 22)
			transforms.append(Transform3D(Basis().scaled(Vector3(w, h, w)), p + Vector3(0, h / 2.0, 0)))
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, Color.WHITE if _rng.randf() < 0.85 else Color(0.3, 0.3, 0.3))
	var sh := Shader.new()
	sh.code = WINDOW_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	decor_root.add_child(mmi)


func _neon_gates() -> void:
	var cols := [Color(0.2, 0.9, 1.0), Color(1.0, 0.3, 0.8), Color(0.6, 0.4, 1.0)]
	var i := 0
	var d := 80.0
	while d < length - 40.0:
		var t := transform_at(d)
		var g := Node3D.new()
		decor_root.add_child(g)
		g.global_transform = t
		var col: Color = cols[i % cols.size()]
		var m := MeshFactory.mat(col, 0.3, 0.0, 3.0)
		var hw := half_width() + KERB_W + 1.0
		_pulse.append(MeshFactory.add(g, MeshFactory.box(Vector3(0.4, 8, 0.4)), m, Vector3(-hw, 4, 0)))
		_pulse.append(MeshFactory.add(g, MeshFactory.box(Vector3(0.4, 8, 0.4)), m, Vector3(hw, 4, 0)))
		MeshFactory.add(g, MeshFactory.box(Vector3(hw * 2.0, 0.4, 0.4)), m, Vector3(0, 8, 0))
		var l := MeshFactory.label3d("NEON CITY", 140, col.lightened(0.4), col.darkened(0.6))
		l.position = Vector3(0, 9.2, 0)
		l.rotation_degrees = Vector3(0, 180, 0)
		g.add_child(l)
		d += 150.0
		i += 1


func _street_lights() -> void:
	var pole := MeshFactory.mat(Color(0.2, 0.2, 0.28), 0.4, 0.6)
	var lamp := MeshFactory.mat(Color(1.0, 0.85, 0.6), 0.3, 0.0, 4.0)
	var d := 0.0
	var lights := 0
	while d < length:
		for side in [-1.0, 1.0]:
			var t := transform_at(d, side * (half_width() + KERB_W + 1.6))
			var n := Node3D.new()
			decor_root.add_child(n)
			n.global_transform = t
			MeshFactory.add(n, MeshFactory.cylinder(0.12, 0.16, 7, 6), pole, Vector3(0, 3.5, 0))
			MeshFactory.add(n, MeshFactory.box(Vector3(1.6, 0.25, 0.5)), lamp, Vector3(-side * 0.7, 7.0, 0))
			if bool(quality.get("decor_lights", false)) and lights < 16 and side > 0.0:
				var ol := OmniLight3D.new()
				ol.light_color = Color(1.0, 0.8, 0.6)
				ol.light_energy = 1.5
				ol.omni_range = 14.0
				ol.position = Vector3(-side * 0.7, 6.5, 0)
				n.add_child(ol)
				lights += 1
		d += 45.0
