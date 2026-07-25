extends Node2D
class_name JungleCamp

## 野怪营地 — 管理一组野怪的刷新/脱战/计时

@export var camp_type: int = 0
@export var camp_name: String = "营地"
@export var spawn_pos: Vector2 = Vector2.ZERO
@onready var respawn_timer: Timer = $RespawnTimer
@onready var spawn_fx: GPUParticles2D = $SpawnFX

var monsters: Array[JungleMonster] = []
var data: JungleData
var is_active: bool = false
var game_time: float = 0.0


func _ready() -> void:
	data = JungleData.new(camp_type, 0)
	respawn_timer.wait_time = data.first_spawn
	respawn_timer.timeout.connect(_spawn_monsters)
	respawn_timer.start()

func _process(delta: float) -> void:
	game_time += delta
	if not is_active: return
	# Check if all dead → restart timer
	var all_dead := true
	for m in monsters:
		if is_instance_valid(m) and not m.is_dead: all_dead = false
	if all_dead and is_active:
		is_active = false
		respawn_timer.wait_time = data.respawn_interval
		respawn_timer.start()

func _spawn_monsters() -> void:
	is_active = true
	monsters.clear()
	for i in range(data.head_count):
		var m := JungleMonster.new()
		m.data = JungleData.new(camp_type, game_time)
		m.name = camp_name + "_" + str(i)
		add_child(m)
		var offset := Vector2(randf_range(-30,30), randf_range(-30,30))
		m.global_position = spawn_pos + offset
		# Create child nodes for monster
		var sp := Sprite2D.new(); sp.name = "Sprite2D"
		sp.texture = _get_monster_texture(); m.add_child(sp)
		var cs := CollisionShape2D.new(); cs.shape = CircleShape2D.new()
		cs.shape.radius = 16; m.add_child(cs)
		var nav := NavigationAgent2D.new(); nav.name = "NavigationAgent2D"
		m.add_child(nav)
		var aggro := Area2D.new(); aggro.name = "AggroZone"
		var acs := CollisionShape2D.new(); acs.shape = CircleShape2D.new()
		acs.shape.radius = 800; aggro.add_child(acs); m.add_child(aggro)
		var hp := Control.new(); hp.name = "HealthBar"; m.add_child(hp)
		var bg := ColorRect.new(); bg.name = "BG"; bg.size = Vector2(40,4)
		bg.color = Color.BLACK; hp.add_child(bg)
		var fill := ColorRect.new(); fill.name = "Fill"; fill.size = Vector2(36,3)
		fill.position = Vector2(2,0.5); fill.color = Color.RED; hp.add_child(fill)
		var atk := Timer.new(); atk.name = "AttackCooldown"; m.add_child(atk)
		m.collision_layer = 64; m.collision_mask = 1
		m._ready.call_deferred()
		monsters.append(m)
	if spawn_fx: spawn_fx.emitting = true

func _get_monster_texture() -> Texture2D:
	return null  # 项目中需替换为实际贴图
