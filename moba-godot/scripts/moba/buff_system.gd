extends Node
class_name BuffSystem

## 红蓝Buff系统 — 附加到英雄身上的效果

@export var buff_duration: float = 70.0

var hero: CharacterBody2D
var is_red_buff: bool = false
var is_blue_buff: bool = false
var timer: float = 0.0

func apply_red_buff(h: CharacterBody2D) -> void:
	hero = h; is_red_buff = true; timer = buff_duration
	# 红Buff效果：普攻附带灼烧（每秒10点伤害，持续3秒）+ 减速20%

func apply_blue_buff(h: CharacterBody2D) -> void:
	hero = h; is_blue_buff = true; timer = buff_duration
	# 蓝Buff效果：每秒回蓝5点 + 技能冷却缩减20%

func _process(delta: float) -> void:
	if not is_red_buff and not is_blue_buff: return
	timer -= delta
	if timer <= 0:
		is_red_buff = false; is_blue_buff = false

func get_cooldown_reduction() -> float:
	return 0.20 if is_blue_buff else 0.0

func on_basic_attack(target: Node2D) -> void:
	if not is_red_buff: return
	if target.has_method("take_damage"):
		for i in range(3):  # 3秒灼烧
			await get_tree().create_timer(1.0).timeout
			target.take_damage(10)
	if target.has_method("apply_slow"):
		target.apply_slow(0.20, 3.0)
