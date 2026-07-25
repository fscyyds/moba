extends Node
class_name TowerTargeting

## 防御塔目标选择 — 含伤害递增（打同一目标每次+10%）

const ATTACK_RANGE: float = 700.0
const BASE_DAMAGE: float = 120.0
const DAMAGE_INCREMENT: float = 0.10  # 每次+10%
const MAX_STACKS: int = 10

var damage_stacks: Dictionary = {}  # target_id → hits


func select_target(tower: Node2D, team: String) -> Node2D:
	var targets: Array[Node2D] = []
	for body in get_tree().get_nodes_in_group("minions") + get_tree().get_nodes_in_group("heroes"):
		if not is_instance_valid(body): continue
		if body.is_in_group(team): continue
		if tower.global_position.distance_to(body.global_position) < ATTACK_RANGE:
			targets.append(body)
	if targets.is_empty(): return null

	# 优先级：打我方英雄的兵 > 最近兵 > 英雄
	for t in targets:
		if t.is_in_group("minions") and _is_attacking_ally(t, team):
			return t
	for t in targets:
		if t.is_in_group("minions"): return t
	for t in targets:
		if t.is_in_group("heroes"): return t
	return targets[0]

func get_damage(target: Node2D) -> float:
	var sid := str(target.get_instance_id())
	if not damage_stacks.has(sid):
		damage_stacks[sid] = 0
	# Reset if target changed
	for k in damage_stacks.keys():
		if k != sid: damage_stacks.erase(k)
	damage_stacks[sid] = min(damage_stacks[sid] + 1, MAX_STACKS)
	return BASE_DAMAGE * (1.0 + (damage_stacks[sid] - 1) * DAMAGE_INCREMENT)

func reset_stacks() -> void:
	damage_stacks.clear()

func _is_attacking_ally(target: Node2D, team: String) -> bool:
	if not target.has_method("get_current_target"): return false
	var t := target.get_current_target()
	return t != null and t.is_in_group(team)
