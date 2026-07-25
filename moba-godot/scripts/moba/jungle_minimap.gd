extends Control
class_name JungleMinimap

## 小地图野怪状态显示

@onready var mgr: JungleManager = get_node_or_null("/root/Main/JungleManager")
@onready var dots: Array[ColorRect] = []

const DOT_SIZE := 4.0
const MAP_W := 200.0; const MAP_H := 200.0
const GAME_W := 10000.0; const GAME_H := 10000.0


func _ready() -> void:
	if not mgr: return
	for camp in mgr.camps:
		var dot := ColorRect.new()
		dot.size = Vector2(DOT_SIZE, DOT_SIZE)
		dot.color = Color.YELLOW
		var x := (camp.spawn_pos.x / GAME_W) * MAP_W
		var y := (camp.spawn_pos.y / GAME_H) * MAP_H
		dot.position = Vector2(x, y)
		add_child(dot)
		dots.append(dot)

func _process(_delta: float) -> void:
	if not mgr: return
	for i in range(min(dots.size(), mgr.camps.size())):
		var camp := mgr.camps[i]
		var dot := dots[i]
		if not camp.is_active:
			var t := camp.get_node_or_null("RespawnTimer") as Timer
			if t and t.time_left < 5.0:
				dot.color = Color.WHITE if fmod(Time.get_ticks_msec()*0.001, 0.4) > 0.2 else Color.GRAY
			else:
				dot.color = Color.GRAY
		else:
			dot.color = Color.YELLOW
