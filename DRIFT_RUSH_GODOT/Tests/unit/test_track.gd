extends TestCase
## Track generation: real meshes, collision, checkpoints, grid on the road.


func _make(path: String) -> TrackBuilder:
	var t: TrackBuilder = load(path).instantiate()
	spawn(t)
	return t


func test_sakura_valley_structure() -> void:
	var t := _make("res://Scenes/Tracks/SakuraValley.tscn")
	await physics_frames(2)
	check(t.length > 600.0, "track length > 600 m (got %.0f)" % t.length)
	check(t.checkpoints.size() >= 6, "at least 6 checkpoints")
	eq(t.checkpoints.size(), t.checkpoint_count, "checkpoint nodes == checkpoint_count")
	check(t.item_box_spots.size() >= 4, "item box spawn spots exist")
	check(t.min_radius() > 14.0, "min corner radius > 14 m (got %.1f) — walls must not self-intersect" % t.min_radius())
	check(t.get_node_or_null("Road") is MeshInstance3D, "road mesh exists")
	check((t.get_node("Road") as MeshInstance3D).mesh.get_surface_count() == 1, "road mesh has geometry")
	check(t.get_node_or_null("RoadBody") is StaticBody3D, "road collision body")
	check(t.get_node_or_null("WallBody") is StaticBody3D, "wall collision body")
	check(t.get_node_or_null("StartGantry") != null, "start gantry")
	check(t.get_node_or_null("Decor/Windmill") != null, "windmill decoration")
	check(t.get_node_or_null("Decor/Waterfall") != null, "waterfall decoration")
	check(t.get_node_or_null("Decor/Viaduct") != null, "arch viaduct decoration")
	# Closed loop: start == end
	near(t.curve.sample_baked(0.0).distance_to(t.curve.sample_baked(t.length)), 0.0, 0.5, "curve is closed")


func test_grid_slots_are_on_the_road() -> void:
	var t := _make("res://Scenes/Tracks/SakuraValley.tscn")
	await physics_frames(2)
	var space := t.get_world_3d().direct_space_state
	for slot in 8:
		var g := t.grid_transform(slot)
		var q := PhysicsRayQueryParameters3D.create(g.origin + Vector3.UP * 3.0, g.origin + Vector3.DOWN * 3.0, KartController.LAYER_WORLD)
		var hit := space.intersect_ray(q)
		check(not hit.is_empty(), "grid slot %d has road below" % slot)
		if not hit.is_empty():
			check(hit["collider"].name == "RoadBody", "grid slot %d is on RoadBody (got %s)" % [slot, hit["collider"].name])
		check(absf(t.lateral_distance(g.origin, t.closest_offset(g.origin))) < t.half_width() - 1.0, "grid slot %d within road width" % slot)


func test_walls_block_leaving_track() -> void:
	var t := _make("res://Scenes/Tracks/SakuraValley.tscn")
	await physics_frames(2)
	var space := t.get_world_3d().direct_space_state
	var bad := 0
	var d := 0.0
	while d < t.length:
		var f := t.frame_at(d)
		for side in [-1.0, 1.0]:
			var from: Vector3 = f["pos"] + Vector3.UP * 1.0
			var to: Vector3 = from + f["right"] * side * (t.half_width() + 6.0)
			var q := PhysicsRayQueryParameters3D.create(from, to, KartController.LAYER_WALLS)
			if space.intersect_ray(q).is_empty():
				bad += 1
		d += 10.0
	eq(bad, 0, "every sampled lateral ray hits a wall")


func test_neon_city_playable_structure() -> void:
	var t := _make("res://Scenes/Tracks/NeonCity.tscn")
	await physics_frames(2)
	check(t.length > 500.0, "neon city length > 500 m (got %.0f)" % t.length)
	check(t.checkpoints.size() >= 6, "neon city checkpoints")
	var wall_offset := t.half_width() + TrackBuilder.KERB_W + 0.8
	check(t.min_radius() > wall_offset + 1.0, "neon min radius %.1f > wall offset %.1f (walls cannot self-intersect)" % [t.min_radius(), wall_offset])
	check(bool(t.theme["night"]), "night theme")


func test_road_never_below_ground() -> void:
	for path in ["res://Scenes/Tracks/SakuraValley.tscn", "res://Scenes/Tracks/NeonCity.tscn"]:
		var t: TrackBuilder = load(path).instantiate()
		spawn(t)
		await physics_frames(1)
		var lowest := INF
		var d := 0.0
		while d < t.length:
			lowest = minf(lowest, (t.frame_at(d)["pos"] as Vector3).y)
			d += 1.0
		check(lowest >= 0.0, "%s road surface stays above the grass (lowest centre y %.3f)" % [path.get_file(), lowest])
