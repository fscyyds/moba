extends Node
class_name LevelSystem

## 等级系统 — 经验表 100 + (Lv-1)×80，升级回满血

signal level_up(new_level: int)
signal xp_changed(current_xp: int, xp_to_next: int)

@export var level: int = 1
@export var max_level: int = 15
@export var current_xp: int = 0

@export var xp_per_creep: int = 50
@export var xp_per_hero: int = 200
@export var xp_per_monster: int = 80

@export var hp_per_level: int = 200
@export var atk_per_level: int = 15
@export var def_per_level: int = 10
@export var aspd_per_level: float = 0.02

@export var skill_q_unlock: int = 1
@export var skill_w_unlock: int = 2
@export var skill_r_unlock: int = 4

var stats: CharacterStats


func _ready() -> void:
	for child in get_parent().get_children():
		if child is CharacterStats:
			stats = child
			break

func add_xp(amount: int) -> void:
	if level >= max_level:
		return
	current_xp += amount
	xp_changed.emit(current_xp, _xp_to_next())
	while current_xp >= _xp_to_next() and level < max_level:
		current_xp -= _xp_to_next()
		_level_up()

## 经验表：100 + (level-1)×80
func _xp_to_next() -> int:
	return 100 + (level - 1) * 80

func _level_up() -> void:
	level += 1
	if stats:
		var hp := 3000 + (level - 1) * hp_per_level
		var atk := 170 + (level - 1) * atk_per_level
		var def := 100 + (level - 1) * def_per_level
		var aspd := 1.0 + (level - 1) * aspd_per_level
		stats.update_stats(hp, atk, def, aspd)
	# 升级飘字在 HealthBarUI 里处理
	level_up.emit(level)
	xp_changed.emit(current_xp, _xp_to_next())

func is_skill_unlocked(skill: String) -> bool:
	match skill:
		"q": return level >= skill_q_unlock
		"w": return level >= skill_w_unlock
		"r": return level >= skill_r_unlock
	return false
