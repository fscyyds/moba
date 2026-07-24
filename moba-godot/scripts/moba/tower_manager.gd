extends Node
class_name TowerManager

## 全局塔管理器 — 解锁链、胜负判定

signal tower_destroyed(team: String, lane: String, tier: int)

var towers: Dictionary = {}  # "blue_mid_T1" → TowerStats

func _ready() -> void:
	await get_tree().process_frame
	_register_all_towers()
	_apply_initial_locks()

## 注册所有塔
func _register_all_towers() -> void:
	for tower_node in get_tree().get_nodes_in_group("towers"):
		var ts: TowerStats = tower_node.get_node_or_null("TowerStats") as TowerStats
		if not ts: continue
		ts.tower_manager_ref = self
		var key := _make_key(ts.team, ts.lane, ts.tower_tier)
		towers[key] = ts

func _make_key(team: String, lane: String, tier: TowerStats.Tier) -> String:
	return team + "_" + lane + "_" + str(tier)

## 初始锁定：除 T1 外所有塔无敌
func _apply_initial_locks() -> void:
	for key in towers:
		var ts: TowerStats = towers[key]
		if ts.tower_tier == TowerStats.Tier.T4:
			ts.is_invincible = true
		elif ts.tower_tier != TowerStats.Tier.T1:
			ts.is_invincible = true

## 塔被摧毁时的回调
func on_tower_destroyed(team: String, lane: String, tier: TowerStats.Tier) -> void:
	tower_destroyed.emit(team, lane, tier)
	print("[TowerManager] %s %s T%d 被摧毁!" % [team, lane, tier])
	# 解锁下一座
	_unlock_next(team, lane, tier)
	# 胜负检测
	_check_victory()

## 解锁下一座塔
func _unlock_next(team: String, lane: String, current_tier: TowerStats.Tier) -> void:
	if current_tier == TowerStats.Tier.T4:
		return
	var next_tier := current_tier + 1 as TowerStats.Tier
	var key := _make_key(team, lane, next_tier)
	if towers.has(key):
		var ts: TowerStats = towers[key]
		ts.unlock()
		print("[TowerManager] 解锁 ", key)

## 检测胜负
func _check_victory() -> void:
	var blue_crystal := towers.get("team_blue_mid_4", null) as TowerStats
	var red_crystal := towers.get("team_red_mid_4", null) as TowerStats
	if blue_crystal and blue_crystal.is_dead:
		print("[TowerManager] 蓝方水晶被摧毁，红方胜利！")
		_game_over("team_red")
	if red_crystal and red_crystal.is_dead:
		print("[TowerManager] 红方水晶被摧毁，蓝方胜利！")
		_game_over("team_blue")

func _game_over(winner: String) -> void:
	print("[TowerManager] 游戏结束! 胜者: ", winner)
	# 暂停所有
	get_tree().paused = true

## 查询塔是否已解锁
func is_tower_unlocked(team: String, lane: String, tier: TowerStats.Tier) -> bool:
	var key := _make_key(team, lane, tier)
	if towers.has(key):
		return not (towers[key] as TowerStats).is_invincible
	return true
