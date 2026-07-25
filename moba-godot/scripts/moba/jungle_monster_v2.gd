extends CharacterBody2D
class_name JungleMonsterV2

## 小野怪/红蓝Buff — 严格短距离追击（500-700px）+ 同组共享仇恨

@export var monster_type: String = "stone_beetle"
@export var max_hp: int = 800
@export var attack: int = 35
@export var gold_value: int = 45
@export var xp_value: int = 60
@export var aggro_range: float = 500.0
@export var disengage_range: float = 700.0
@export var max_leash: float = 500.0
@export var retreat_spd: float = 350.0
@export var atk_interval: float = 1.5

var current_hp: int = 800
var is_dead: bool = false
var atk_cooldown: float = 0.0
var camp_group: Array = []  # 同组其他野怪

@onready var aggro: AggroSystem = $AggroSystem
@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("monsters")
	current_hp = max_hp
	aggro.setup(self, global_position)
	aggro.aggro_range = aggro_range
	aggro.disengage_range = disengage_range
	aggro.max_leash_distance = max_leash
	aggro.retreat_speed = retreat_spd
	collision_layer = 32; collision_mask = 1

func _physics_process(_delta: float) -> void:
	if is_dead or aggro.is_retreating or aggro.is_invulnerable: return
	var target := aggro.current_target
	if not target:
		var heroes: Array = []; heroes.assign(get_tree().get_nodes_in_group("heroes"))
		aggro.try_acquire(heroes)
		target = aggro.current_target
	if not target: return

	var d := global_position.distance_to(target.global_position)
	if d <= 80 and atk_cooldown <= 0:
		atk_cooldown = atk_interval
		if target.has_method("take_damage"): target.take_damage(attack)
		aggro.on_hit_target()
		_notify_camp(target)
	atk_cooldown -= _delta
	if d > 80 and d < aggro_range:
		velocity = (target.global_position - global_position).normalized() * 150
		move_and_slide()

func _notify_camp(target: Node2D) -> void:
	for other in camp_group:
		if not is_instance_valid(other) or other == self: continue
		var agg: AggroSystem = other.get_node_or_null("AggroSystem") as AggroSystem
		if agg and not agg.current_target:
			agg.acquire_target(target)

func take_damage(dmg: int) -> void:
	if is_dead or aggro.is_invulnerable: return
	current_hp = max(current_hp - dmg, 0)
	if aggro.is_retreating: return
	# 通知全组
	for other in camp_group:
		if not is_instance_valid(other) or other == self: continue
		var agg: AggroSystem = other.get_node_or_null("AggroSystem") as AggroSystem
		if agg and not agg.current_target and dmg > 0:
			# 找到最近的英雄
			var heroes: Array = []; heroes.assign(get_tree().get_nodes_in_group("heroes"))
			agg.try_acquire(heroes)
	if current_hp <= 0: _die()

func _die() -> void:
	is_dead = true; collision_layer = 0
	visible = false
	_give_reward()
	await get_tree().create_timer(70.0).timeout
	_respawn()

func _respawn() -> void:
	is_dead = false; current_hp = max_hp; visible = true
	global_position = aggro.spawn_position
	collision_layer = 32; collision_mask = 1

func _give_reward() -> void:
	for h in get_tree().get_nodes_in_group("heroes"):
		if h.has_method("add_gold") and global_position.distance_to(h.global_position) < 1000:
			h.add_gold(gold_value)
		if h.has_method("add_xp") and global_position.distance_to(h.global_position) < 1000:
			h.add_xp(xp_value)

func reset_hp() -> void:
	current_hp = max_hp
