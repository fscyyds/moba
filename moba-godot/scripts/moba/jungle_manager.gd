extends Node
class_name JungleManager

## 全局野怪管理器 — 所有营地 + Boss + 河蟹

var camps: Array[JungleCamp] = []
var game_time: float = 0.0

# 营地配置表
const CAMP_CONFIGS := [
	# 蓝方野区
	{"type":JungleData.CampType.STONE_BEETLES,"name":"蓝石甲","pos":Vector2(2000,7200)},
	{"type":JungleData.CampType.WOLVES,"name":"蓝野狼","pos":Vector2(2500,6500)},
	{"type":JungleData.CampType.BIRDS,"name":"蓝野鸟","pos":Vector2(1800,5800)},
	{"type":JungleData.CampType.LIZARDS,"name":"蓝蜥蜴","pos":Vector2(3000,5500)},
	{"type":JungleData.CampType.RED_BUFF,"name":"蓝红Buff","pos":Vector2(3000,7000)},
	{"type":JungleData.CampType.BLUE_BUFF,"name":"蓝蓝Buff","pos":Vector2(2000,6000)},
	# 红方野区
	{"type":JungleData.CampType.STONE_BEETLES,"name":"红石甲","pos":Vector2(8000,2800)},
	{"type":JungleData.CampType.WOLVES,"name":"红野狼","pos":Vector2(7500,3500)},
	{"type":JungleData.CampType.BIRDS,"name":"红野鸟","pos":Vector2(8200,4200)},
	{"type":JungleData.CampType.LIZARDS,"name":"红蜥蜴","pos":Vector2(7000,4500)},
	{"type":JungleData.CampType.RED_BUFF,"name":"红红Buff","pos":Vector2(7000,3000)},
	{"type":JungleData.CampType.BLUE_BUFF,"name":"红蓝Buff","pos":Vector2(8000,4000)},
	# 河蟹
	{"type":JungleData.CampType.RIVER_CRAB,"name":"左河蟹","pos":Vector2(4500,5200)},
	{"type":JungleData.CampType.RIVER_CRAB,"name":"右河蟹","pos":Vector2(5500,4800)},
	# Boss
	{"type":JungleData.CampType.DRAGON,"name":"暴君","pos":Vector2(4000,6000)},
	{"type":JungleData.CampType.BARON,"name":"主宰","pos":Vector2(6000,4000)},
]


func _ready() -> void:
	for cfg in CAMP_CONFIGS:
		var camp := JungleCamp.new()
		camp.camp_type = cfg["type"]
		camp.camp_name = cfg["name"]
		camp.spawn_pos = cfg["pos"]
		camp.name = cfg["name"]
		add_child(camp)
		# Timer
		var t := Timer.new(); t.name = "RespawnTimer"; camp.add_child(t)
		var fx := GPUParticles2D.new(); fx.name = "SpawnFX"; camp.add_child(fx)
		camp._ready.call_deferred()
		camps.append(camp)

func _process(delta: float) -> void:
	game_time += delta

func get_camp_status(camp_name: String) -> String:
	for c in camps:
		if c.camp_name == camp_name:
			return "存活" if c.is_active else "死亡"
	return "未知"
