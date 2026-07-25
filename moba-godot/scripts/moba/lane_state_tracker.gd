extends Node
class_name LaneStateTracker

## 兵线状态追踪 — 每路状态+交汇历史+小地图数据

enum LaneState { PUSHING_BLUE, PUSHING_RED, CLASHING, AT_BLUE_TOWER, AT_RED_TOWER, NO_MINIONS }

@onready var wave_mgr: WaveManager = $"../WaveManager"

var map_data := {"top": {}, "mid": {}, "bot": {}}


func _ready() -> void:
	if not wave_mgr:
		wave_mgr = get_node_or_null("/root/Main/WaveManager")

func get_state(lane: String) -> LaneState:
	if not wave_mgr: return LaneState.NO_MINIONS
	var s := wave_mgr.lane_states.get(lane, {}).get("state", "NO_MINIONS")
	match s:
		"PUSHING_BLUE": return LaneState.PUSHING_BLUE
		"PUSHING_RED": return LaneState.PUSHING_RED
		"CLASHING": return LaneState.CLASHING
		"AT_BLUE_TOWER": return LaneState.AT_BLUE_TOWER
		"AT_RED_TOWER": return LaneState.AT_RED_TOWER
	return LaneState.NO_MINIONS

func get_minion_counts(lane: String) -> Dictionary:
	if not wave_mgr: return {"b":0,"r":0}
	var s := wave_mgr.lane_states.get(lane, {})
	return {"blue": s.get("blue",0), "red": s.get("red",0)}

func get_meet_point(lane: String) -> Vector2:
	return wave_mgr.get_meet_point(lane) if wave_mgr else Vector2(5000,5000)

func get_trend(lane: String) -> String:
	return wave_mgr.get_lane_trend(lane) if wave_mgr else "CLASHING"

## 调试：手动刷兵
func _input(event: InputEvent) -> void:
	if not event.is_pressed(): return
	var lane: String = ""
	if event.is_action_pressed("ui_1") or Input.is_key_pressed(KEY_1): lane = "top"
	elif event.is_action_pressed("ui_2") or Input.is_key_pressed(KEY_2): lane = "mid"
	elif event.is_action_pressed("ui_3") or Input.is_key_pressed(KEY_3): lane = "bot"
	if lane != "":
		var spawner := get_node_or_null("/root/Main/WaveSpawner") as WaveSpawner
		if spawner: spawner._spawn_lane(lane)
