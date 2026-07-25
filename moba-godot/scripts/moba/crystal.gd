extends StaticBody2D
class_name Crystal

## 水晶 — 高HP，摧毁=游戏结束

@export var max_hp: int = 15000
@export var team: String = "team_blue"
var current_hp: int = 15000
var is_dead: bool = false


func _ready() -> void:
	add_to_group(team); add_to_group("crystals")
	current_hp = max_hp

func _process(_delta: float) -> void:
	if not is_dead:
		var glow := 0.6 + 0.3 * sin(Time.get_ticks_msec() * 0.003)
		modulate.a = glow

func take_damage(dmg: int) -> void:
	if is_dead: return
	current_hp = max(current_hp - dmg, 0)
	if current_hp <= 0: _destroy()

func _destroy() -> void:
	is_dead = true
	var other := "team_red" if team == "team_blue" else "team_blue"
	print("[Crystal] ", team, " 水晶被摧毁! ", other, " 胜利!")
	get_tree().paused = true  # 游戏结束
