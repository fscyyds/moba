extends Resource
class_name MapData

## 地图数据配置 — 所有坐标、属性常量

const MAP_W := 10000.0; const MAP_H := 10000.0

# 基地
const BLUE_NEXUS  := Vector2(1000, 9000)
const RED_NEXUS   := Vector2(9000, 1000)
const BLUE_FOUNTAIN := Vector2(500, 9500)
const RED_FOUNTAIN  := Vector2(9500, 500)

# 蓝方塔
const BLUE_TOWERS := {
	"top_outer":  {"pos": Vector2(1200,6500), "tier":"outer"},
	"top_inner":  {"pos": Vector2(1000,4500), "tier":"inner"},
	"top_high":   {"pos": Vector2(1200,2500), "tier":"high"},
	"mid_outer":  {"pos": Vector2(3200,6800), "tier":"outer"},
	"mid_inner":  {"pos": Vector2(2400,7600), "tier":"inner"},
	"mid_high":   {"pos": Vector2(1600,8400), "tier":"high"},
	"bot_outer":  {"pos": Vector2(6500,8800), "tier":"outer"},
	"bot_inner":  {"pos": Vector2(4500,9000), "tier":"inner"},
	"bot_high":   {"pos": Vector2(2500,8800), "tier":"high"},
}

# 红方塔（对称）
const RED_TOWERS := {
	"top_outer":  {"pos": Vector2(3500,1200), "tier":"outer"},
	"top_inner":  {"pos": Vector2(5500,1000), "tier":"inner"},
	"top_high":   {"pos": Vector2(7500,1200), "tier":"high"},
	"mid_outer":  {"pos": Vector2(6800,3200), "tier":"outer"},
	"mid_inner":  {"pos": Vector2(7600,2400), "tier":"inner"},
	"mid_high":   {"pos": Vector2(8400,1600), "tier":"high"},
	"bot_outer":  {"pos": Vector2(8800,3500), "tier":"outer"},
	"bot_inner":  {"pos": Vector2(9000,5500), "tier":"inner"},
	"bot_high":   {"pos": Vector2(8800,7500), "tier":"high"},
}

# 塔属性配置
const TOWER_CONFIG := {
	"outer": {"hp":3000, "atk":120, "range":700.0, "armor":200},
	"inner": {"hp":4000, "atk":120, "range":700.0, "armor":200},
	"high":  {"hp":5000, "atk":120, "range":700.0, "armor":200},
}

# 蓝方野区
const BLUE_JUNGLE := {
	"red_buff":  Vector2(3000,7000),
	"blue_buff": Vector2(2000,6000),
	"stone":     Vector2(2500,7500),
	"wolves":    Vector2(3200,7800),
	"birds":     Vector2(2800,6500),
	"lizard":    Vector2(3500,7200),
}

# 红方野区
const RED_JUNGLE := {
	"red_buff":  Vector2(7000,3000),
	"blue_buff": Vector2(8000,4000),
	"stone":     Vector2(7500,2500),
	"wolves":    Vector2(6800,2200),
	"birds":     Vector2(7200,3500),
	"lizard":    Vector2(6500,2800),
}

# Boss
const DRAGON_POS  := Vector2(4000,6000)
const BARON_POS   := Vector2(6000,4000)
const CRAB_LEFT   := Vector2(4200,5500)
const CRAB_RIGHT  := Vector2(5800,4500)

# 草丛位置
const BUSHES := [
	Vector2(900,5000), Vector2(900,3500), Vector2(3500,6500), Vector2(6500,3500),
	Vector2(5000,9100), Vector2(7000,9000), Vector2(2500,6800), Vector2(3300,7500),
	Vector2(7500,3200), Vector2(6700,2500), Vector2(4500,5500), Vector2(5500,4500),
]

# 兵线路径
const LANE_PATHS := {
	"mid_blue": [Vector2(1600,8400),Vector2(2400,7600),Vector2(3200,6800),Vector2(4000,6000),Vector2(5000,5000),Vector2(6000,4000),Vector2(6800,3200),Vector2(7600,2400),Vector2(8400,1600),Vector2(9000,1000)],
	"top_blue": [Vector2(1200,8500),Vector2(1000,7000),Vector2(800,5500),Vector2(800,4000),Vector2(800,2500),Vector2(1000,1500),Vector2(2000,800),Vector2(3500,600),Vector2(5000,500),Vector2(6500,600),Vector2(7500,700),Vector2(8500,1000)],
	"bot_blue": [Vector2(1500,8800),Vector2(3000,9200),Vector2(4500,9400),Vector2(6000,9400),Vector2(7500,9200),Vector2(8500,8800),Vector2(9200,7500),Vector2(9400,6000),Vector2(9400,4500),Vector2(9200,3000),Vector2(9000,2000)],
}
