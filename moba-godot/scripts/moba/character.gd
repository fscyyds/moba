extends CharacterBody2D
class_name MOBACharacter

## 角色主控制器 — 整合所有子组件
## 逻辑层：移动、死亡隐藏
## 通过 group 区分阵营

# ===== 阵营 =====
@export var team: String = "team_blue"

# ===== 子节点引用 =====
@onready var stats: CharacterStats = $CharacterStats
@onready var level_sys: LevelSystem = $LevelSystem
@onready var basic_attack: BasicAttack = $BasicAttack
@onready var target_detector: AttackTargetDetector = $AttackTargetDetector
@onready var hp_ui: HealthBarUI = $HealthBarUI
@onready var sprite: Sprite2D = $Sprite2D

# ===== 移动输入 =====
var move_input: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group(team)

	# 连接信号
	if stats:
		stats.died.connect(_on_died)
		stats.resurrected.connect(_on_resurrected)

	if target_detector:
		target_detector.enemy_entered_range.connect(_on_enemy_nearby)


func _physics_process(delta: float) -> void:
	if stats and stats.is_dead:
		return

	# 攻击状态机控制移动
	if basic_attack and basic_attack.state != BasicAttack.AttackState.IDLE:
		# 攻击状态中由 BasicAttack 控制移动
		if basic_attack.state == BasicAttack.AttackState.SEEKING_TARGET:
			move_and_slide()
		return

	if move_input.length() > 0.1:
		velocity = move_input * stats.move_speed if stats else move_input * 350.0
		if sprite:
			sprite.flip_h = move_input.x < 0
	else:
		velocity = Vector2.ZERO
	move_and_slide()


## 外部设置移动方向（摇杆调用）
func set_move_direction(dir: Vector2) -> void:
	move_input = dir


## 外部触发普攻（按钮调用）
func do_attack() -> void:
	if basic_attack:
		basic_attack.start_attack()


## 死亡回调
func _on_died() -> void:
	visible = false
	set_physics_process(false)


## 复活回调
func _on_resurrected() -> void:
	visible = true
	set_physics_process(true)


## 附近有敌人（可提示 UI）
func _on_enemy_nearby(_enemy: Node2D) -> void:
	pass


## 获取最近敌人
func get_nearest_enemy() -> Node2D:
	if target_detector:
		return target_detector.get_nearest_enemy()
	return null
