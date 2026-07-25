extends Node
class_name BossSkill

## Boss技能系统 — 预警圈 + AOE + 击飞

@export var warning_time: float = 0.5
@export var warning_color: Color = Color(1.0, 0.2, 0.2, 0.4)

var boss_ref: Node2D

func setup(boss: Node2D) -> void:
	boss_ref = boss

func cast_ground_slam(radius: float, damage: int) -> void:
	_draw_warning_circle(radius)
	await get_tree().create_timer(warning_time).timeout
	for h in boss_ref.get_tree().get_nodes_in_group("heroes"):
		if boss_ref.global_position.distance_to(h.global_position) < radius:
			if h.has_method("take_damage"): h.take_damage(damage)

func cast_cone(direction: Vector2, angle: float, length: float, damage: int) -> void:
	# 扇形AOE
	for h in boss_ref.get_tree().get_nodes_in_group("heroes"):
		var to_h := h.global_position - boss_ref.global_position
		if to_h.length() > length: continue
		if direction.angle_to(to_h) < angle * 0.5:
			if h.has_method("take_damage"): h.take_damage(damage)

func _draw_warning_circle(radius: float) -> void:
	var indicator := ColorRect.new()
	indicator.color = warning_color
	indicator.size = Vector2(radius * 2, radius * 2)
	indicator.position = boss_ref.global_position - Vector2(radius, radius)
	boss_ref.get_parent().add_child(indicator)
	var tw := boss_ref.create_tween()
	tw.tween_property(indicator, "color:a", 0.0, warning_time)
	tw.tween_callback(indicator.queue_free)
