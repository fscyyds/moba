extends Node
class_name BuffEffect

## 红蓝Buff效果 — 附加到英雄，70秒持续

@export var duration: float = 70.0
@export var is_red: bool = false
@export var is_blue: bool = false

var hero_ref: CharacterBody2D
var timer: float = 0.0


func apply(h: CharacterBody2D, buff_type: String) -> void:
	hero_ref = h
	match buff_type:
		"red": is_red = true; timer = duration
		"blue": is_blue = true; timer = duration

func _process(delta: float) -> void:
	if not is_red and not is_blue: return
	timer -= delta
	if timer <= 0: is_red = false; is_blue = false

func get_cooldown_reduction() -> float:
	return 0.20 if is_blue else 0.0

func on_hit(target: Node2D) -> void:
	if not is_red: return
	# 灼烧3秒
	for _i in range(3):
		if not is_instance_valid(target): break
		if target.has_method("take_damage"): target.take_damage(10)
		await hero_ref.get_tree().create_timer(1.0).timeout
