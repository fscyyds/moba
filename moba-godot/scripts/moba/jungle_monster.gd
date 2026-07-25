extends CharacterBody2D
class_name JungleMonster

## 野怪 AI — IDLE → PATROL → CHASE → ATTACK → RETREAT → DEAD

enum State { IDLE, PATROL, CHASE, ATTACK, RETREAT, DEAD }
var state: State = State.IDLE

@export var data: JungleData
var current_hp: int = 800
var spawn_pos: Vector2
var is_dead: bool = false
var is_returning: bool = false  # 返回途中无敌

@onready var nav: NavigationAgent2D = $NavigationAgent2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var atk_timer: Timer = $AttackCooldown
@onready var hp_bar: Control = $HealthBar
@onready var aggro_zone: Area2D = $AggroZone

var current_target: Node2D = null
var patrol_timer: float = 0.0
var patrol_dir: Vector2 = Vector2.RIGHT
var hit_flash: float = 0.0

const LEASH_RANGE: float = 1500.0
const AGRO_RANGE: float = 800.0
const PATROL_RANGE: float = 100.0


func _ready() -> void:
	add_to_group("monsters")
	spawn_pos = global_position
	if data: current_hp = data.max_hp
	atk_timer.wait_time = 1.0 / (data.attack_speed if data else 1.0)
	atk_timer.timeout.connect(_on_attack_tick)
	state = State.IDLE

func _physics_process(delta: float) -> void:
	if state == State.DEAD: return
	hit_flash = max(0.0, hit_flash - delta)
	if sprite: sprite.modulate = Color.RED if hit_flash > 0 else Color.WHITE
	_update_hp_bar()

	match state:
		State.IDLE: _idle(delta)
		State.PATROL: _patrol(delta)
		State.CHASE: _chase()
		State.ATTACK: _attack()
		State.RETREAT: _retreat()

func _idle(_delta: float) -> void:
	patrol_timer = 2.0
	state = State.PATROL

func _patrol(delta: float) -> void:
	patrol_timer -= delta
	if patrol_timer <= 0:
		patrol_dir = Vector2.RIGHT.rotated(randf() * TAU)
		patrol_timer = 2.0 + randf() * 3.0
	var d := global_position.distance_to(spawn_pos)
	if d > PATROL_RANGE * 0.8:
		patrol_dir = (spawn_pos - global_position).normalized()
	velocity = patrol_dir * (data.move_speed if data else 150) * 0.3
	move_and_slide()
	# Check aggro
	if _find_attacker():
		state = State.CHASE

func _chase() -> void:
	current_target = _find_attacker()
	if not current_target:
		state = State.IDLE; return
	var d := global_position.distance_to(current_target.global_position)
	if d > LEASH_RANGE:
		current_target = null; state = State.RETREAT; return
	var rng := data.attack_range if data else 80.0
	if d <= rng:
		state = State.ATTACK
	else:
		var dir := (current_target.global_position - global_position).normalized()
		velocity = dir * (data.move_speed if data else 150)
		move_and_slide()

func _attack() -> void:
	if not current_target or _is_target_dead():
		state = State.CHASE; return
	var d := global_position.distance_to(current_target.global_position)
	var rng := data.attack_range if data else 80.0
	if d > rng * 1.3:
		state = State.CHASE; return
	if d > LEASH_RANGE:
		state = State.RETREAT; return
	velocity = Vector2.ZERO

func _retreat() -> void:
	is_returning = true
	var d := global_position.distance_to(spawn_pos)
	if d < 20:
		current_hp = data.max_hp if data else 800
		is_returning = false
		state = State.IDLE
		return
	var dir := (spawn_pos - global_position).normalized()
	velocity = dir * (data.move_speed if data else 150) * 1.5
	move_and_slide()

func _find_attacker() -> Node2D:
	for body in aggro_zone.get_overlapping_bodies():
		if body.is_in_group("heroes") and not _is_hero_dead(body):
			return body
	return null

func _is_hero_dead(h: Node2D) -> bool:
	if h.has_method("is_dead"): return h.is_dead()
	return false

func _is_target_dead() -> bool:
	if not current_target or not is_instance_valid(current_target): return true
	if current_target.has_method("is_dead"): return current_target.is_dead()
	return false

func _on_attack_tick() -> void:
	if state != State.ATTACK or not current_target: return
	var dmg := data.attack if data else 35
	if current_target.has_method("take_damage"):
		current_target.take_damage(dmg)

func take_damage(dmg: int) -> void:
	if state == State.DEAD or is_returning: return
	current_hp = max(current_hp - dmg, 0)
	hit_flash = 0.1
	if current_target == null: state = State.CHASE
	if current_hp <= 0: _die()

func _die() -> void:
	state = State.DEAD
	collision_layer = 0; collision_mask = 0
	visible = false
	_give_reward()
	await get_tree().create_timer(70.0).timeout
	_respawn()

func _respawn() -> void:
	state = State.IDLE; current_hp = data.max_hp if data else 800
	is_dead = false; visible = true
	collision_layer = 64; collision_mask = 1
	global_position = spawn_pos

func _give_reward() -> void:
	for h in get_tree().get_nodes_in_group("heroes"):
		var d := global_position.distance_to(h.global_position)
		if d < 1000 and h.has_method("add_gold"):
			h.add_gold(data.gold_value if data else 45)
		if d < 1000 and h.has_method("add_xp"):
			h.add_xp(data.xp_value if data else 60)

func _update_hp_bar() -> void:
	if not hp_bar or not data: return
	hp_bar.visible = current_hp < data.max_hp
	var fill := hp_bar.get_node_or_null("Fill") as ColorRect
	if fill: fill.size.x = 36.0 * current_hp / max(data.max_hp, 1)
