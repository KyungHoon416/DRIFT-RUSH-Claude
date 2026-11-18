class_name MeshFactory
extends RefCounted
## Small helpers to build stylized low-poly meshes and materials in code.
## All 3D art in this project is generated here (no third-party models).
## Winding: Godot treats CLOCKWISE triangles as front faces. quad() takes the
## four corners counter-clockwise as seen from the front and emits CW triangles.

static var _mat_cache: Dictionary = {}


static func mat(col: Color, rough := 0.6, metal := 0.0, emission_energy := 0.0, rim := 0.25) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f|%.2f" % [col.to_html(), rough, metal, emission_energy, rim]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if rim > 0.0:
		m.rim_enabled = true
		m.rim = rim
		m.rim_tint = 0.4
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emission_energy
	if col.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_cache[key] = m
	return m


static func unique_mat(col: Color, rough := 0.5, metal := 0.15) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	m.rim_enabled = true
	m.rim = 0.3
	m.rim_tint = 0.5
	return m


static func vertex_color_mat(rough := 0.8, unshaded := false) -> StandardMaterial3D:
	var key := "vc|%.2f|%s" % [rough, unshaded]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_cache[key] = m
	return m


static func add(parent: Node3D, mesh: Mesh, material: Material, pos := Vector3.ZERO, rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if material:
		mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func sphere(r: float, segs := 16, rings := 8) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = rings
	return s


static func cylinder(top_r: float, bottom_r: float, h: float, segs := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bottom_r
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 4
	return c


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col := Color.WHITE, uv_a := Vector2(0, 0), uv_b := Vector2(1, 0), uv_c := Vector2(1, 1), uv_d := Vector2(0, 1)) -> void:
	var n := (b - a).cross(d - a).normalized()
	if n == Vector3.ZERO:
		n = Vector3.UP
	_v(st, a, n, col, uv_a)
	_v(st, c, n, col, uv_c)
	_v(st, b, n, col, uv_b)
	_v(st, a, n, col, uv_a)
	_v(st, d, n, col, uv_d)
	_v(st, c, n, col, uv_c)


static func _v(st: SurfaceTool, p: Vector3, n: Vector3, col: Color, uv: Vector2) -> void:
	st.set_normal(n)
	st.set_color(col)
	st.set_uv(uv)
	st.add_vertex(p)


## Frustum-like box: bottom footprint (w, l) and top footprint (w, l), height h.
## top_shift_z moves the top face forward/back (negative = toward -Z/front).
static func tapered_box(bottom: Vector2, top: Vector2, h: float, top_shift_z := 0.0, col := Color.WHITE) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bw := bottom.x / 2.0
	var bl := bottom.y / 2.0
	var tw := top.x / 2.0
	var tl := top.y / 2.0
	# bottom corners (y=0): front-left, front-right, back-right, back-left (front = -Z)
	var b0 := Vector3(-bw, 0, -bl)
	var b1 := Vector3(bw, 0, -bl)
	var b2 := Vector3(bw, 0, bl)
	var b3 := Vector3(-bw, 0, bl)
	var t0 := Vector3(-tw, h, -tl + top_shift_z)
	var t1 := Vector3(tw, h, -tl + top_shift_z)
	var t2 := Vector3(tw, h, tl + top_shift_z)
	var t3 := Vector3(-tw, h, tl + top_shift_z)
	# Faces listed CCW when viewed from outside.
	quad(st, t3, t2, t1, t0, col)      # top (viewed from above: back-left, back-right, front-right, front-left)
	quad(st, b0, b1, b2, b3, col)      # bottom
	quad(st, b0, t0, t1, b1, col)      # front (-Z)
	quad(st, b2, t2, t3, b3, col)      # back (+Z)
	quad(st, b1, t1, t2, b2, col)      # right (+X)
	quad(st, b3, t3, t0, b0, col)      # left (-X)
	return st.commit()


static func label3d(text: String, size := 64, col := Color.WHITE, outline := Color(0, 0, 0)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UITheme.display_font()
	l.font_size = size
	l.modulate = col
	l.outline_modulate = outline
	l.outline_size = 12
	l.pixel_size = 0.01
	return l


static var _soft_dot: GradientTexture2D


## Round, soft-edged sprite so particles never look like square tiles.
static func soft_dot() -> GradientTexture2D:
	if _soft_dot == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.65), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_soft_dot = t
	return _soft_dot


static func particle_material(col: Color, additive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = soft_dot()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = col
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


static func fade_gradient(c0: Color, c1: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	return g
