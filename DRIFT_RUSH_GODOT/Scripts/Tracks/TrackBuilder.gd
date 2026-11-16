class_name TrackBuilder
extends Node3D
## Builds a drivable closed-loop track from control points:
## Curve3D centre line → road mesh + trimesh collision, kerbs, guard walls with
## collision, ground, checkpoints (Area3D), start gantry, grid slots, item box
## spots, respawn frames, lighting/sky. Subclasses define points + decoration.

signal checkpoint_passed(kart: KartController, index: int)

const ROAD_Y := 0.06
const KERB_W := 1.2
const WALL_H_VISUAL := 1.05
const WALL_H_COLLISION := 3.0
const ROAD_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform vec4 asphalt : source_color = vec4(0.36, 0.37, 0.42, 1.0);
uniform vec4 line_color : source_color = vec4(0.97, 0.97, 0.97, 1.0);
uniform vec4 center_color : source_color = vec4(1.0, 0.86, 0.35, 1.0);
uniform float emission_lines = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = UV; // x: 0..1 across the road, y: metres along the track
	vec3 c = asphalt.rgb;
	float n = hash(floor(uv * vec2(60.0, 6.0)));
	float n2 = hash(floor(uv * vec2(9.0, 0.7)));
	c *= 0.93 + 0.07 * n + 0.05 * n2;
	float edge = step(uv.x, 0.035) + step(0.965, uv.x);
	float dash = step(abs(uv.x - 0.5), 0.009) * step(0.5, fract(uv.y / 7.0));
	vec3 em = vec3(0.0);
	c = mix(c, line_color.rgb, clamp(edge, 0.0, 1.0));
	em += line_color.rgb * clamp(edge, 0.0, 1.0) * emission_lines;
	c = mix(c, center_color.rgb, dash);
	// start / finish checker (y in [0, 3])
	if (uv.y > 0.0 && uv.y < 3.0) {
		float chk = mod(floor(uv.x * 14.0) + floor(uv.y * 1.6), 2.0);
		c = mix(vec3(0.08), vec3(0.97), chk);
	}
	ALBEDO = c;
	ROUGHNESS = 0.82;
	EMISSION = em;
}
"""

@export var track_id := "track"
@export var display_name := "Track"
@export var road_width := 14.0
@export var checkpoint_count := 8
@export var xz_scale := 1.0

var control_points := PackedVector3Array()
var theme := {
	"sky_top": Color(0.33, 0.6, 0.96), "sky_horizon": Color(0.82, 0.9, 1.0),
	"ground": Color(0.55, 0.8, 0.38), "ground_horizon": Color(0.7, 0.85, 0.6),
	"asphalt": Color(0.36, 0.37, 0.42), "lines": Color(0.97, 0.97, 0.97),
	"center": Color(1.0, 0.86, 0.35), "line_emission": 0.0,
	"kerb_a": Color(0.92, 0.15, 0.2), "kerb_b": Color(0.98, 0.98, 0.98),
	"wall_a": Color(0.95, 0.2, 0.25), "wall_b": Color(0.98, 0.98, 0.98), "wall_emission": 0.0,
	"sun_color": Color(1.0, 0.94, 0.84), "sun_energy": 1.25, "sun_angle": Vector3(-48, -35, 0),
	"ambient_energy": 0.9, "fog_color": Color(0.95, 0.88, 0.92), "fog_density": 0.0025,
	"glow": 0.4, "night": false, "petals": true,
}
var curve: Curve3D
var length := 0.0
var min_y := 0.0
var checkpoints: Array[Checkpoint] = []
var item_box_spots: Array[Transform3D] = []
var quality: Dictionary = {}
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var decor_root: Node3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = hash(track_id)
	quality = GameFlow.quality_profile() if is_instance_valid(GameFlow) else {"shadows": true, "tree_density": 1.0, "glow": true, "fog": true, "particles": 1.0}
	_define_track()
	build()


## Override: fill control_points, theme, etc.
func _define_track() -> void:
	pass


## Override: add scenery.
func _decorate() -> void:
	pass


func build() -> void:
	var pts := PackedVector3Array()
	for p in control_points:
		pts.append(Vector3(p.x * xz_scale, p.y, p.z * xz_scale))
	curve = make_closed_curve(pts)
	length = curve.get_baked_length()
	min_y = 0.0
	for p in pts:
		min_y = minf(min_y, p.y)
	decor_root = Node3D.new()
	decor_root.name = "Decor"
	add_child(decor_root)
	_build_environment()
	_build_ground()
	_build_road()
	_build_walls()
	_build_checkpoints()
	_build_start_gantry()
	_compute_item_spots()
	_decorate()


static func make_closed_curve(pts: PackedVector3Array, interval := 1.0) -> Curve3D:
	var c := Curve3D.new()
	c.bake_interval = interval
	var n := pts.size()
	for i in n + 1:
		var p := pts[i % n]
		var prev := pts[(i - 1 + n) % n]
		var nxt := pts[(i + 1) % n]
		var tan := (nxt - prev) / 5.0
		c.add_point(p, -tan, tan)
	return c


## Centre-line frame at distance d (wraps). Right vector is kept horizontal.
func frame_at(d: float) -> Dictionary:
	d = fposmod(d, length)
	var p := curve.sample_baked(d, true)
	var a := curve.sample_baked(fposmod(d - 1.5, length), true)
	var b := curve.sample_baked(fposmod(d + 1.5, length), true)
	var fwd := b - a
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	if flat == Vector3.ZERO:
		flat = Vector3.FORWARD
	var right := flat.cross(Vector3.UP).normalized()
	return {"pos": p, "forward": fwd.normalized(), "flat": flat, "right": right}


## Transform on the road surface at distance d and lateral offset, facing forward.
func transform_at(d: float, lateral := 0.0, lift := 0.0) -> Transform3D:
	var f := frame_at(d)
	var origin: Vector3 = f["pos"] + f["right"] * lateral + Vector3.UP * (ROAD_Y + lift)
	var basis := Basis.looking_at(f["flat"], Vector3.UP)
	return global_transform * Transform3D(basis, origin)


func closest_offset(world_pos: Vector3) -> float:
	return curve.get_closest_offset(to_local(world_pos))


func lateral_distance(world_pos: Vector3, offset: float) -> float:
	var f := frame_at(offset)
	var lp := to_local(world_pos)
	return (lp - f["pos"]).dot(f["right"])


func tangent_at(offset: float) -> Vector3:
	return frame_at(offset)["flat"]


## Starting grid: two staggered columns behind the start line.
func grid_transform(slot: int) -> Transform3D:
	var row := slot / 2
	var col := slot % 2
	var d := -9.0 - row * 6.5 - col * 2.5
	var lateral := -3.2 if col == 0 else 3.2
	return transform_at(d, lateral, 0.05)


func half_width() -> float:
	return road_width / 2.0


## Minimum curvature radius of the centre line (QA / test helper).
func min_radius(step := 4.0) -> float:
	var best := INF
	var d := 0.0
	while d < length:
		var a: Vector3 = frame_at(d - step)["flat"]
		var b: Vector3 = frame_at(d + step)["flat"]
		var ang := a.angle_to(b)
		if ang > 0.0001:
			best = minf(best, (2.0 * step) / ang)
		d += step
	return best


# ------------------------------------------------------------------ building
func _build_environment() -> void:
	world_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = theme["sky_top"]
	sm.sky_horizon_color = theme["sky_horizon"]
	sm.ground_horizon_color = theme["ground_horizon"]
	sm.ground_bottom_color = Color(theme["ground"]).darkened(0.3)
	sm.sun_angle_max = 30.0
	sm.sky_curve = 0.12
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = theme["ambient_energy"]
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.03
	if quality.get("glow", true):
		env.glow_enabled = true
		env.glow_intensity = theme["glow"]
		env.glow_bloom = 0.05
		env.glow_hdr_threshold = 1.0
	if quality.get("fog", true) and float(theme["fog_density"]) > 0.0:
		env.fog_enabled = true
		env.fog_light_color = theme["fog_color"]
		env.fog_density = theme["fog_density"]
		env.fog_sky_affect = 0.15
		env.fog_aerial_perspective = 0.3
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.light_color = theme["sun_color"]
	sun.light_energy = theme["sun_energy"]
	sun.rotation_degrees = theme["sun_angle"]
	sun.shadow_enabled = bool(quality.get("shadows", true))
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_blur = 1.5
	add_child(sun)


func _build_ground() -> void:
	var size := 1400.0
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	pm.subdivide_width = 0
	pm.subdivide_depth = 0
	var gm := StandardMaterial3D.new()
	gm.albedo_color = theme["ground"]
	gm.roughness = 0.95
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var nt := NoiseTexture2D.new()
	nt.noise = noise
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var grad := Gradient.new()
	grad.set_color(0, Color(theme["ground"]).darkened(0.12))
	grad.set_color(1, Color(theme["ground"]).lightened(0.1))
	nt.color_ramp = grad
	gm.albedo_texture = nt
	gm.albedo_color = Color.WHITE
	gm.uv1_scale = Vector3(60, 60, 1)
	var gmi := MeshFactory.add(self, pm, gm, Vector3(0, 0, 0))
	gmi.name = "Ground"
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = KartController.LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size, 2.0, size)
	cs.shape = bs
	cs.position = Vector3(0, -1.0, 0)
	body.add_child(cs)
	add_child(body)


func _segments(step: float) -> int:
	return maxi(16, int(ceil(length / step)))


func _build_road() -> void:
	var hw := half_width()
	var n := _segments(2.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kerb := SurfaceTool.new()
	kerb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var prev: Dictionary = {}
	for i in n + 1:
		var d := length * float(i) / float(n)
		var f := frame_at(d)
		var p: Vector3 = f["pos"] + Vector3.UP * ROAD_Y
		var r: Vector3 = f["right"]
		var cur := {
			"d": d, "l": p - r * hw, "r": p + r * hw,
			"kl": p - r * (hw + KERB_W) + Vector3.UP * 0.03, "kr": p + r * (hw + KERB_W) + Vector3.UP * 0.03,
			"il": p - r * hw + Vector3.UP * 0.03, "ir": p + r * hw + Vector3.UP * 0.03,
		}
		if not prev.is_empty():
			var v0: float = prev["d"]
			MeshFactory.quad(st, prev["l"], prev["r"], cur["r"], cur["l"], Color.WHITE,
				Vector2(0, v0), Vector2(1, v0), Vector2(1, d), Vector2(0, d))
			faces.append_array([prev["l"], cur["r"], prev["r"], prev["l"], cur["l"], cur["r"]])
			var kc: Color = theme["kerb_a"] if (i / 2) % 2 == 0 else theme["kerb_b"]
			MeshFactory.quad(kerb, prev["kl"], prev["il"], cur["il"], cur["kl"], kc)
			MeshFactory.quad(kerb, prev["ir"], prev["kr"], cur["kr"], cur["ir"], kc)
			faces.append_array([prev["kl"], cur["il"], prev["il"], prev["kl"], cur["kl"], cur["il"]])
			faces.append_array([prev["ir"], cur["kr"], prev["kr"], prev["ir"], cur["ir"], cur["kr"]])
		prev = cur
	var road_mesh := st.commit()
	var sh := Shader.new()
	sh.code = ROAD_SHADER
	var rm := ShaderMaterial.new()
	rm.shader = sh
	rm.set_shader_parameter("asphalt", theme["asphalt"])
	rm.set_shader_parameter("line_color", theme["lines"])
	rm.set_shader_parameter("center_color", theme["center"])
	rm.set_shader_parameter("emission_lines", theme["line_emission"])
	var road := MeshFactory.add(self, road_mesh, rm)
	road.name = "Road"
	var km := MeshFactory.add(self, kerb.commit(), MeshFactory.vertex_color_mat(0.6))
	km.name = "Kerbs"
	var body := StaticBody3D.new()
	body.name = "RoadBody"
	body.collision_layer = KartController.LAYER_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	# Supports under elevated sections
	var pillar_mat := MeshFactory.mat(Color(0.82, 0.78, 0.72), 0.9)
	var d2 := 0.0
	while d2 < length:
		var f2 := frame_at(d2)
		var y: float = f2["pos"].y
		if y > 1.6:
			for side in [-1.0, 1.0]:
				var bp: Vector3 = f2["pos"] + f2["right"] * side * (hw - 1.0)
				MeshFactory.add(decor_root, MeshFactory.box(Vector3(1.2, y, 1.2)), pillar_mat, Vector3(bp.x, y / 2.0, bp.z))
		d2 += 14.0


func _build_walls() -> void:
	var hw := half_width() + KERB_W + 0.35
	var n := _segments(2.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var thick := 0.45
	for side in [-1.0, 1.0]:
		var prev: Dictionary = {}
		for i in n + 1:
			var d := length * float(i) / float(n)
			var f := frame_at(d)
			var base: Vector3 = f["pos"]
			var r: Vector3 = f["right"]
			var inner: Vector3 = base + r * side * hw
			var outer: Vector3 = base + r * side * (hw + thick)
			var bottom := minf(0.0, base.y) - 0.3
			var road_y := base.y + ROAD_Y
			var cur := {
				"ib": Vector3(inner.x, bottom, inner.z), "it": Vector3(inner.x, road_y + WALL_H_VISUAL, inner.z),
				"ob": Vector3(outer.x, bottom, outer.z), "ot": Vector3(outer.x, road_y + WALL_H_VISUAL, outer.z),
				"ct": Vector3(inner.x, road_y + WALL_H_COLLISION, inner.z), "cb": Vector3(inner.x, road_y - 0.5, inner.z),
			}
			if not prev.is_empty():
				var col: Color = theme["wall_a"] if (i / 2) % 2 == 0 else theme["wall_b"]
				# Corners are passed counter-clockwise as seen from outside each face
				# (inner face looks toward the road, outer face away, top face up).
				if side > 0.0:
					MeshFactory.quad(st, cur["ib"], prev["ib"], prev["it"], cur["it"], col)
					MeshFactory.quad(st, prev["ob"], cur["ob"], cur["ot"], prev["ot"], col.darkened(0.15))
					MeshFactory.quad(st, prev["it"], prev["ot"], cur["ot"], cur["it"], col.lightened(0.1))
				else:
					MeshFactory.quad(st, prev["ib"], cur["ib"], cur["it"], prev["it"], col)
					MeshFactory.quad(st, cur["ob"], prev["ob"], prev["ot"], cur["ot"], col.darkened(0.15))
					MeshFactory.quad(st, prev["ot"], prev["it"], cur["it"], cur["ot"], col.lightened(0.1))
				faces.append_array([prev["cb"], cur["ct"], cur["cb"], prev["cb"], prev["ct"], cur["ct"]])
			prev = cur
	var wm := MeshFactory.vertex_color_mat(0.55)
	if float(theme["wall_emission"]) > 0.0:
		wm = StandardMaterial3D.new()
		wm.vertex_color_use_as_albedo = true
		wm.emission_enabled = true
		wm.emission = Color(1, 1, 1)
		wm.emission_energy_multiplier = theme["wall_emission"]
		wm.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	var walls := MeshFactory.add(self, st.commit(), wm)
	walls.name = "Walls"
	var body := StaticBody3D.new()
	body.name = "WallBody"
	body.collision_layer = KartController.LAYER_WALLS
	body.collision_mask = 0
	body.add_to_group("walls")
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


func _build_checkpoints() -> void:
	checkpoints.clear()
	for i in checkpoint_count:
		var d := length * float(i) / float(checkpoint_count)
		var cp := Checkpoint.new(i)
		cp.name = "Checkpoint%d" % i
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(road_width + KERB_W * 2.0 + 2.0, 5.0, 2.0)
		cs.shape = bs
		cs.position = Vector3(0, 2.0, 0)
		cp.add_child(cs)
		add_child(cp)
		cp.global_transform = transform_at(d)
		cp.kart_passed.connect(func(k: KartController, idx: int): checkpoint_passed.emit(k, idx))
		checkpoints.append(cp)


func _build_start_gantry() -> void:
	var t := transform_at(1.5)
	var g := Node3D.new()
	g.name = "StartGantry"
	add_child(g)
	g.global_transform = t
	var hw := half_width() + KERB_W + 1.2
	var post := MeshFactory.mat(Color(0.15, 0.2, 0.45), 0.4, 0.4)
	MeshFactory.add(g, MeshFactory.box(Vector3(0.7, 7.0, 0.7)), post, Vector3(-hw, 3.5, 0))
	MeshFactory.add(g, MeshFactory.box(Vector3(0.7, 7.0, 0.7)), post, Vector3(hw, 3.5, 0))
	MeshFactory.add(g, MeshFactory.box(Vector3(hw * 2.0 + 0.7, 1.6, 0.5)), MeshFactory.mat(Color(0.08, 0.12, 0.3), 0.4), Vector3(0, 6.6, 0))
	var accent := MeshFactory.mat(Color(0.2, 0.7, 1.0), 0.3, 0.0, 2.0)
	MeshFactory.add(g, MeshFactory.box(Vector3(hw * 2.0 + 0.7, 0.12, 0.55)), accent, Vector3(0, 5.75, 0))
	MeshFactory.add(g, MeshFactory.box(Vector3(hw * 2.0 + 0.7, 0.12, 0.55)), accent, Vector3(0, 7.45, 0))
	for face in [-1.0, 1.0]:
		var l := MeshFactory.label3d("DRIFT RUSH", 160, Color(1.0, 0.75, 0.2), Color(0.1, 0.05, 0.2))
		l.position = Vector3(0, 6.6, 0.3 * face)
		if face < 0.0:
			l.rotation_degrees = Vector3(0, 180, 0)
		g.add_child(l)


func _compute_item_spots() -> void:
	item_box_spots.clear()
	for frac in [0.3, 0.68]:
		var d := length * float(frac)
		for lat in [-4.5, -1.5, 1.5, 4.5]:
			item_box_spots.append(transform_at(d, float(lat), 1.0))


## True when a world XZ position is at least `margin` metres outside the road edge.
func is_clear_of_road(p: Vector3, margin: float) -> bool:
	var lp := to_local(p)
	var cp := curve.get_closest_point(Vector3(lp.x, lp.y, lp.z))
	var dx := Vector2(lp.x - cp.x, lp.z - cp.z).length()
	if dx < half_width() + KERB_W + margin:
		return false
	# get_closest_point uses 3D distance; double check with a coarse 2D scan.
	var d := 0.0
	while d < length:
		var q := curve.sample_baked(d)
		if Vector2(lp.x - q.x, lp.z - q.z).length() < half_width() + KERB_W + margin:
			return false
		d += 6.0
	return true


## Points along both sides outside the walls, for scenery placement.
func roadside_points(spacing: float, min_off: float, max_off: float, jitter := 2.0) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var d := 0.0
	while d < length:
		for side in [-1.0, 1.0]:
			var off := _rng.randf_range(min_off, max_off)
			var f := frame_at(d + _rng.randf_range(-jitter, jitter))
			var p: Vector3 = f["pos"] + f["right"] * side * (half_width() + KERB_W + off)
			p.y = 0.0
			if is_clear_of_road(p, min_off * 0.6):
				out.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p))
		d += spacing
	return out
