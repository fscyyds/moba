extends Node
class_name MinionWaveManager

## 兵线管理器 — 每30秒一波，每3波加炮车

@export var minion_scene_melee: PackedScene
@export var minion_scene_ranged: PackedScene
@export var minion_scene_cannon: PackedScene

@export var lanes: Array[LanePath] = []
@export var spawn_interval: float = 30.0    # 每波间隔
@export var per_wave_melee: int = 3
@export var per_wave_ranged: int = 3
@export var cannon_every_n_waves: int = 3   # 每N波加炮车
@export var birth_delay: float = 0.8        # 每兵出生间隔
@export var growth_interval: float = 180.0  # 每3分钟成长

var timer: float = 0.0
var wave_count: int = 0
var game_time: float = 0.0
var is_active: bool = true


func _ready() -> void:
	# 获取场景中的 LanePath 节点
	var parent := get_parent()
	for child in parent.get_children():
		if child is LanePath:
			lanes.append(child)

func _process(delta: float) -> void:
	if not is_active: return
	game_time += delta
	timer += delta
	if timer >= spawn_interval:
		timer -= spawn_interval
		_spawn_wave()

func _spawn_wave() -> void:
	wave_count += 1
	var include_cannon := wave_count % cannon_every_n_waves == 0
	for lane in lanes:
		_spawn_lane(lane, include_cannon)

func _spawn_lane(lane: LanePath, with_cannon: bool) -> void:
	var types_and_counts := [
		[minion_scene_melee, per_wave_melee, MinionStats.MinionType.MELEE],
		[minion_scene_ranged, per_wave_ranged, MinionStats.MinionType.RANGED],
	]
	if with_cannon:
		types_and_counts.append([minion_scene_cannon, 1, MinionStats.MinionType.CANNON])

	var total := 0
	for entry in types_and_counts:
		total += entry[1]

	var idx := 0
	for entry in types_and_counts:
		var scene: PackedScene = entry[0]
		var count: int = entry[1]
		var mtype: MinionStats.MinionType = entry[2]
		for i in range(count):
			await _delayed_spawn(lane, scene, mtype, idx * birth_delay, total)
			idx += 1

func _delayed_spawn(lane: LanePath, scene: PackedScene, mtype: int, delay: float, _total: int) -> void:
	await get_tree().create_timer(delay).timeout
	if not scene or not lane: return
	var minion := scene.instantiate() as CharacterBody2D
	get_parent().add_child(minion)
	# 蓝方（ratio=0 → 1）
	var blue_pos := lane.curve.sample_baked(0.0)
	var red_pos := lane.curve.sample_baked(lane.curve.get_baked_length())
	minion.global_position = blue_pos + Vector2(randf_range(-15, 15), randf_range(-15, 15))
	if minion.has_method("_ready_minion"):
		minion._ready_minion(lane, 1, mtype)  # 1=蓝方向
	# 红方
	var red := scene.instantiate() as CharacterBody2D
	get_parent().add_child(red)
	red.global_position = red_pos + Vector2(randf_range(-15, 15), randf_range(-15, 15))
	if red.has_method("_ready_minion"):
		red._ready_minion(lane, -1, mtype)
	# 应用成长
	var minutes := game_time / 60.0
	for m in [minion, red]:
		var ms := m.get_node_or_null("MinionStats") as MinionStats
		if ms: ms.apply_growth(minutes)
