extends Node
class_name BasicAttack

## 普攻状态机 — IDLE → MOVING → WINDUP → BACKSWING → IDLE

signal attack_started(target: Node2D)
signal attack_hit(target: Node2D, damage: int)
signal attack_finished()

@export var is_ranged: bool = false
@export var windup_time: float = 0.3
@export var backswing_time: float = 0.2
@export var melee_range: float = 80.0
@export var ranged_range: float = 350.0
@export var projectile_speed: float = 300.0

enum State { IDLE, MOVING_TO_TARGET, WINDUP, BACKSWING }
var state: State = State.IDLE

var stats: CharacterStats
var character: CharacterBody2D
var current_target: Node2D = null
var attack_timer: float = 0.0
var cooldown: float = 0.0

@export var projectile_scene: PackedScene


func _ready() -> void:
	character = get_parent() as CharacterBody2D
	for child in get_parent().get_children():
		if child is CharacterStats:
			stats = child
			break

func _process(delta: float) -> void:
	if not stats or stats.is_dead: return
	cooldown = max(0.0, cooldown - delta)
	match state:
		State.IDLE: pass
		State.MOVING_TO_TARGET:
			if current_target and _target_alive():
				_move_toward(delta)
				if _in_range(): _begin_windup()
			else:
				state = State.IDLE
		State.WINDUP:
			attack_timer += delta
			if attack_timer >= windup_time:
				_hit()
				state = State.BACKSWING
		State.BACKSWING:
			attack_timer += delta
			if attack_timer >= windup_time + backswing_time:
				_finish()

## 外部调用：开始攻击
func start_attack(target_override: Node2D = null) -> bool:
	if state != State.IDLE or cooldown > 0 or not stats or stats.is_dead:
		return false
	current_target = target_override if target_override else _nearest_enemy()
	if not current_target:
		# 空挥：原地播放攻击动画
		_begin_windup()
		return true
	state = State.MOVING_TO_TARGET
	return true

func _nearest_enemy() -> Node2D:
	var my_team := ""
	for g in character.get_groups():
		if g.begins_with("team_"): my_team = g; break
	var best: Node2D = null; var best_d := INF
	var sr := stats.attack_range + 500

	# 聚合所有可攻击目标
	var all: Array[Node] = []
	all.assign(get_tree().get_nodes_in_group("heroes"))
	all.append_array(get_tree().get_nodes_in_group("minions"))
	all.append_array(get_tree().get_nodes_in_group("towers"))

	for node in all:
		if node == character or node.is_in_group(my_team): continue
		# 跳过已死亡
		var s := node.get_node_or_null("CharacterStats") as CharacterStats
		if s and s.is_dead: continue
		var ms := node.get_node_or_null("MinionStats") as MinionStats
		if ms and ms.is_dead: continue
		var ts := node.get_node_or_null("TowerStats") as TowerStats
		if ts and ts.is_dead: continue
		var d := character.global_position.distance_to(node.global_position)
		if d < sr and d < best_d:
			best_d = d; best = node
	return best

func _target_alive() -> bool:
	if not is_instance_valid(current_target): return false
	var es := current_target.get_node_or_null("CharacterStats") as CharacterStats
	return es and not es.is_dead

func _in_range() -> bool:
	var rng := ranged_range if is_ranged else melee_range
	return character.global_position.distance_to(current_target.global_position) <= rng

func _move_toward(delta: float) -> void:
	var dir := current_target.global_position - character.global_position
	if dir.length() > 5:
		character.velocity = dir.normalized() * stats.move_speed
		_face_target(dir.x)
	else:
		character.velocity = Vector2.ZERO

func _face_target(dir_x: float) -> void:
	var sp := character.get_node_or_null("Sprite2D") as Sprite2D
	if sp: sp.flip_h = dir_x < 0

func _begin_windup() -> void:
	character.velocity = Vector2.ZERO
	attack_timer = 0.0
	state = State.WINDUP
	attack_started.emit(current_target)

func _hit() -> void:
	if current_target and _target_alive():
		if is_ranged:
			_fire_projectile()
		else:
			var es := current_target.get_node_or_null("CharacterStats") as CharacterStats
			if es:
				var dmg := es.take_damage(stats.attack)
				attack_hit.emit(current_target, dmg)
				if es.is_dead:
					_grant_kill_xp(current_target)
	elif not current_target:
		# 空挥完成
		pass

func _fire_projectile() -> void:
	if not projectile_scene or not current_target: return
	var proj := projectile_scene.instantiate()
	get_parent().get_parent().add_child(proj)
	proj.global_position = character.global_position
	if proj.has_method("setup"):
		proj.setup(current_target, stats.attack, projectile_speed)
	if proj.has_signal("hit_target"):
		proj.hit_target.connect(_on_proj_hit)

func _on_proj_hit(target: Node2D, damage: int) -> void:
	var es := target.get_node_or_null("CharacterStats") as CharacterStats
	if es:
		var dmg := es.take_damage(damage)
		attack_hit.emit(target, dmg)
		if es.is_dead:
			_grant_kill_xp(target)

func _grant_kill_xp(target: Node2D) -> void:
	var ls := _get_level_sys()
	if not ls: return
	if target.is_in_group("team_blue") or target.is_in_group("team_red"):
		ls.add_xp(ls.xp_per_hero)
	else:
		ls.add_xp(ls.xp_per_creep)

func _finish() -> void:
	attack_timer = 0.0
	current_target = null
	cooldown = 1.0 / stats.attack_speed if stats else 1.0
	state = State.IDLE
	attack_finished.emit()

func _get_level_sys() -> LevelSystem:
	for child in get_parent().get_children():
		if child is LevelSystem: return child
	return null
