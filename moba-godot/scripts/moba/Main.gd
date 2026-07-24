extends Node2D

## MOBA 主场景 — 用代码构建所有实体

var hero_blue: CharacterBody2D
var hero_red: CharacterBody2D

func _ready() -> void:
	_build_heroes()
	_build_towers()

func _build_heroes() -> void:
	hero_blue = _make_hero("HeroBlue", Vector2(2000, 5000), Color(0.3, 0.5, 1.0), "team_blue")
	hero_red = _make_hero("HeroRed", Vector2(8000, 5000), Color(1.0, 0.3, 0.3), "team_red")

func _make_hero(nm: String, pos: Vector2, col: Color, team: String) -> CharacterBody2D:
	var h := CharacterBody2D.new()
	h.name = nm; h.position = pos; h.add_to_group(team); h.add_to_group("heroes")
	add_child(h)
	var s := ColorRect.new(); s.name = "Sprite2D"; s.size = Vector2(32, 32)
	s.position = Vector2(-16, -32); s.color = col; h.add_child(s)
	var cs := CollisionShape2D.new(); cs.shape = CircleShape2D.new()
	cs.shape.radius = 16; h.add_child(cs)
	return h

func _build_towers() -> void:
	var towers_data := [
		{"nm":"BlueMidT1","pos":Vector2(3000,7000),"team":"team_blue","rng":500},
		{"nm":"BlueMidT2","pos":Vector2(2200,7800),"team":"team_blue","rng":500},
		{"nm":"BlueMidT3","pos":Vector2(1400,8600),"team":"team_blue","rng":550},
		{"nm":"BlueCrystal","pos":Vector2(800,9200),"team":"team_blue","rng":600},
		{"nm":"RedMidT1","pos":Vector2(7000,3000),"team":"team_red","rng":500},
		{"nm":"RedMidT2","pos":Vector2(7800,2200),"team":"team_red","rng":500},
		{"nm":"RedMidT3","pos":Vector2(8600,1400),"team":"team_red","rng":550},
		{"nm":"RedCrystal","pos":Vector2(9200,800),"team":"team_red","rng":600},
	]
	for td in towers_data:
		_make_tower(td["nm"], td["pos"], td["team"], td["rng"])

func _make_tower(nm: String, pos: Vector2, team: String, rng: float) -> StaticBody2D:
	var t := StaticBody2D.new()
	t.name = nm; t.position = pos; t.add_to_group(team); t.add_to_group("towers")
	add_child(t)
	var s := ColorRect.new(); s.name = "Sprite2D"
	s.size = Vector2(60, 80); s.position = Vector2(-30, -80)
	s.color = Color(0.5, 0.5, 0.5); t.add_child(s)
	var cs := CollisionShape2D.new(); cs.shape = RectangleShape2D.new()
	cs.shape.size = Vector2(60, 80); t.add_child(cs)
	# 范围圈
	var ring: Node2D = load("res://scripts/moba/range_ring.gd").new()
	ring.name = "RangeRing"; ring.set("range_radius", rng); t.add_child(ring)
	# 标签
	var lb := Label.new(); lb.name = "Label"; lb.add_theme_font_size_override("font_size", 12)
	lb.position = Vector2(-15, -95); lb.text = nm; t.add_child(lb)
	return t

func _physics_process(_delta: float) -> void:
	# 蓝方英雄 WASD 移动
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): dir.y -= 1
	if Input.is_key_pressed(KEY_S): dir.y += 1
	if Input.is_key_pressed(KEY_A): dir.x -= 1
	if Input.is_key_pressed(KEY_D): dir.x += 1
	if hero_blue:
		hero_blue.velocity = dir.normalized() * 350 if dir.length() > 0 else Vector2.ZERO
		hero_blue.move_and_slide()
