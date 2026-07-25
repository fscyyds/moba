extends Node
class_name TowerStats

## 防御塔属性 — 4层塔 + 攻击系统 + 保护机制

signal hp_changed(current: int, max_hp: int)
signal died()

enum Tier { T1, T2, T3, T4 }

@export var tower_tier: Tier = Tier.T1
@export var team: String = "team_blue"
@export var lane: String = "mid"
@export var max_hp: int = 4000
@export var current_hp: int = 4000
@export var attack: int = 200
@export var attack_speed: float = 1.0
@export var attack_range: float = 500.0
@export var gold_reward: int = 150
@export var xp_reward: int = 100

# ===== 保护机制 =====
@export var is_invincible: bool = false
@export var damage_reduction: float = 0.0
@export var early_game_protect_duration: float = 240.0
@export var early_game_reduction: float = 0.5
@export var no_creep_reduction: float = 0.9
@export var stack_damage_bonus: float = 0.2
@export var max_damage_stacks: int = 5

# ─── 攻击力成长 ───
@export var base_attack: float = 470.0
@export var max_attack: float = 550.0
@export var attack_growth_per_min: float = 5.0
@export var growth_start_sec: float = 0.0
@export var growth_end_sec: float = 960.0

# ─── 攻击间隔 ───
@export var attack_interval: float = 1.0

# ─── 伤害递增倍率 ───
@export var damage_multipliers: Array = [1.0, 1.6, 2.2, 2.8, 3.4, 4.0]

# ─── 塔的防御 ───
@export var armor_with_minions: float = 200.0
@export var armor_no_minions: float = 1200.0
@export var fixed_damage_reduction: float = 0.55
@export var single_hit_cap: float = 1000.0

# ─── 前期保护 ───
@export var early_protection_time: float = 240.0
@export var early_dmg_reduction: float = 0.60
@export var late_dmg_reduction: float = 0.30

# ─── 越塔削弱 ───
@export var dive_debuff_early: float = 0.25
@export var dive_debuff_mid: float = 0.10
@export var dive_debuff_late: float = 0.0

var current_stack_target: Node2D = null
var damage_stacks: int = 0
var is_dead: bool = false
var game_time: float = 0.0
var tower_manager_ref: Node = null


func _ready() -> void:
	_apply_tier_defaults()
	current_hp = max_hp

func _process(delta: float) -> void:
	game_time += delta
	if game_time < early_game_protect_duration:
		damage_reduction = early_game_reduction
	else:
		damage_reduction = 0.0

func _apply_tier_defaults() -> void:
	match tower_tier:
		Tier.T1:
			max_hp = 6000; base_attack = 470; max_attack = 550; attack_range = 830
			attack_interval = 1.0; gold_reward = 150; xp_reward = 100
		Tier.T2:
			max_hp = 6000; base_attack = 470; max_attack = 550; attack_range = 830
			attack_interval = 1.0; gold_reward = 200; xp_reward = 150
		Tier.T3:
			max_hp = 6000; base_attack = 630; max_attack = 730; attack_range = 880
			attack_interval = 1.0; gold_reward = 250; xp_reward = 200
		Tier.T4:
			max_hp = 9000; base_attack = 560; max_attack = 660; attack_range = 1010
			attack_interval = 1.0; gold_reward = 500; xp_reward = 400
			armor_no_minions = 3800
	current_hp = max_hp

func take_damage(raw_damage: int, attacker: Node2D = null) -> int:
	if is_dead: return 0
	var dmg: float = float(raw_damage)
	# 单次上限
	dmg = minf(dmg, single_hit_cap)
	# 固定免伤
	dmg *= (1.0 - fixed_damage_reduction)
	# 前期保护
	if attacker and attacker.is_in_group("heroes"):
		var reduction := _get_early_protection(get_game_time())
		dmg *= (1.0 - reduction)
	# 护甲
	var armor := armor_with_minions if _has_nearby_allied_minions() else armor_no_minions
	dmg *= (1.0 - armor / (armor + 602.0))
	# 无敌
	if is_invincible:
		dmg = 0
	var actual := max(int(dmg), 1)
	current_hp = max(current_hp - actual, 0)
	hp_changed.emit(current_hp, max_hp)
	if current_hp <= 0:
		is_dead = true; died.emit()
	return actual

func _get_early_protection(t: float) -> float:
	if t < 120: return early_dmg_reduction
	elif t < 240: return early_dmg_reduction - (early_dmg_reduction - late_dmg_reduction) * (t - 120) / 120.0
	else: return late_dmg_reduction

func get_game_time() -> float:
	return game_time

func _has_nearby_allied_minions() -> bool:
	var p := get_parent()
	for m in get_tree().get_nodes_in_group("minions"):
		if m.is_in_group(team) and p.global_position.distance_to(m.global_position) < attack_range:
			return true
	return false

func get_stacked_damage(target: Node2D) -> int:
	if target != current_stack_target:
		current_stack_target = target; damage_stacks = 0
	damage_stacks = min(damage_stacks + 1, max_damage_stacks)
	return int(float(attack) * (1.0 + (damage_stacks - 1) * stack_damage_bonus))

func unlock() -> void:
	is_invincible = false

## 获取当前攻击力（随时间成长）
func get_current_attack() -> float:
	var t := get_game_time()
	if t <= growth_start_sec: return base_attack
	var elapsed := t - growth_start_sec
	var duration := growth_end_sec - growth_start_sec
	var ratio := clamp(elapsed / duration, 0.0, 1.0)
	return lerpf(base_attack, max_attack, ratio)

## 获取越塔削弱值
func get_dive_debuff() -> float:
	var t := get_game_time()
	if t < 240: return dive_debuff_early
	elif t < 600: return dive_debuff_mid
	else: return dive_debuff_late
