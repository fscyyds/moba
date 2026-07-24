extends StaticBody2D
class_name Tower

## 防御塔 AI — IDLE → TARGETING → WINDUP → FIRE → IDLE

enum State { IDLE, TARGETING, WINDUP, FIRE }
var state: State = State.IDLE

@onready var stats: TowerStats = $TowerStats
@onready var range_area: Area2D = $AttackRangeArea
@onready var warning_line: Line2D = $WarningLine
@onready var shield: Sprite2D = $ShieldSprite
@onready var label: Label = $TowerLabel
@onready var hp_bar: ProgressBar = $HealthBar/ProgressBar
@onready var sprite: Sprite2D = $Sprite2D

var current_target: Node2D = null
var attack_timer: float = 0.0
var windup_timer: float = 0.0
@export var windup_time: float = 0.5 # 前摇0.5秒
var targets_in_range: Array[Node2D] = []


@onready var range_indicator: RangeIndicator = $RangeIndicator

func _ready() -> void:
	add_to_group("towers")
	add_to_group(stats.team)
	if stats:
		stats.hp_changed.connect(_on_hp)
		stats.died.connect(_on_died)
	if range_area:
		range_area.body_entered.connect(_on_body_entered)
		range_area.body_exited.connect(_on_body_exited)
	_update_label()
	if shield:
		shield.visible = stats.is_invincible
	# 初始化范围指示器
	if range_indicator and stats:
		range_indicator.setup(stats.team, stats.attack_range)

func _process(delta: float) -> void:
	if not stats or stats.is_dead: return
	# 无敌护盾显示
	if shield:
		shield.visible = stats.is_invincible
	match state:
		State.IDLE:
			if targets_in_range.size() > 0:
				current_target = _select_target()
				if current_target:
					state = State.WINDUP
					windup_timer = 0.0
		State.WINDUP:
			windup_timer += delta
			_show_warning_line()
			if windup_timer >= windup_time:
				state = State.FIRE
		State.FIRE:
			_fire()
			attack_timer = 1.0 / stats.attack_speed
			state = State.IDLE

	# 冷却计时（IDLE 期间递减）
	if attack_timer > 0:
		attack_timer -= delta

func _on_body_entered(body: Node2D) -> void:
	if body == self: return
	if not _is_enemy(body): return
	if not body in targets_in_range:
		targets_in_range.append(body)

func _on_body_exited(body: Node2D) -> void:
	targets_in_range.erase(body)
	if body == current_target:
		current_target = null
		stats.current_stack_target = null

## 目标优先级（0~4）
func _select_target() -> Node2D:
	if targets_in_range.is_empty(): return null

	# 过滤有效目标
	var valid: Array[Node2D] = []
	for t in targets_in_range:
		if not is_instance_valid(t): continue
		if t is CharacterBody2D:
			var s := t.get_node_or_null("CharacterStats") as CharacterStats
			if s and s.is_dead: continue
			var ms := t.get_node_or_null("MinionStats") as MinionStats
			if ms and ms.is_dead: continue
		valid.append(t)
	if valid.is_empty(): return null

	# 优先级 0：正在攻击我方英雄的敌方小兵
	for v in valid:
		if v.is_in_group("minions"):
			# 简化：小兵在范围内就优先
			return v

	# 优先级 1：最近敌方小兵
	var nearest_creep: Node2D = null; var nd: float = INF
	for v in valid:
		if v.is_in_group("minions"):
			var d := global_position.distance_to(v.global_position)
			if d < nd: nd = d; nearest_creep = v
	if nearest_creep: return nearest_creep

	# 优先级 2：攻击我方英雄的敌方英雄
	for v in valid:
		if v.is_in_group("heroes"):
			var attacker := v.get_node_or_null("BasicAttack") as BasicAttack
			if attacker and attacker.current_target and attacker.current_target.is_in_group(stats.team):
				return v

	# 优先级 3：最近敌方英雄
	var nearest_hero: Node2D = null; var nh: float = INF
	for v in valid:
		if v.is_in_group("heroes"):
			var d := global_position.distance_to(v.global_position)
			if d < nh: nh = d; nearest_hero = v
	return nearest_hero

func _show_warning_line() -> void:
	if not current_target or not is_instance_valid(current_target): return
	warning_line.visible = true
	warning_line.points = PackedVector2Array([Vector2.ZERO, current_target.global_position - global_position])
	warning_line.default_color = Color.RED
	warning_line.width = 3

func _fire() -> void:
	warning_line.visible = false
	if not current_target or not is_instance_valid(current_target):
		return

	var dmg := stats.get_stacked_damage(current_target)
	# 塔的攻击 → 真实伤害（无视防御），直接扣 HP
	if current_target.has_method("take_damage_direct"):
		current_target.take_damage_direct(dmg)
	else:
		var s := current_target.get_node_or_null("CharacterStats") as CharacterStats
		if s:
			s.current_hp = max(s.current_hp - dmg, 0)
			s.hp_changed.emit(s.current_hp, s.max_hp)
			if s.current_hp <= 0:
				s.is_dead = true; s.died.emit()
		var ms := current_target.get_node_or_null("MinionStats") as MinionStats
		if ms:
			ms.current_hp = max(ms.current_hp - dmg, 0)
			ms.hp_changed.emit(ms.current_hp, ms.max_hp)
			if ms.current_hp <= 0:
				ms.is_dead = true; ms.died.emit(ms.gold_value, ms.xp_value)

	# 闪白效果
	if current_target.has_node("Sprite2D"):
		var sp := current_target.get_node("Sprite2D") as Sprite2D
		if sp:
			sp.modulate = Color.WHITE
			var tw := create_tween()
			tw.tween_property(sp, "modulate", Color.WHITE, 0.1)

func _is_enemy(body: Node2D) -> bool:
	return not body.is_in_group(stats.team)

func _on_hp(current: int, maximum: int) -> void:
	if hp_bar:
		hp_bar.max_value = maximum
		hp_bar.value = current

func _on_died() -> void:
	# 隐藏范围指示器
	if range_indicator:
		range_indicator.visible = false
	# 爆炸粒子
	_spawn_death_particles()
	# 给附近英雄发奖励
	_reward_nearby()
	# 通知 TowerManager
	if stats.tower_manager_ref and stats.tower_manager_ref.has_method("on_tower_destroyed"):
		stats.tower_manager_ref.on_tower_destroyed(stats.team, stats.lane, stats.tower_tier)
	# 消失
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.tween_callback(queue_free)

func _spawn_death_particles() -> void:
	var particles := CPUParticles2D.new()
	particles.emitting = true; particles.one_shot = true
	particles.amount = 30; particles.lifetime = 0.6
	particles.explosiveness = 1.0
	particles.texture = preload("res://icon.svg") if ResourceLoader.exists("res://icon.svg") else null
	get_parent().add_child(particles)
	particles.global_position = global_position
	var tw := create_tween()
	tw.tween_callback(particles.queue_free).set_delay(1.0)

func _reward_nearby() -> void:
	var reward_list: Array[Node] = []
	reward_list.assign(get_tree().get_nodes_in_group("team_blue") + get_tree().get_nodes_in_group("team_red"))
	for node in reward_list:
		if node.is_in_group(stats.team): continue
		if node.is_in_group("heroes"):
			if global_position.distance_to(node.global_position) < 2000:
				var ls := node.get_node_or_null("LevelSystem") as LevelSystem
				if ls: ls.add_xp(stats.xp_reward)
				if node.has_method("add_gold"):
					node.add_gold(stats.gold_reward)

func _update_label() -> void:
	match stats.tower_tier:
		TowerStats.Tier.T1: label.text = "T1"
		TowerStats.Tier.T2: label.text = "T2"
		TowerStats.Tier.T3: label.text = "T3"
		TowerStats.Tier.T4: label.text = "水晶"
