extends Node
class_name WaveSpawner

## 兵线刷新管理器 — 首波10秒，30秒间隔，3波1炮车

signal wave_spawned(wave: int, lane: String)

const FIRST_WAVE := 10.0
const WAVE_INTERVAL := 30.0
const BIRTH_DELAY := 0.5
const CANNON_EVERY := 3

var wave_count: int = 0
var timer: float = -FIRST_WAVE
var game_time: float = 0.0
var is_spawning: bool = false

# 出生点
const BLUE_SPAWNS := {"top": Vector2(1500,8500), "mid": Vector2(1800,8200), "bot": Vector2(2200,7800)}
const RED_SPAWNS  := {"top": Vector2(8500,1500), "mid": Vector2(8200,1800), "bot": Vector2(7800,2200)}

# 高地塔被破 → 出超级兵
var high_ground_lost := {"team_blue": [], "team_red": []}

# 小兵场景模板
@export var melee_scene: PackedScene
@export var ranged_scene: PackedScene
@export var cannon_scene: PackedScene
@export var super_scene: PackedScene

var lanes := ["top", "mid", "bot"]


func _process(delta: float) -> void:
	game_time += delta
	if is_spawning: return
	timer += delta
	if timer >= WAVE_INTERVAL:
		timer -= WAVE_INTERVAL
		wave_count += 1
		_spawn_all_lanes()

func _spawn_all_lanes() -> void:
	is_spawning = true
	for lane in lanes:
		await _spawn_lane(lane)
		wave_spawned.emit(wave_count, lane)
	is_spawning = false

func _spawn_lane(lane: String) -> void:
	var has_cannon := wave_count % CANNON_EVERY == 0
	var tasks: Array[Dictionary] = []

	# 蓝方：3近战+3远程
	_add_units(tasks, "team_blue", lane, "melee", 3)
	_add_units(tasks, "team_blue", lane, "ranged", 3)
	if has_cannon:
		tasks.append({"team":"team_blue","lane":lane,"type":"cannon"})
	if lane in high_ground_lost["team_blue"]:
		tasks.append({"team":"team_blue","lane":lane,"type":"super"})

	# 红方
	_add_units(tasks, "team_red", lane, "melee", 3)
	_add_units(tasks, "team_red", lane, "ranged", 3)
	if has_cannon:
		tasks.append({"team":"team_red","lane":lane,"type":"cannon"})
	if lane in high_ground_lost["team_red"]:
		tasks.append({"team":"team_red","lane":lane,"type":"super"})

	for i in range(tasks.size()):
		await get_tree().create_timer(BIRTH_DELAY).timeout
		var t := tasks[i]
		_create_minion(t["team"], t["lane"], t["type"])

func _add_units(arr: Array, team: String, lane: String, mtype: String, count: int) -> void:
	for _i in range(count):
		arr.append({"team":team, "lane":lane, "type":mtype})

func _create_minion(team: String, lane: String, mtype: String) -> void:
	var scene: PackedScene
	match mtype:
		"melee":  scene = melee_scene
		"ranged": scene = ranged_scene
		"cannon": scene = cannon_scene
		"super":  scene = super_scene
	if not scene: return

	var m := scene.instantiate() as Minion
	get_parent().add_child(m)
	var sp := BLUE_SPAWNS[lane] if team == "team_blue" else RED_SPAWNS[lane]
	m.global_position = sp + Vector2(randf_range(-25,25), randf_range(-25,25))
	m.team = team; m.lane = lane
	m.minion_type = mtype
	m.wave_number = wave_count
	m.move_dir = 1 if team == "team_blue" else -1
	m._ready.call_deferred()

func get_wave_time(n: int) -> float:
	return FIRST_WAVE + (n - 1) * WAVE_INTERVAL

func is_cannon_wave(n: int) -> bool:
	return n % CANNON_EVERY == 0
