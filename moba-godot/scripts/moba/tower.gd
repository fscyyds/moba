extends StaticBody2D
class_name Tower

## 防御塔 — 攻击范围700，伤害120，优先打小兵

@export var team: String = "team_blue"
@export var max_hp: int = 5000
var current_hp: int = 5000
@export var attack: int = 120
@export var attack_range: float = 700.0
@export var attack_speed: float = 1.0

@onready var range_area: Area2D = $AttackRange
@onready var atk_timer: Timer = $AttackTimer
@onready var hp_bar: Control = $HealthBar

var current_target: Node2D = null
var is_dead: bool = false


func _ready() -> void:
	add_to_group(team); add_to_group("towers")
	current_hp = max_hp
	atk_timer.wait_time = 1.0 / attack_speed
	atk_timer.timeout.connect(_on_attack)

func _on_attack() -> void:
	if is_dead: return
	current_target = _select_target()
	if current_target:
		if current_target.has_method("take_damage"):
			current_target.take_damage(attack)

func _select_target() -> Node2D:
	var bodies := range_area.get_overlapping_bodies()
	var enemies: Array[Node2D] = []
	for b in bodies:
		if b.is_in_group(team) or b == self: continue
		enemies.append(b)
	if enemies.is_empty(): return null
	# 优先级：打我方英雄的兵 > 兵 > 英雄
	for e in enemies:
		if e.is_in_group("minions"): return e
	for e in enemies:
		if e.is_in_group("heroes"): return e
	return enemies[0]

func take_damage(dmg: int) -> void:
	if is_dead: return
	current_hp = max(current_hp - dmg, 0)
	update_hp()
	if current_hp <= 0: _die()

func update_hp() -> void:
	if hp_bar:
		var fill := hp_bar.get_node_or_null("Fill") as ColorRect
		if fill: fill.size.x = 50.0 * current_hp / max_hp

func _die() -> void:
	is_dead = true
	queue_free()
