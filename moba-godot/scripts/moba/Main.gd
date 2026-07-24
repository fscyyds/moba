extends Node2D
class_name Main

## 主场景管理器 — 连接摇杆和攻击键到英雄

@onready var hero_blue: Hero = $HeroBlue
@onready var hero_red: Hero = $HeroRed
@onready var joystick: Joystick = $UI/Joystick
@onready var attack_btn: AttackButton = $UI/AttackButton
@onready var wave_mgr: MinionWaveManager = $MinionWaveManager
@onready var tower_mgr: TowerManager = $TowerManager


func _ready() -> void:
	if joystick and hero_blue:
		joystick.direction_changed.connect(hero_blue.set_move_direction)
	if attack_btn and hero_blue:
		attack_btn.attack_pressed.connect(hero_blue.do_attack)
	if wave_mgr:
		wave_mgr.is_active = true
