class_name KartPreview
extends SubViewportContainer
## Real-time 3D kart on a turntable (lobby / garage). Drag to rotate 360°.

var viewport: SubViewport
var pivot: Node3D
var model: KartModel
var auto_rotate := true
var garage_scene := true
var _dragging := false
var _yaw := 0.6


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.msaa_3d = Viewport.MSAA_2X if GameFlow.quality_profile()["name"] != "low" else Viewport.MSAA_DISABLED
	add_child(viewport)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("101d4a")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.85)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.6
	env.environment = e
	viewport.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -35, 0)
	key.light_energy = 1.3
	key.light_color = Color(1.0, 0.95, 0.88)
	key.shadow_enabled = true
	viewport.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-3, 2.5, -3)
	rim.light_color = Color(0.3, 0.6, 1.0)
	rim.light_energy = 3.0
	rim.omni_range = 9.0
	viewport.add_child(rim)
	var warm := OmniLight3D.new()
	warm.position = Vector3(3, 2.0, 2.5)
	warm.light_color = Color(1.0, 0.45, 0.75)
	warm.light_energy = 1.8
	warm.omni_range = 8.0
	viewport.add_child(warm)
	if garage_scene:
		_build_garage()
	pivot = Node3D.new()
	viewport.add_child(pivot)
	model = KartModel.new()
	pivot.add_child(model)
	model.build(GameFlow.kart_color(String(SaveSettings.get_value("kart_color"))), false, 0.0)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 2.2, 5.2)
	cam.fov = 45
	viewport.add_child(cam)
	cam.look_at(Vector3(0, 0.8, 0), Vector3.UP)
	cam.current = true


func _build_garage() -> void:
	var root := Node3D.new()
	viewport.add_child(root)
	var floor_m := MeshFactory.mat(Color(0.12, 0.14, 0.24), 0.35, 0.3)
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	MeshFactory.add(root, pm, floor_m)
	var ring := TorusMesh.new()
	ring.inner_radius = 2.6
	ring.outer_radius = 2.8
	MeshFactory.add(root, ring, MeshFactory.mat(Color(0.25, 0.65, 1.0), 0.2, 0.0, 3.0), Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1, 0.05, 1))
	MeshFactory.add(root, MeshFactory.cylinder(2.6, 2.6, 0.08, 40), MeshFactory.mat(Color(0.2, 0.22, 0.35), 0.3, 0.5), Vector3(0, 0.04, 0))
	var wall := MeshFactory.mat(Color(0.14, 0.16, 0.3), 0.8)
	MeshFactory.add(root, MeshFactory.box(Vector3(30, 10, 0.4)), wall, Vector3(0, 5, -8))
	MeshFactory.add(root, MeshFactory.box(Vector3(0.4, 10, 30)), wall, Vector3(-9, 5, 0))
	MeshFactory.add(root, MeshFactory.box(Vector3(0.4, 10, 30)), wall, Vector3(9, 5, 0))
	# tyre stacks + neon sign
	var tire := MeshFactory.mat(Color(0.08, 0.08, 0.1), 0.9)
	for x in [-6.5, -5.3, 5.6]:
		for y in 4:
			MeshFactory.add(root, MeshFactory.cylinder(0.55, 0.55, 0.35, 14), tire, Vector3(x, 0.18 + y * 0.36, -6.5))
	var sign := MeshFactory.label3d("DRIFT RUSH", 220, Color(1.0, 0.6, 0.25), Color(0.6, 0.1, 0.5))
	sign.position = Vector3(0, 3.2, -7.7)
	sign.font_size = 150
	sign.modulate = Color(1.6, 1.0, 0.6)
	root.add_child(sign)
	MeshFactory.add(root, MeshFactory.box(Vector3(12, 0.12, 0.12)), MeshFactory.mat(Color(1.0, 0.3, 0.8), 0.2, 0.0, 4.0), Vector3(0, 2.3, -7.7))
	MeshFactory.add(root, MeshFactory.box(Vector3(12, 0.12, 0.12)), MeshFactory.mat(Color(0.2, 0.8, 1.0), 0.2, 0.0, 4.0), Vector3(0, 4.1, -7.7))


func set_color(c: Color) -> void:
	if model:
		model.set_paint(c)


func _process(delta: float) -> void:
	if pivot == null:
		return
	if auto_rotate and not _dragging:
		_yaw += delta * 0.45
	pivot.rotation.y = _yaw
	model.animate(delta, 0.0, 0.0, 0, 0.0, false, 0.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_dragging = (event as InputEventMouseButton).pressed
	elif event is InputEventMouseMotion and _dragging:
		_yaw += (event as InputEventMouseMotion).relative.x * 0.01
	elif event is InputEventScreenDrag:
		_yaw += (event as InputEventScreenDrag).relative.x * 0.01
