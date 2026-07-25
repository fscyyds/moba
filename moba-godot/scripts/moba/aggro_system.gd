extends Node
class_name AggroSystem

## 通用仇恨系统 — 挂载到任何野怪节点
## 核心：严格脱战围栏 + 无敌返回 + 仇恨衰减

signal aggro_started(target: Node2D)
signal aggro_lost()
signal retreat_started()
signal retreat_ended()

@export var aggro_range: float = 500.0        # 仇恨触发范围
@export var disengage_range: float = 700.0     # 脱战距离
@export var max_leash_distance: float = 500.0  # 最大追击距离（围栏半径）
@export var retreat_speed: float = 350.0       # 返回速度
@export var disengage_time: float = 3.0        # 连续打不到目标→脱战
@export var aggro_check_interval: float = 0.2  # 脱战检查间隔

var spawn_position: Vector2 = Vector2.ZERO     # 出生点
var current_target: Node2D = null
var is_retreating: bool = false
var is_invulnerable: bool = false
var threat_level: float = 0.0                  # 仇恨值
var hit_timer: float = 0.0                     # 未命中计时
var check_timer: float = 0.0

var monster_ref: CharacterBody2D               # 野怪本体引用


func setup(monster: CharacterBody2D, spawn_pos: Vector2) -> void:
	monster_ref = monster
	spawn_position = spawn_pos
	check_timer = aggro_check_interval

func _process(delta: float) -> void:
	if not monster_ref: return

	# 围栏硬限制：绝对不超出出生点+leash范围
	var offset := monster_ref.global_position - spawn_position
	if offset.length() > max_leash_distance and not is_retreating:
		_force_retreat()
	elif offset.length() > max_leash_distance + 50 and is_retreating:
		# 硬clamp
		monster_ref.global_position = spawn_position + offset.normalized() * max_leash_distance

	# 返回中
	if is_retreating:
		_retreat_move(delta)
		return

	# 脱战检查（每0.2秒）
	check_timer -= delta
	if check_timer <= 0:
		check_timer = aggro_check_interval
		_check_disengage()

	# 仇恨衰减
	if current_target:
		hit_timer += delta
		if hit_timer >= disengage_time:
			_force_retreat()
		threat_level = max(0.0, threat_level - 2.0 * delta)
		if threat_level <= 0:
			_force_retreat()

func _check_disengage() -> void:
	if not current_target: return
	if not is_instance_valid(current_target):
		_force_retreat(); return

	# 目标超脱战距离
	var d := monster_ref.global_position.distance_to(current_target.global_position)
	if d > disengage_range:
		_force_retreat(); return

	# 目标死亡
	if current_target.has_method("is_dead") and current_target.is_dead():
		_force_retreat(); return

	# 自身超围栏
	var off := monster_ref.global_position.distance_to(spawn_position)
	if off > max_leash_distance:
		_force_retreat(); return

func _force_retreat() -> void:
	if is_retreating: return
	is_retreating = true
	is_invulnerable = true
	current_target = null
	threat_level = 0.0
	hit_timer = 0.0
	# 关闭碰撞
	if monster_ref is CharacterBody2D:
		monster_ref.collision_layer = 0
		monster_ref.collision_mask = 0
	retreat_started.emit()
	aggro_lost.emit()

func _retreat_move(delta: float) -> void:
	var to_home := spawn_position - monster_ref.global_position
	if to_home.length() < 20:
		# 到达，满血恢复
		monster_ref.global_position = spawn_position
		if monster_ref.has_method("reset_hp"):
			monster_ref.reset_hp()
		is_retreating = false
		is_invulnerable = false
		# 恢复碰撞
		if monster_ref is CharacterBody2D:
			monster_ref.collision_layer = 32
			monster_ref.collision_mask = 1
		retreat_ended.emit()
		return
	monster_ref.global_position += to_home.normalized() * retreat_speed * delta

func on_hit_target() -> void:
	hit_timer = 0.0
	threat_level += 1.0

func acquire_target(target: Node2D) -> void:
	if is_retreating or is_invulnerable: return
	current_target = target
	threat_level = 10.0
	hit_timer = 0.0
	aggro_started.emit(target)

func try_acquire(heroes: Array) -> Node2D:
	if is_retreating or is_invulnerable: return null
	var best: Node2D = null; var bd := aggro_range
	for h in heroes:
		if not is_instance_valid(h): continue
		if h.has_method("is_dead") and h.is_dead(): continue
		var d := monster_ref.global_position.distance_to(h.global_position)
		if d < bd: bd = d; best = h
	if best: acquire_target(best)
	return best
