extends JungleMonster
class_name BossMonster

## Boss 野怪 — 暴君(2分钟)/主宰(8分钟) + 进化

@export var is_dragon: bool = true  # true=暴君, false=主宰
@export var evolved: bool = false
@export var evolve_time: float = 600.0  # 10分钟进化（暴君）

var evolve_timer: float = 0.0


func _ready() -> void:
	super._ready()
	if is_dragon: evolve_time = 600.0

func _process(delta: float) -> void:
	super._process(delta)
	if not evolved and is_dragon:
		evolve_timer += delta
		if evolve_timer >= evolve_time:
			_evolve()

func _evolve() -> void:
	evolved = true
	data.max_hp = 15000; data.attack = 250
	current_hp = data.max_hp
	# 全屏特效
	print("[Boss] 暴君进化为黑暗暴君！")

func _give_reward() -> void:
	var killer_team := ""
	for h in get_tree().get_nodes_in_group("heroes"):
		var d := global_position.distance_to(h.global_position)
		if d < 2000:
			if h.has_method("add_gold"): h.add_gold(data.gold_value)
			if h.has_method("add_xp"): h.add_xp(data.xp_value)
			if d < 500: killer_team = h.get_groups()[0] if h.get_groups().size() > 0 else ""
	# 主宰击杀：所有己方兵线变主宰先锋
	if not is_dragon and killer_team != "":
		for m in get_tree().get_nodes_in_group("minions"):
			if m.is_in_group(killer_team):
				var ms := m.get_node_or_null("MinionStats") as MinionStats
				if ms: ms.minion_type = MinionStats.MinionType.SUPER
