extends Node
class_name SpawnManager

## 兵线波次管理器 — 首波10秒，30秒间隔

@export var first_wave_delay: float = 10.0
@export var wave_interval: float = 30.0
@export var minion_birth_delay: float = 0.5
@export var growth_per_wave: float = 0.08

var wave_count: int = 0
var timer: float = 0.0
var is_spawning: bool = false
var minion_template: PackedScene
var cannon_template: PackedScene
var super_template: PackedScene

var lanes := ["top", "mid", "bot"]
var blue_spawns := {"top": Vector2(1500,8500), "mid": Vector2(1800,8200), "bot": Vector2(2200,7800)}
var red_spawns  := {"top": Vector2(8500,1500), "mid": Vector2(8200,1800), "bot": Vector2(7800,2200)}
var high_ground_lost := {"team_blue": [], "team_red": []}

signal wave_spawned(wave: int)


func _ready() -> void:
	timer = -first_wave_delay  # 首波延迟10秒

func _process(delta: float) -> void:
	if is_spawning: return
	timer += delta
	if timer >= wave_interval:
		timer -= wave_interval
		_spawn_wave()

func _spawn_wave() -> void:
	is_spawning = true
	wave_count += 1
	var with_cannon := wave_count % 3 == 0
	for lane in lanes:
		_spawn_lane(lane, with_cannon)
	wave_spawned.emit(wave_count)
	is_spawning = false

func _spawn_lane(lane: String, has_cannon: bool) -> void:
	var tasks := []
	# 蓝方：3近战+3远程(+炮车)
	for i in range(3):
		tasks.append({"team":"team_blue","lane":lane,"type":MinionStats.MinionType.MELEE,"spawn":blue_spawns[lane]})
	for i in range(3):
		tasks.append({"team":"team_blue","lane":lane,"type":MinionStats.MinionType.RANGED,"spawn":blue_spawns[lane]})
	if has_cannon:
		tasks.append({"team":"team_blue","lane":lane,"type":MinionStats.MinionType.CANNON,"spawn":blue_spawns[lane]})
	# 蓝方出超级兵？
	if lane in high_ground_lost["team_blue"]:
		tasks.append({"team":"team_blue","lane":lane,"type":MinionStats.MinionType.SUPER,"spawn":blue_spawns[lane]})
	# 红方
	for i in range(3):
		tasks.append({"team":"team_red","lane":lane,"type":MinionStats.MinionType.MELEE,"spawn":red_spawns[lane]})
	for i in range(3):
		tasks.append({"team":"team_red","lane":lane,"type":MinionStats.MinionType.RANGED,"spawn":red_spawns[lane]})
	if has_cannon:
		tasks.append({"team":"team_red","lane":lane,"type":MinionStats.MinionType.CANNON,"spawn":red_spawns[lane]})
	if lane in high_ground_lost["team_red"]:
		tasks.append({"team":"team_red","lane":lane,"type":MinionStats.MinionType.SUPER,"spawn":red_spawns[lane]})

	for i in range(tasks.size()):
		await get_tree().create_timer(minion_birth_delay).timeout
		var t := tasks[i]
		_spawn_one(t["team"], t["lane"], t["type"], t["spawn"])

func _spawn_one(_team: String, _lane: String, _type: int, _pos: Vector2) -> void:
	var scene: PackedScene
	match _type:
		MinionStats.MinionType.CANNON: scene = cannon_template
		MinionStats.MinionType.SUPER:  scene = super_template
		_:                             scene = minion_template
	if not scene: return
	var m := scene.instantiate() as Minion
	get_parent().add_child(m)
	m.global_position = _pos + Vector2(randf_range(-20,20), randf_range(-20,20))
	m.stats = MinionStats.new(_type, wave_count)
	m.team = _team; m.lane = _lane
	m.move_dir = 1 if _team == "team_blue" else -1
	# 调用ready
	m._ready.call_deferred()
