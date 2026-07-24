extends Node
class_name MinionStats

## 小兵属性 — 3种类型，支持随时间成长

signal died(gold: int, xp: int)
signal hp_changed(current: int, maximum: int)

enum MinionType { MELEE, RANGED, CANNON }

@export var minion_type: MinionType = MinionType.MELEE
@export var max_hp: int = 500
@export var current_hp: int = 500
@export var attack: int = 40
@export var attack_speed: float = 1.0
@export var attack_range: float = 60
@export var gold_value: int = 30
@export var xp_value: int = 50
@export var growth_rate: float = 0.1  # 每3分钟 +10%

var is_dead: bool = false
var _game_time_minutes: float = 0.0

func _ready() -> void:
	_apply_type_defaults()
	current_hp = max_hp

func _apply_type_defaults() -> void:
	match minion_type:
		MinionType.MELEE:
			max_hp = 500; attack = 40; attack_speed = 1.0; attack_range = 60; gold_value = 30; xp_value = 50
		MinionType.RANGED:
			max_hp = 300; attack = 55; attack_speed = 0.8; attack_range = 250; gold_value = 35; xp_value = 55
		MinionType.CANNON:
			max_hp = 1200; attack = 120; attack_speed = 0.5; attack_range = 200; gold_value = 80; xp_value = 100

## 随时间成长：每3分钟全属性+10%
func apply_growth(minutes: float) -> void:
	_game_time_minutes = minutes
	var mul: float = 1.0 + floor(minutes / 3.0) * growth_rate
	max_hp = int(max_hp * mul); current_hp = max_hp
	attack = int(attack * mul)

func take_damage(dmg: int) -> void:
	if is_dead: return
	var actual := int(ceil(float(dmg) * (1.0 - 100.0 / 702.0)))  # 防御100
	actual = max(actual, 1)
	current_hp = max(current_hp - actual, 0)
	hp_changed.emit(current_hp, max_hp)
	if current_hp <= 0:
		is_dead = true
		died.emit(gold_value, xp_value)
