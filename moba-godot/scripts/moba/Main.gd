extends Node2D

## MOBA 主场景 — 2.5D 伪透视：地面压缩 + 角色正常

var hero_blue: CharacterBody2D
var hero_red: CharacterBody2D
@onready var ground_layer: Node2D = $GroundLayer
@onready var building_layer: Node2D = $BuildingLayer
@onready var unit_layer: Node2D = $UnitLayer

var minions_container: Node2D
var wave_timer: float = 0.0
var wave_count: int = 0

func _ready() -> void:
	# 地面和建筑：Y轴压缩 → 看起来像斜的
	ground_layer.scale = Vector2(1.0, 0.5)
	building_layer.scale = Vector2(1.0, 0.5)
	# 角色层不压缩
	unit_layer.y_sort_enabled = true  # 下方遮挡上方

	minions_container = Node2D.new(); minions_container.name = "Minions"
	unit_layer.add_child(minions_container)

	_build_towers()
	_build_heroes()
	_build_ground()

func _build_ground() -> void:
	# 草地背景
	var grass := ColorRect.new(); grass.name = "Grass"
	grass.size = Vector2(10000, 10000)
	grass.color = Color(0.15, 0.35, 0.15)
	ground_layer.add_child(grass)
	# 上路
	var road_top := ColorRect.new(); road_top.name = "RoadTop"
	road_top.size = Vector2(9200, 600); road_top.position = Vector2(400, 6700)
	road_top.color = Color(0.35, 0.3, 0.22)
	ground_layer.add_child(road_top)
	# 下路
	var road_bot := ColorRect.new(); road_bot.name = "RoadBot"
	road_bot.size = Vector2(9200, 600); road_bot.position = Vector2(400, 2700)
	road_bot.color = Color(0.35, 0.3, 0.22)
	ground_layer.add_child(road_bot)

func _build_towers() -> void:
	var data := [
		{"nm":"BlueMidT1","pos":Vector2(3000,7000),"team":"team_blue","rng":400},
		{"nm":"BlueMidT2","pos":Vector2(2200,7800),"team":"team_blue","rng":450},
		{"nm":"BlueMidT3","pos":Vector2(1400,8600),"team":"team_blue","rng":500},
		{"nm":"BlueCrystal","pos":Vector2(800,9200),"team":"team_blue","rng":800},
		{"nm":"RedMidT1","pos":Vector2(7000,3000),"team":"team_red","rng":400},
		{"nm":"RedMidT2","pos":Vector2(7800,2200),"team":"team_red","rng":450},
		{"nm":"RedMidT3","pos":Vector2(8600,1400),"team":"team_red","rng":500},
		{"nm":"RedCrystal","pos":Vector2(9200,800),"team":"team_red","rng":800},
	]
	for d in data:
		var t := StaticBody2D.new()
		t.name = d["nm"]; t.position = d["pos"]; t.add_to_group(d["team"]); t.add_to_group("towers")
		building_layer.add_child(t)
		var sp := ColorRect.new(); sp.size = Vector2(60,80); sp.position = Vector2(-30,-80)
		sp.color = Color(0.4,0.4,0.4) if d["team"] == "team_blue" else Color(0.5,0.3,0.3)
		t.add_child(sp)
		var cs := CollisionShape2D.new(); cs.shape = RectangleShape2D.new()
		cs.shape.size = Vector2(60,80); t.add_child(cs)
		var ring: Node2D = load("res://scripts/moba/range_ring.gd").new()
		ring.name = "RangeRing"; ring.set("range_radius", d["rng"]); t.add_child(ring)

func _build_heroes() -> void:
	hero_blue = _make_hero("HeroBlue", Vector2(2000,5000), Color(0.3,0.5,1.0), "team_blue")
	hero_red = _make_hero("HeroRed", Vector2(8000,5000), Color(1.0,0.3,0.3), "team_red")

func _make_hero(nm: String, pos: Vector2, col: Color, team: String) -> CharacterBody2D:
	var h := CharacterBody2D.new(); h.name = nm; h.position = pos
	h.add_to_group(team); h.add_to_group("heroes"); unit_layer.add_child(h)
	var sp := ColorRect.new(); sp.size = Vector2(32,32); sp.position = Vector2(-16,-32)
	sp.color = col; h.add_child(sp)
	var cs := CollisionShape2D.new(); cs.shape = CircleShape2D.new()
	cs.shape.radius = 16; h.add_child(cs)
	var atk_script := load("res://scripts/moba/basic_attack.gd")
	var atk := Node.new(); atk.name = "BasicAttack"; atk.set_script(atk_script)
	atk.set("is_ranged", team == "team_red"); h.add_child(atk)
	return h

func _physics_process(delta: float) -> void:
	wave_timer += delta
	if wave_timer >= 30:
		wave_timer -= 30; _spawn_wave()
	# 蓝方移动
	if hero_blue:
		var dir := Vector2.ZERO
		var s := Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_R)
		if not s:
			if Input.is_key_pressed(KEY_W): dir.y -= 1
			if Input.is_key_pressed(KEY_S): dir.y += 1
			if Input.is_key_pressed(KEY_A): dir.x -= 1
			if Input.is_key_pressed(KEY_D): dir.x += 1
		hero_blue.velocity = Vector2(dir.x, dir.y * 2).normalized() * 350 if dir.length() > 0 else Vector2.ZERO
		hero_blue.move_and_slide()
	if Input.is_key_pressed(KEY_J) or Input.is_key_pressed(KEY_SPACE):
		_hero_attack(hero_blue)
	for m in minions_container.get_children():
		if m is CharacterBody2D: _minion_ai(m, delta)

func _spawn_wave() -> void:
	wave_count += 1
	for lane_y in [3000, 7000]:
		for i in range(3):
			var t := "melee" if i < 2 else "ranged"
			var bm := _make_minion(Color.LIGHT_BLUE, "team_blue", t)
			bm.position = Vector2(200, lane_y + (i-1)*40); minions_container.add_child(bm)
			var rm := _make_minion(Color.LIGHT_CORAL, "team_red", t)
			rm.position = Vector2(9800, lane_y + (i-1)*40); minions_container.add_child(rm)

func _make_minion(col: Color, team: String, _mtype: String) -> CharacterBody2D:
	var m := CharacterBody2D.new(); m.name = "Minion"; m.add_to_group(team); m.add_to_group("minions")
	var sp := ColorRect.new(); sp.size = Vector2(16,16); sp.position = Vector2(-8,-16)
	sp.color = col; m.add_child(sp)
	var cs := CollisionShape2D.new(); cs.shape = CircleShape2D.new()
	cs.shape.radius = 8; m.add_child(cs)
	m.set_meta("dir", 1 if team == "team_blue" else -1)
	m.set_meta("hp", 500); m.set_meta("atk", 30); m.set_meta("spd", 100)
	m.set_meta("cd", 0.0); m.set_meta("target", null)
	return m

func _minion_ai(m: CharacterBody2D, delta: float) -> void:
	var hp: int = m.get_meta("hp", 500)
	if hp <= 0: m.queue_free(); return
	var spd: float = m.get_meta("spd", 100)
	var dir: int = m.get_meta("dir", 1)
	var cd: float = m.get_meta("cd", 0.0)
	cd -= delta; m.set_meta("cd", max(0.0, cd))
	var target: Node2D = m.get_meta("target")
	if not target or not is_instance_valid(target):
		target = _find_minion_target(m); m.set_meta("target", target)
	if target and is_instance_valid(target):
		var d := m.global_position.distance_to(target.global_position)
		if d < 60:
			if cd <= 0:
				var t_hp := target.get_meta("hp", 500) - m.get_meta("atk", 30)
				target.set_meta("hp", t_hp); m.set_meta("cd", 1.0)
		else:
			m.position += (target.global_position - m.global_position).normalized() * spd * delta
	else:
		m.position.x += dir * spd * delta

func _find_minion_target(m: CharacterBody2D) -> Node2D:
	var mt := ""; for g in m.get_groups(): if g.begins_with("team_"): mt = g; break
	var best: Node2D = null; var bd: float = 300
	for mm in minions_container.get_children():
		if mm == m or mm.is_in_group(mt): continue
		var d := m.global_position.distance_to(mm.global_position)
		if d < bd: bd = d; best = mm
	return best

func _hero_attack(h: CharacterBody2D) -> void:
	var atk := h.get_node_or_null("BasicAttack") as Node
	if atk and atk.has_method("start_attack"): atk.start_attack()
