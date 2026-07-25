extends CharacterBody2D
class_name Minion

## 小兵 AI 状态机 — MARCHING → ATTACKING → RETREATING → DEAD

enum State { MARCHING, ATTACKING, RETREATING, DEAD }
var state: State = State.MARCHING

@export var stats: MinionStats
@export var lane: String = "mid"
@export var team: String = "team_blue"
@export var move_dir: int = 1  # 1=右+上, -1=左+下

@onready var nav: NavigationAgent2D = $NavigationAgent2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var aggro_zone: Area2D = $AggroZone
@onready var attack_zone: Area2D = $AttackZone
@onready var hp_bar: Control = $HealthBar
@onready var atk_timer: Timer = $AttackCooldown
@onready var death_timer: Timer = $DeathTimer
@onready var death_fx: GPUParticles2D = $DeathFX

var current_target: Node2D = null
var hit_flash_timer: float = 0.0
var spawn_position: Vector2
var is_ranged: bool = false

const AGGRO_RANGE: float = 600.0
const DISENGAGE_RANGE: float = 1200.0
const WAYPOINTS: Dictionary = {
	"top_blue": [Vector2(1500,8500), Vector2(5000,7500), Vector2(8500,1500)],
	"mid_blue": [Vector2(1800,8200), Vector2(5000,5000), Vector2(8200,1800)],
	"bot_blue": [Vector2(2200,7800), Vector2(7500,5000), Vector2(7800,2200)],
	"top_red":  [Vector2(8500,1500), Vector2(5000,7500), Vector2(1500,8500)],
	"mid_red":  [Vector2(8200,1800), Vector2(5000,5000), Vector2(1800,8200)],
	"bot_red":  [Vector2(7800,2200), Vector2(7500,5000), Vector2(2200,7800)],
}
var waypoint_index: int = 0
var waypoints: Array = []


func _ready() -> void:
	add_to_group(team); add_to_group("minions")
	spawn_position = global_position
	is_ranged = stats.minion_type == MinionStats.MinionType.RANGED or stats.minion_type == MinionStats.MinionType.CANNON
	setup_waypoints()
	update_color()
	nav.target_desired_distance = 10
	if atk_timer: atk_timer.wait_time = 1.0 / stats.attack_speed

func setup_waypoints() -> void:
	var key := lane + "_" + ("blue" if team == "team_blue" else "red")
	waypoints = WAYPOINTS.get(key, [])
	if waypoints.is_empty(): return
	nav.target_position = waypoints[0]

func update_color() -> void:
	if not sprite: return
	var col := Color.LIGHT_BLUE if team == "team_blue" else Color.LIGHT_CORAL
	match stats.minion_type:
		MinionStats.MinionType.MELEE: col = col.darkened(0.1)
		MinionStats.MinionType.RANGED: col = col.lightened(0.2)
		MinionStats.MinionType.CANNON: col = col.lightened(0.4)
		MinionStats.MinionType.SUPER: col = Color.GOLD
	sprite.modulate = col

func _physics_process(delta: float) -> void:
	if state == State.DEAD: return
	hit_flash_timer = max(0.0, hit_flash_timer - delta)
	if sprite: sprite.modulate.a = 0.5 if hit_flash_timer > 0 and fmod(hit_flash_timer, 0.15) < 0.08 else 1.0
	update_hp_bar()

	match state:
		State.MARCHING: _march(delta)
		State.ATTACKING: _attack(delta)
		State.RETREATING: _retreat(delta)

func _march(_delta: float) -> void:
	var target := _find_target()
	if target:
		current_target = target; state = State.ATTACKING; return
	if waypoints.is_empty():
		velocity = Vector2(move_dir * stats.move_speed, 0)
		move_and_slide(); return
	if waypoint_index >= waypoints.size(): return
	var wp := waypoints[waypoint_index]
	if global_position.distance_to(wp) < 50:
		waypoint_index += 1
		if waypoint_index >= waypoints.size(): return
		wp = waypoints[waypoint_index]
	var dir := (wp - global_position).normalized()
	velocity = dir * stats.move_speed
	move_and_slide()

func _attack(_delta: float) -> void:
	if not _target_valid():
		current_target = null; state = State.RETREATING; return
	var d := global_position.distance_to(current_target.global_position)
	if d > DISENGAGE_RANGE:
		current_target = null; state = State.RETREATING; return
	if d <= stats.attack_range:
		velocity = Vector2.ZERO
		if atk_timer and atk_timer.is_stopped():
			atk_timer.start()
	else:
		var dir := (current_target.global_position - global_position).normalized()
		velocity = dir * stats.move_speed
	move_and_slide()

func _retreat(_delta: float) -> void:
	current_target = null
	var target := _find_target()
	if target:
		current_target = target; state = State.ATTACKING; return
	state = State.MARCHING

func _on_attack_timer_timeout() -> void:
	if state != State.ATTACKING or not _target_valid(): return
	if is_ranged:
		_fire_projectile()
	else:
		_melee_hit()

func _melee_hit() -> void:
	if not current_target: return
	if current_target.has_method("take_damage"):
		current_target.take_damage(stats.attack)
	else:
		var ms := current_target.get_node_or_null("MinionStats") as MinionStats
		if ms: ms.take_damage(stats.attack)

func _fire_projectile() -> void:
	var proj := Projectile.new()
	proj.setup(current_target.global_position, stats.attack, team)
	get_parent().add_child(proj)
	proj.global_position = global_position

func _find_target() -> Node2D:
	var enemies: Array[Node2D] = []
	for body in aggro_zone.get_overlapping_bodies():
		if body == self or body.is_in_group(team): continue
		var ms := body.get_node_or_null("MinionStats") as MinionStats
		if ms and ms.is_dead(): continue
		enemies.append(body)
	if enemies.is_empty(): return null

	# 优先级：最近敌兵 → 英雄 → 塔 → 水晶
	enemies.sort_custom(func(a,b): return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position))
	for e in enemies:
		if e.is_in_group("minions"): return e
	for e in enemies:
		if e.is_in_group("heroes"): return e
	for e in enemies:
		if e.is_in_group("towers"): return e
	for e in enemies:
		if e.is_in_group("crystals"): return e
	return null

func _target_valid() -> bool:
	if not current_target or not is_instance_valid(current_target): return false
	if current_target.has_method("is_dead") and current_target.is_dead(): return false
	var ms := current_target.get_node_or_null("MinionStats") as MinionStats
	if ms and ms.is_dead(): return false
	return true

func take_damage(dmg: int) -> void:
	if state == State.DEAD: return
	if stats: stats.take_damage(dmg)
	hit_flash_timer = 0.1
	if stats and stats.is_dead(): _die()

func _die() -> void:
	state = State.DEAD
	collision_layer = 0; collision_mask = 0
	if death_fx: death_fx.emitting = true
	if death_timer: death_timer.start(0.8)
	_reward_nearby()

func _reward_nearby() -> void:
	for h in get_tree().get_nodes_in_group("heroes"):
		if h.is_in_group(team): continue
		var d := global_position.distance_to(h.global_position)
		if d < 500: _give_reward(h, d < 300)

func _give_reward(hero: Node2D, is_killer: bool) -> void:
	if hero.has_method("add_gold"):
		hero.add_gold(stats.gold_value if is_killer else stats.gold_value / 2)
	if hero.has_method("add_xp"):
		hero.add_xp(stats.xp_value if is_killer else stats.xp_value / 2)

func _on_death_timer_timeout() -> void:
	queue_free()

func update_hp_bar() -> void:
	if not hp_bar or not stats: return
	hp_bar.visible = stats.current_hp < stats.max_hp
	var fill := hp_bar.get_node_or_null("Fill") as ColorRect
	if fill:
		fill.size.x = 40.0 * stats.current_hp / stats.max_hp
		fill.position.x = -20
