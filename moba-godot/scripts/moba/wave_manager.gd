extends Node
class_name WaveManager

## 兵线交汇管理器 — 计算交汇点、推进状态

var lane_states: Dictionary = {}
var meet_history: Dictionary = {}  # lane → Array[Vector2] 最近10次交汇点

const MEET_THRESHOLD: float = 200.0   # <200px → 判定交汇
const PUSH_OFFSET: float = 150.0       # 每多存活1兵偏移150px
const CANNON_OFFSET: float = 200.0     # 炮车额外偏移


func _ready() -> void:
	for lane in ["top", "mid", "bot"]:
		lane_states[lane] = {"state":"NO_MINIONS", "meet":Vector2(5000,5000), "blue":0, "red":0}
		meet_history[lane] = []

func _process(_delta: float) -> void:
	var timer_now := Time.get_ticks_msec() * 0.001
	if fmod(timer_now, 0.5) > 0.05: return  # 每0.5秒更新一次
	for lane in ["top", "mid", "bot"]:
		_update_lane(lane)

func _update_lane(lane: String) -> void:
	var blues: Array[Minion] = []; var reds: Array[Minion] = []
	for m in get_tree().get_nodes_in_group("minions"):
		if not is_instance_valid(m) or m.is_dead: continue
		if m.lane != lane: continue
		if m.team == "team_blue": blues.append(m)
		else: reds.append(m)

	var bc := blues.size(); var rc := reds.size()
	if bc == 0 and rc == 0:
		lane_states[lane] = {"state":"NO_MINIONS", "meet":Vector2(5000,5000), "blue":0, "red":0}
		return

	# 找前锋（最靠前的兵）
	var blue_front := _get_front(blues, 1)
	var red_front  := _get_front(reds, -1)
	if blue_front == null: blue_front = Vector2(0, 5000)
	if red_front == null: red_front = Vector2(10000, 5000)

	var meet := (blue_front + red_front) / 2.0
	var dist := blue_front.distance_to(red_front)

	# 状态判定
	var state: String
	if dist < MEET_THRESHOLD:
		state = "CLASHING"
	elif bc > 0 and rc == 0:
		state = "PUSHING_BLUE"
	elif rc > 0 and bc == 0:
		state = "PUSHING_RED"
	else:
		state = "CLASHING"

	# 推进偏移
	var push := 0.0
	push += (bc - rc) * PUSH_OFFSET
	var cannon_b := blues.filter(func(m): return m.minion_type == "cannon").size()
	var cannon_r := reds.filter(func(m): return m.minion_type == "cannon").size()
	push += (cannon_b - cannon_r) * CANNON_OFFSET
	meet.x += push * 0.5

	# 检查是否到塔下
	for t in get_tree().get_nodes_in_group("towers"):
		var d := meet.distance_to(t.global_position)
		if d < 700:
			state = "AT_BLUE_TOWER" if t.team == "team_blue" else "AT_RED_TOWER"
			break

	lane_states[lane] = {"state":state, "meet":meet, "blue":bc, "red":rc}
	meet_history[lane].append(meet)
	if meet_history[lane].size() > 10:
		meet_history[lane].pop_front()

func _get_front(minions: Array, direction: int) -> Variant:
	var best: Vector2 = Vector2.NEG_INF if direction > 0 else Vector2.INF
	var found: bool = false
	for m in minions:
		if not is_instance_valid(m): continue
		var p := m.global_position
		if direction > 0 and p.x > best.x: best = p; found = true
		elif direction < 0 and p.x < best.x: best = p; found = true
	return best if found else null

## 判断兵线趋势（连续5次同向偏移 >300px → 推进）
func get_lane_trend(lane: String) -> String:
	var hist := meet_history.get(lane, [])
	if hist.size() < 5: return "CLASHING"
	var offset := hist[hist.size()-1].x - hist[hist.size()-5].x
	if offset > 300: return "PUSHING_BLUE"
	if offset < -300: return "PUSHING_RED"
	return "CLASHING"

func get_meet_point(lane: String) -> Vector2:
	return lane_states.get(lane, {}).get("meet", Vector2(5000,5000))
