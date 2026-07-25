extends Resource
class_name MinionStats

## 小兵属性数据 — 4种类型 + 波次成长

enum MinionType { MELEE, RANGED, CANNON, SUPER }

@export var minion_type: MinionType = MinionType.MELEE
@export var max_hp: int = 500
@export var current_hp: int = 500
@export var attack: int = 40
@export var attack_speed: float = 1.0
@export var move_speed: float = 200.0
@export var attack_range: float = 80.0
@export var gold_value: int = 20
@export var xp_value: int = 30

func _init(t: MinionType = MinionType.MELEE, wave: int = 1) -> void:
	minion_type = t
	_apply_base()
	_apply_growth(wave)
	current_hp = max_hp

func _apply_base() -> void:
	match minion_type:
		MinionType.MELEE:
			max_hp = 500; attack = 40; attack_speed = 1.0; move_speed = 200
			attack_range = 80; gold_value = 20; xp_value = 30
		MinionType.RANGED:
			max_hp = 300; attack = 50; attack_speed = 0.8; move_speed = 200
			attack_range = 400; gold_value = 25; xp_value = 35
		MinionType.CANNON:
			max_hp = 1200; attack = 80; attack_speed = 0.5; move_speed = 180
			attack_range = 500; gold_value = 60; xp_value = 80
		MinionType.SUPER:
			max_hp = 2000; attack = 100; attack_speed = 1.0; move_speed = 220
			attack_range = 100; gold_value = 40; xp_value = 50

## 每波属性+8%
func _apply_growth(wave: int) -> void:
	var mul := 1.0 + (wave - 1) * 0.08
	max_hp = int(max_hp * mul)
	attack = int(attack * mul)

## 受伤
func take_damage(dmg: int) -> int:
	var actual := max(dmg, 1)
	current_hp = max(current_hp - actual, 0)
	return actual

func is_dead() -> bool:
	return current_hp <= 0
