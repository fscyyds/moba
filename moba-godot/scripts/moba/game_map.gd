extends Node2D
class_name GameMap

## 地图构建器 — 从 MapData 生成所有地图元素

@onready var ground_layer: Node2D = $GroundLayer
@onready var building_layer: Node2D = $BuildingLayer
@onready var unit_layer: Node2D = $UnitLayer

func _ready() -> void:
	ground_layer.scale = Vector2(1.0, 0.5)
	building_layer.scale = Vector2(1.0, 0.5)
	unit_layer.y_sort_enabled = true

	_build_ground()
	_build_bases()
	_build_towers()
	_build_bushes()
	_build_jungle()
	_build_boss_pits()
	print("[GameMap] 地图构建完成")
	_print_coords()

func _build_ground() -> void:
	# 草地 - 使用 MapData 纹理或纯色
	var grass := ColorRect.new(); grass.name = "Grass"
	grass.size = Vector2(MapData.MAP_W, MapData.MAP_H)
	grass.color = Color(0.18, 0.38, 0.18)
	ground_layer.add_child(grass)

	# 河流对角线
	var river := _draw_river()
	ground_layer.add_child(river)

	# 三路道路
	for lane in ["top","mid","bot"]:
		for team in ["blue","red"]:
			var path := _get_lane_path(lane, team)
			_draw_road(path)

func _draw_river() -> ColorRect:
	var r := ColorRect.new(); r.name = "River"
	r.color = Color(0.15, 0.45, 0.55, 0.5)
	# 简化为对角线矩形带
	var rw := 400.0
	# 从(8000,2000)到(2000,8000)绘制
	return r

func _draw_road(points: Array) -> void:
	if points.size() < 2: return
	var road := Line2D.new()
	road.width = 300
	road.default_color = Color(0.58, 0.47, 0.35)
	for p in points: road.add_point(p)
	ground_layer.add_child(road)

func _build_bases() -> void:
	# 蓝方水晶
	var bc := _make_crystal(MapData.BLUE_NEXUS, Color(0.2, 0.4, 1.0), "team_blue")
	building_layer.add_child(bc)
	# 红方水晶
	var rc := _make_crystal(MapData.RED_NEXUS, Color(1.0, 0.2, 0.2), "team_red")
	building_layer.add_child(rc)
	# 泉水
	_make_fountain(MapData.BLUE_FOUNTAIN, Color(0.3, 0.6, 1.0), "team_blue")
	_make_fountain(MapData.RED_FOUNTAIN, Color(1.0, 0.3, 0.3), "team_red")

func _make_crystal(pos: Vector2, col: Color, team: String) -> StaticBody2D:
	var c := StaticBody2D.new(); c.name = "Crystal_" + team; c.position = pos
	c.add_to_group(team); c.add_to_group("crystals")
	var sp := ColorRect.new(); sp.size = Vector2(80, 80); sp.position = Vector2(-40, -80)
	sp.color = col; c.add_child(sp)
	var cs := CollisionShape2D.new(); cs.shape = CircleShape2D.new()
	cs.shape.radius = 40; c.add_child(cs)
	return c

func _make_fountain(pos: Vector2, col: Color, team: String) -> void:
	var f := Area2D.new(); f.name = "Fountain_" + team; f.position = pos
	f.add_to_group(team)
	var cs := CollisionShape2D.new(); cs.shape = CircleShape2D.new()
	cs.shape.radius = 500; f.add_child(cs)
	building_layer.add_child(f)

func _build_towers() -> void:
	for k in MapData.BLUE_TOWERS:
		var d := MapData.BLUE_TOWERS[k]
		_make_tower(d["pos"], "team_blue", d["tier"])
	for k in MapData.RED_TOWERS:
		var d := MapData.RED_TOWERS[k]
		_make_tower(d["pos"], "team_red", d["tier"])

func _make_tower(pos: Vector2, team: String, tier: String) -> void:
	var t := StaticBody2D.new(); t.name = "Tower_" + team + "_" + tier; t.position = pos
	t.add_to_group(team); t.add_to_group("towers")
	var sp := ColorRect.new(); sp.size = Vector2(50, 70); sp.position = Vector2(-25, -70)
	sp.color = Color(0.6,0.5,0.4) if team == "team_blue" else Color(0.5,0.3,0.3)
	t.add_child(sp)
	var cs := CollisionShape2D.new(); cs.shape = RectangleShape2D.new()
	cs.shape.size = Vector2(50, 70); t.add_child(cs)
	building_layer.add_child(t)

func _build_bushes() -> void:
	for pos in MapData.BUSHES:
		var b := Area2D.new(); b.name = "Bush"; b.position = pos
		b.add_to_group("bushes")
		var cs := CollisionShape2D.new(); cs.shape = CircleShape2D.new()
		cs.shape.radius = 150; b.add_child(cs)
		ground_layer.add_child(b)

func _build_jungle() -> void:
	for k in MapData.BLUE_JUNGLE:
		_make_camp_marker(MapData.BLUE_JUNGLE[k], k)
	for k in MapData.RED_JUNGLE:
		_make_camp_marker(MapData.RED_JUNGLE[k], k)

func _make_camp_marker(pos: Vector2, name: String) -> void:
	var m := Marker2D.new(); m.name = "Camp_" + name; m.position = pos
	add_child(m)

func _build_boss_pits() -> void:
	_make_pit(MapData.DRAGON_POS, 400, "Dragon")
	_make_pit(MapData.BARON_POS, 500, "Baron")
	# 河蟹
	_make_camp_marker(MapData.CRAB_LEFT, "CrabLeft")
	_make_camp_marker(MapData.CRAB_RIGHT, "CrabRight")

func _make_pit(pos: Vector2, radius: float, name: String) -> void:
	var p := Area2D.new(); p.name = name + "Pit"; p.position = pos
	p.add_to_group("boss_pits")
	var cs := CollisionShape2D.new(); cs.shape = CircleShape2D.new()
	cs.shape.radius = radius; p.add_child(cs)
	building_layer.add_child(p)

func _get_lane_path(lane: String, team: String) -> Array:
	var k := lane + "_" + team
	return MapData.LANE_PATHS.get(k, [])

func _print_coords() -> void:
	print("=== 地图坐标一览 ===")
	print("蓝水晶:", MapData.BLUE_NEXUS)
	print("红水晶:", MapData.RED_NEXUS)
	print("暴君:", MapData.DRAGON_POS)
	print("主宰:", MapData.BARON_POS)
	print("草丛数:", MapData.BUSHES.size())
	print("蓝塔数:", MapData.BLUE_TOWERS.size())
	print("红塔数:", MapData.RED_TOWERS.size())
