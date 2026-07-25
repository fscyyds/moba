extends Node
class_name MinionFormation

## 小兵编队散开 — 避免同队重叠，保持40px间距

const MIN_SPACING: float = 40.0  # 最小间距
const REPEL_FORCE: float = 80.0  # 排斥力


func _process(_delta: float) -> void:
	var minions_by_lane: Dictionary = {}
	for m in get_tree().get_nodes_in_group("minions"):
		if not is_instance_valid(m): continue
		var lane := m.get("lane") as String
		if lane == "": continue
		if not minions_by_lane.has(lane):
			minions_by_lane[lane] = {"team_blue": [], "team_red": []}
		var team := m.get("team") as String
		if team in minions_by_lane[lane]:
			minions_by_lane[lane][team].append(m)

	for lane in minions_by_lane:
		for team in minions_by_lane[lane]:
			_apply_repel(minions_by_lane[lane][team])

func _apply_repel(units: Array) -> void:
	for i in range(units.size()):
		for j in range(i + 1, units.size()):
			var a: Node2D = units[i]; var b: Node2D = units[j]
			if not is_instance_valid(a) or not is_instance_valid(b): continue
			var d := a.global_position.distance_to(b.global_position)
			if d < MIN_SPACING and d > 0.01:
				var dir := (a.global_position - b.global_position).normalized()
				var force := (MIN_SPACING - d) * REPEL_FORCE * 0.01
				a.position += dir * force
				b.position -= dir * force

## 远程兵风筝：被近身<150px时后退
func apply_kite(ranged_unit: CharacterBody2D, nearest_enemy: Node2D) -> Vector2:
	if not nearest_enemy: return Vector2.ZERO
	var d := ranged_unit.global_position.distance_to(nearest_enemy.global_position)
	if d < 150:
		return (ranged_unit.global_position - nearest_enemy.global_position).normalized() * 100
	if d < 350:
		return Vector2.ZERO
	return Vector2.ZERO
