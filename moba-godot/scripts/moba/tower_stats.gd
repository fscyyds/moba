extends Node
class_name TowerStats

## 防御塔属性 — 4层塔 + 保护机制

signal hp_changed(current: int, max_hp: int)
signal died()

enum Tier { T1, T2, T3, T4 }

@export var tower_tier: Tier = Tier.T1
@export var team: String = "team_blue"   # "team_blue" / "team_red"
@export var lane: String = "mid"          # "top" / "mid" / "bot"
@export var max_hp: int = 4000
@export var current_hp: int = 4000
@export var attack: int = 200
@export var attack_speed: float = 1.0
@export var attack_range: float = 500.0
@export var gold_reward: int = 150
@export var xp_reward: int = 100

# ===== 保护机制 =====
@export var is_invincible: bool = false             # 未解锁时无敌
@export var damage_reduction: float = 0.0            # 当前减伤率
@export var early_game_protect_duration: float = 240.0 # 4分钟开局保护
@export var early_game_reduction: float = 0.5         # 50%减伤
@export var no_creep_reduction: float = 0.9           # 无兵线90%减伤
@export var stack_damage_bonus: float = 0.2           # 每层+20%
@export var max_damage_stacks: int = 5                # 最多5层

# ===== 攻击递增 =====
var current_stack_target: Node2D = null
var damage_stacks: int = 0

var is_dead: bool = false
var game_time: float = 0.0
var tower_manager_ref: Node = null  # TowerManager 引用


func _ready() -> void:
	_apply_tier_defaults()
	current_hp = max_hp

func _process(delta: float) -> void:
	game_time += delta
	# 开局保护递减
	if game_time < early_game_protect_duration:
		damage_reduction = early_game_reduction
	else:
		damage_reduction = 0.0

func _apply_tier_defaults() -> void:
	match tower_tier:
		Tier.T1:
			max_hp = 4000; attack = 200; attack_speed = 1.0; attack_range = 500; gold_reward = 150; xp_reward = 100
		Tier.T2:
			max_hp = 5500; attack = 260; attack_speed = 1.0; attack_range = 500; gold_reward = 200; xp_reward = 150
		Tier.T3:
			max_hp = 7000; attack = 320; attack_speed = 1.0; attack_range = 550; gold_reward = 250; xp_reward = 200
		Tier.T4:
			max_hp = 10000; attack = 400; attack_speed = 0.8; attack_range = 600; gold_reward = 500; xp_reward = 400

## 伤害计算（处理所有保护机制）
## 返回实际扣除的 HP
func take_damage(raw_damage: int, attacker: Node2D = null) -> int:
	if is_dead: return 0

	# 1. 无敌（未解锁）→ 免疫
	if is_invincible:
		return 0

	# 2. 无兵线保护（英雄攻击时，检查范围内有无友方小兵）
	if attacker and attacker.is_in_group("heroes"):
		if not _has_nearby_allied_minions():
			raw_damage = int(raw_damage * (1.0 - no_creep_reduction))

	# 3. 开局保护
	if damage_reduction > 0:
		raw_damage = int(raw_damage * (1.0 - damage_reduction))

	var actual := max(raw_damage, 1)
	current_hp = max(current_hp - actual, 0)
	hp_changed.emit(current_hp, max_hp)
	if current_hp <= 0:
		is_dead = true
		died.emit()
	return actual

## 检查攻击范围内是否有己方小兵
func _has_nearby_allied_minions() -> bool:
	var parent := get_parent()
	for minion in get_tree().get_nodes_in_group("minions"):
		if minion.is_in_group(team):
			if parent.global_position.distance_to(minion.global_position) < attack_range:
				return true
	return false

## 攻击递增：切换目标时重置层数
func get_stacked_damage(target: Node2D) -> int:
	if target != current_stack_target:
		current_stack_target = target
		damage_stacks = 0
	damage_stacks = min(damage_stacks + 1, max_damage_stacks)
	var multiplier := 1.0 + (damage_stacks - 1) * stack_damage_bonus
	return int(attack * multiplier)

## 解锁此塔（TowerManager 调用）
func unlock() -> void:
	is_invincible = false
