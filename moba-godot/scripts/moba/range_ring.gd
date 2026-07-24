extends Node2D
class_name RangeRing

## 简单的范围圈 — 塔下的红色圆圈

@export var range_radius: float = 500.0
@export var ring_color: Color = Color(1.0, 0.2, 0.2, 0.3)
@export var border_width: float = 2.0

var hero_ref: CharacterBody2D = null
var time: float = 0.0
var alpha: float = 0.0

func _ready() -> void:
	# 找英雄
	await get_tree().process_frame
	var p := get_parent()
	while p:
		for c in p.get_children():
			if c is CharacterBody2D and c.name.begins_with("Hero"):
				hero_ref = c; break
		if hero_ref: break
		p = p.get_parent()
	if not hero_ref:
		for c in get_tree().root.get_children():
			for cc in c.get_children():
				if cc is CharacterBody2D and cc.name.begins_with("Hero"):
					hero_ref = cc; break

func _process(delta: float) -> void:
	time += delta
	if not hero_ref: return
	var dist := global_position.distance_to(hero_ref.global_position)
	var wr := range_radius * 1.5
	if dist > wr * 2:
		alpha = move_toward(alpha, 0.0, delta * 2)
	elif dist > range_radius:
		alpha = move_toward(alpha, 0.5, delta * 2)
	else:
		alpha = move_toward(alpha, 1.0, delta * 2)
	if alpha > 0.01:
		queue_redraw()

func _draw() -> void:
	if alpha < 0.01: return
	var c := ring_color
	c.a *= alpha
	draw_circle(Vector2.ZERO, range_radius, c)
	var pulse := sin(time * 3) * 0.5 + 0.5
	var bc := Color(ring_color.r, ring_color.g, ring_color.b, c.a * (0.5 + pulse * 0.5))
	draw_arc(Vector2.ZERO, range_radius, 0, TAU, 64, bc, border_width)
