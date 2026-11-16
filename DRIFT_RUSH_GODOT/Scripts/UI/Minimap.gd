class_name Minimap
extends Control
## Track-shaped minimap drawn from the real Curve3D (XZ projection).

var track: TrackBuilder
var karts: Array[KartController] = []
var player: KartController
var _poly := PackedVector2Array()
var _min := Vector2.ZERO
var _scale := 1.0
var _pad := 12.0


func setup(t: TrackBuilder, kart_list: Array[KartController], me: KartController) -> void:
	track = t
	karts = kart_list
	player = me
	_build()
	resized.connect(_build)


func _build() -> void:
	if track == null:
		return
	var raw := PackedVector2Array()
	var d := 0.0
	while d <= track.length:
		var p := track.curve.sample_baked(d)
		raw.append(Vector2(p.x, p.z))
		d += 6.0
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for v in raw:
		mn = mn.min(v)
		mx = mx.max(v)
	var span := mx - mn
	var avail := size - Vector2(_pad, _pad) * 2.0
	_scale = minf(avail.x / maxf(span.x, 1.0), avail.y / maxf(span.y, 1.0))
	_min = mn - (avail / _scale - span) / 2.0
	_poly = PackedVector2Array()
	for v in raw:
		_poly.append(_to_map(v))
	queue_redraw()


func _to_map(v: Vector2) -> Vector2:
	return (v - _min) * _scale + Vector2(_pad, _pad)


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.07, 0.2, 0.55))
	if _poly.size() < 2:
		return
	draw_polyline(_poly, Color(0.02, 0.05, 0.15, 0.9), 9.0, true)
	draw_polyline(_poly, Color(0.95, 0.97, 1.0, 0.95), 5.0, true)
	var start := _poly[0]
	draw_circle(start, 4.0, Color(0.1, 0.1, 0.1))
	for k in karts:
		if not is_instance_valid(k) or k == player:
			continue
		var p := _to_map(Vector2(k.global_position.x, k.global_position.z))
		draw_circle(p, 5.0, Color(0.02, 0.05, 0.15))
		draw_circle(p, 4.0, k.kart_color.lightened(0.15))
	if player and is_instance_valid(player):
		var pp := _to_map(Vector2(player.global_position.x, player.global_position.z))
		var f := player.forward()
		var dir := Vector2(f.x, f.z).normalized()
		var side := Vector2(-dir.y, dir.x)
		var tri := PackedVector2Array([pp + dir * 10.0, pp - dir * 6.0 + side * 6.0, pp - dir * 6.0 - side * 6.0])
		draw_circle(pp, 9.0, Color(1, 1, 1))
		draw_colored_polygon(tri, UITheme.BLUE)
