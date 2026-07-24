extends Node
class_name CharacterStats

## 属性系统 — 逻辑层（纯数据）
## 管理 HP/攻击/防御/攻速，通过 signal 通知 UI 层

signal hp_changed(current_hp: int, max_hp: int)
signal died()
signal respawned()

@export var max_hp: int = 3000
@export var current_hp: int = 3000
@export var attack: int = 170
@export var defense: int = 100
@export var attack_speed: float = 1.0
@export var attack_range: float = 120.0
@export var move_speed: float = 350.0
@export var respawn_time: float = 2.0

var is_dead: bool = false
var respawn_timer: float = 0.0

func _ready() -> void:
	current_hp = max_hp

func _process(delta: float) -> void:
	if is_dead:
		respawn_timer += delta
		if respawn_timer >= respawn_time:
			_resurrect()

## 伤害公式：实际伤害 = 攻击 × (1 - 防御/(防御+602))
func take_damage(raw_damage: int) -> int:
	if is_dead:
		return 0
	var reduction := float(defense) / (defense + 602.0)
	var actual: int = max(int(ceil(float(raw_damage) * (1.0 - reduction))), 1)
	current_hp = max(current_hp - actual, 0)
	hp_changed.emit(current_hp, max_hp)
	if current_hp <= 0:
		_die()
	return actual

func heal(amount: int) -> void:
	if is_dead: return
	current_hp = min(current_hp + amount, max_hp)
	hp_changed.emit(current_hp, max_hp)

func _die() -> void:
	is_dead = true
	respawn_timer = 0.0
	died.emit()

func _resurrect() -> void:
	is_dead = false
	current_hp = max_hp
	respawn_timer = 0.0
	respawned.emit()
	hp_changed.emit(current_hp, max_hp)

## 等级系统调用：升级时更新属性并回满血
func update_stats(hp: int, atk: int, def: int, aspd: float) -> void:
	max_hp = hp
	current_hp = hp
	attack = atk
	defense = def
	attack_speed = aspd
	hp_changed.emit(current_hp, max_hp)
