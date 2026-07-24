extends CharacterBody2D
class_name Minion

## 小兵 AI — WALKING → CHASING → ATTACKING → DEAD

enum State { WALKING, CHASING, ATTACKING, DEAD }
var state: State = State.WALKING

@onready var stats: MinionStats = $MinionStats
@onready var sprite: Sprite2D = $Sprite2D
@onready var hp_bar: ProgressBar = $HealthBar/ProgressBar

@export var lane_path: Path2D           # 所属兵线
@export var path_ratio: float = 0.0      # 在路径上的位置
@export var move_speed: float = 120.0
@export var move_direction: int = 1      # 1=蓝方(ratio递增), -1=红方(ratio递减)
@export var aggro_range: float = 300.0
@export var disengage_range: float = 400.0

var current_target: Node2D = null
var attack_timer: float = 0.0
var random_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	random_offset = Vector2(randf_range(-20, 20), randf_range(-20, 20))
	if stats:
		stats.died.connect(_on_death)
		stats.hp_changed.connect(_on_hp)

func _physics_process(delta: float) -> void:
	if state == State.DEAD: return

	match state:
		State.WALKING:
			_walk_along_path(delta)
			var enemy := _find_enemy()
			if enemy and global_position.distance_to(enemy.global_position) < aggro_range:
				current_target = enemy
				state = State.CHASING
		State.CHASING:
			if not current_target or not _target_valid():
				current_target = null
				state = State.WALKING
				return
			var d := global_position.distance_to(current_target.global_position)
			if d > disengage_range:
				current_target = null
				state = State.WALKING
			elif d <= (stats.attack_range if stats else 60):
				state = State.ATTACKING
			else:
				var dir := (current_target.global_position - global_position).normalized()
				velocity = dir * move_speed
				move_and_slide()
		State.ATTACKING:
			if not current_target or not _target_valid():
				current_target = null
				state = State.WALKING
				return
			var d := global_position.distance_to(current_target.global_position)
			if d > (stats.attack_range if stats else 60) * 1.3:
				state = State.CHASING
				return
			attack_timer += delta
			if attack_timer >= (1.0 / stats.attack_speed if stats else 1.0):
				attack_timer = 0.0
				if current_target and _target_valid():
					var es := current_target.get_node_or_null("CharacterStats") as CharacterStats
					if es: es.take_damage(stats.attack if stats else 40)
					else: _try_damage_minion(current_target)

	move_and_slide()

func _walk_along_path(delta: float) -> void:
	if not lane_path: return
	path_ratio += move_direction * (move_speed / lane_path.curve.get_baked_length()) * delta
	path_ratio = clamp(path_ratio, 0.0, 1.0)
	var pos := lane_path.curve.sample_baked(path_ratio * lane_path.curve.get_baked_length())
	global_position = pos + random_offset

func _find_enemy() -> Node2D:
	var my_team := ""
	for g in get_groups():
		if g.begins_with("team_"): my_team = g; break

	# 优先级 0：最近敌方小兵
	var best_creep: Node2D = null; var bd: float = INF
	for node in get_tree().get_nodes_in_group("minions"):
		if node.is_in_group(my_team): continue
		var d := global_position.distance_to(node.global_position)
		if d < aggro_range and d < bd:
			bd = d; best_creep = node
	if best_creep: return best_creep

	# 优先级 1：敌方英雄
	for node in get_tree().get_nodes_in_group("heroes"):
		if node.is_in_group(my_team): continue
		var s := node.get_node_or_null("CharacterStats") as CharacterStats
		if s and s.is_dead: continue
		var d := global_position.distance_to(node.global_position)
		if d < aggro_range: return node

	# 优先级 2：敌方防御塔
	for node in get_tree().get_nodes_in_group("towers"):
		if node.is_in_group(my_team): continue
		var ts := node.get_node_or_null("TowerStats") as TowerStats
		if ts and ts.is_dead: continue
		var rng := stats.attack_range if stats else 60.0
		var d := global_position.distance_to(node.global_position)
		if d < rng + 50: return node
	return null

func _target_valid() -> bool:
	if not current_target or not is_instance_valid(current_target): return false
	if current_target is CharacterBody2D:
		var es := current_target.get_node_or_null("CharacterStats") as CharacterStats
		if es and es.is_dead: return false
		var ms := current_target.get_node_or_null("MinionStats") as MinionStats
		if ms and ms.is_dead: return false
	return true

func _try_damage_minion(target: Node2D) -> void:
	var ms := target.get_node_or_null("MinionStats") as MinionStats
	if ms: ms.take_damage(stats.attack if stats else 40)

func _on_death(gold: int, xp: int) -> void:
	state = State.DEAD
	# 缩小消失动画
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ZERO, 0.3)
	tw.tween_callback(queue_free)
	# 给附近英雄发奖励
	var reward_list: Array[Node] = []
	reward_list.assign(get_tree().get_nodes_in_group("team_blue") + get_tree().get_nodes_in_group("team_red"))
	for node in reward_list:
		if node is CharacterBody2D and global_position.distance_to(node.global_position) < 800:
			# 发放金币和经验
			if node.has_method("add_gold"):
				node.add_gold(gold)
			var ls := node.get_node_or_null("LevelSystem") as LevelSystem
			if ls: ls.add_xp(xp)

func _on_hp(current: int, maximum: int) -> void:
	if hp_bar:
		hp_bar.max_value = maximum
		hp_bar.value = current
