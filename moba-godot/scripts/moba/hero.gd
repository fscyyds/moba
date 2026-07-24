extends CharacterBody2D
class_name Hero

## 角色主控 — 整合摇杆输入、普攻、死亡复活

@export var team: String = "team_blue"

@onready var stats: CharacterStats = $CharacterStats
@onready var level_sys: LevelSystem = $LevelSystem
@onready var basic_attack: BasicAttack = $BasicAttack

var move_input: Vector2 = Vector2.ZERO
var gold: int = 0


func _ready() -> void:
	add_to_group(team)
	if stats:
		stats.died.connect(_on_died)
		stats.respawned.connect(_on_respawned)

func _physics_process(_delta: float) -> void:
	if stats and stats.is_dead: return
	if basic_attack and basic_attack.state != BasicAttack.State.IDLE: return

	if move_input.length() > 0.1:
		velocity = move_input * (stats.move_speed if stats else 350.0)
		var sp := get_node_or_null("Sprite2D") as Sprite2D
		if sp: sp.flip_h = move_input.x < 0
	else:
		velocity = Vector2.ZERO
	move_and_slide()

## 摇杆调用
func set_move_direction(dir: Vector2) -> void:
	move_input = dir

## 攻击键调用
func do_attack() -> void:
	if basic_attack:
		basic_attack.start_attack()

## 加金币
func add_gold(amount: int) -> void:
	gold += amount

func _on_died() -> void:
	visible = false
	move_input = Vector2.ZERO

func _on_respawned() -> void:
	visible = true
