extends Resource
class_name JungleData

## 野怪数据配置 — 所有类型属性 + 成长公式

enum CampType { STONE_BEETLES, WOLVES, BIRDS, LIZARDS, RED_BUFF, BLUE_BUFF, RIVER_CRAB, DRAGON, BARON }

@export var camp_type: CampType = CampType.STONE_BEETLES
@export var max_hp: int = 800
@export var attack: int = 35
@export var attack_speed: float = 1.0
@export var move_speed: float = 150
@export var attack_range: float = 80
@export var gold_value: int = 45
@export var xp_value: int = 60
@export var head_count: int = 2
@export var is_ranged: bool = false
@export var first_spawn: float = 30.0
@export var respawn_interval: float = 70.0

func _init(type: CampType = CampType.STONE_BEETLES, game_time: float = 0.0) -> void:
	camp_type = type
	_apply_base()
	_apply_growth(game_time)

func _apply_base() -> void:
	match camp_type:
		CampType.STONE_BEETLES:
			max_hp = 800; attack = 35; gold_value = 45; xp_value = 60; head_count = 2
		CampType.WOLVES:
			max_hp = 700; attack = 45; gold_value = 45; xp_value = 60; head_count = 2
		CampType.BIRDS:
			max_hp = 500; attack = 30; gold_value = 50; xp_value = 65; head_count = 3; is_ranged = true; attack_range = 300
		CampType.LIZARDS:
			max_hp = 600; attack = 40; gold_value = 40; xp_value = 55; head_count = 2
		CampType.RED_BUFF:
			max_hp = 2500; attack = 80; gold_value = 120; xp_value = 150; head_count = 1; respawn_interval = 90
		CampType.BLUE_BUFF:
			max_hp = 2500; attack = 60; gold_value = 120; xp_value = 150; head_count = 1; respawn_interval = 90
		CampType.RIVER_CRAB:
			max_hp = 1500; attack = 0; gold_value = 70; xp_value = 80; head_count = 1; respawn_interval = 120; first_spawn = 60
		CampType.DRAGON:
			max_hp = 8000; attack = 150; gold_value = 100; xp_value = 150; head_count = 1; respawn_interval = 120; first_spawn = 120
		CampType.BARON:
			max_hp = 12000; attack = 200; gold_value = 200; xp_value = 250; head_count = 1; respawn_interval = 180; first_spawn = 480

## 每2分钟全属性+10%
func _apply_growth(game_time: float) -> void:
	var mul := 1.0 + floor(game_time / 120.0) * 0.10
	max_hp = int(max_hp * mul)
	attack = int(attack * mul)
	gold_value = int(gold_value * mul)
	xp_value = int(xp_value * mul)
