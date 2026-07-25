extends CharacterBody2D
class_name BossMonster

## 暴君/主宰 — 继承 AggroSystem，加技能+进化

@export var is_dragon: bool = true       # true=暴君, false=主宰
@export var max_hp: int = 8000
@export var attack: int = 150
@export var aggro_range: float = 800.0
@export var disengage_range: float = 1200.0
@export var max_leash: float = 1000.0
@export var retreat_spd: float = 400.0

var current_hp: int = 8000
var is_dead: bool = false
var is_berserk: bool = false
var berserk_timer: float = 0.0
var atk_cooldown: float = 0.0
var skill1_cd: float = 0.0
var skill2_cd: float = 0.0
var game_time: float = 0.0
var evolved: bool = false

@onready var aggro: AggroSystem = $AggroSystem
@onready var sprite: Sprite2D = $Sprite2D
@onready var hp_bar: Control = $HealthBar
@onready var spawn_fx: GPUParticles2D = $SpawnFX


func _ready() -> void:
	add_to_group("monsters")
	current_hp = max_hp
	aggro.setup(self, global_position)
	aggro.aggro_range = aggro_range
	aggro.disengage_range = disengage_range
	aggro.max_leash_distance = max_leash
	aggro.retreat_speed = retreat_spd
	collision_layer = 64; collision_mask = 1

func _physics_process(delta: float) -> void:
	if is_dead: return
	game_time += delta
	_evolve_check()
	_check_berserk(delta)
	if aggro.is_retreating or aggro.is_invulnerable: return

	var target := _get_target()
	if target: _try_attack(target, delta)
	# 找新目标
	if not aggro.current_target:
		var heroes: Array = []; heroes.assign(get_tree().get_nodes_in_group("heroes"))
		aggro.try_acquire(heroes)

func _evolve_check() -> void:
	if evolved: return
	if is_dragon and game_time >= 600:
		evolved = true
		max_hp = 16000; current_hp = max_hp; attack = 300
		print("[Boss] 暴君进化为黑暗暴君！")
	if not is_dragon and game_time >= 1200:
		evolved = true
		max_hp = 18000; current_hp = max_hp; attack = 260

func _check_berserk(delta: float) -> void:
	if not is_berserk: return
	berserk_timer -= delta
	if berserk_timer <= 0: is_berserk = false

func _get_target() -> Node2D:
	if aggro.current_target and is_instance_valid(aggro.current_target):
		return aggro.current_target
	return null

func _try_attack(target: Node2D, delta: float) -> void:
	atk_cooldown -= delta; skill1_cd -= delta; skill2_cd -= delta
	var d := global_position.distance_to(target.global_position)
	var rng := 300.0
	if d > rng * 2: return
	if d <= rng and atk_cooldown <= 0:
		var spd := 2.0; if is_berserk: spd *= 0.5
		atk_cooldown = spd
		var dmg := attack
		if is_berserk: dmg = int(dmg * 1.5)
		if target.has_method("take_damage"): target.take_damage(dmg)
		aggro.on_hit_target()
	# 技能
	if skill1_cd <= 0:
		skill1_cd = 8.0 if is_dragon else 10.0
		_cast_skill1(target)
	if skill2_cd <= 0 and current_hp < max_hp * 0.5:
		skill2_cd = 15.0
		is_berserk = true; berserk_timer = 10.0
		print("[Boss] 狂暴！")

func _cast_skill1(target: Node2D) -> void:
	if is_dragon:
		# 地面震击 AOE
		for h in get_tree().get_nodes_in_group("heroes"):
			if h.has_method("take_damage") and global_position.distance_to(h.global_position) < 500:
				h.take_damage(250)
	else:
		# 击飞最近目标
		if target.has_method("take_damage"): target.take_damage(300)
		if target.has_method("knockup"): target.knockup(1.0)

func take_damage(dmg: int) -> void:
	if is_dead or aggro.is_invulnerable: return
	current_hp = max(current_hp - dmg, 0)
	if current_hp <= 0: _die()

func _die() -> void:
	is_dead = true; collision_layer = 0
	if is_dragon:
		# 暴君击杀：全队金币
		for h in get_tree().get_nodes_in_group("heroes"):
			if h.has_method("add_gold"): h.add_gold(200 if evolved else 100)
	else:
		for h in get_tree().get_nodes_in_group("heroes"):
			if h.has_method("add_gold"): h.add_gold(200 if evolved else 150)
	await get_tree().create_timer(2.0).timeout
	_respawn()

func _respawn() -> void:
	is_dead = false; current_hp = max_hp
	global_position = aggro.spawn_position
	collision_layer = 64; collision_mask = 1

func reset_hp() -> void:
	current_hp = max_hp
