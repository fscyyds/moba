extends StaticBody2D
class_name Crystal

## 水晶/基地 — 摧毁即游戏结束

@export var team: String = "team_blue"
@export var max_hp: int = 10000
var current_hp: int = 10000
@onready var sprite: Sprite2D = $Sprite2D
var is_dead: bool = false


func _ready() -> void:
	add_to_group(team); add_to_group("crystals")
	current_hp = max_hp

func _process(_delta: float) -> void:
	if sprite and not is_dead:
		var glow := 0.5 + 0.3 * sin(Time.get_ticks_msec() * 0.003)
		sprite.modulate.a = glow

func take_damage(dmg: int) -> void:
	if is_dead: return
	current_hp = max(current_hp - dmg, 0)
	if current_hp <= 0: _die()

func _die() -> void:
	is_dead = true
	var winner := "team_red" if team == "team_blue" else "team_blue"
	print("[Crystal] ", team, " 水晶被摧毁! ", winner, " 胜利!")
	if Engine.has_singleton("GameManager"):
		Engine.get_singleton("GameManager").game_over(winner)
