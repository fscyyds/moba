extends Node

## 玩家输入控制器
## 负责：英雄选择、WASD移动、鼠标普攻、QWER技能、D回城、T传送

var selected_role: String = ""
var game_started: bool = false
var last_move_send: int = 0

func _ready() -> void:
	NetworkClient.connected_to_server.connect(_on_connected)
	NetworkClient.event_received.connect(_on_event)
	NetworkClient.state_received.connect(_on_state)

func _on_connected() -> void:
	print("[Godot] 已连接服务器")

func _on_event(type: String, data: Dictionary) -> void:
	if type == "start":
		game_started = true
		print("[Godot] 对局开始!")
	elif type == "reset":
		game_started = false
		selected_role = ""
	elif type == "joined":
		print("[Godot] 加入对局 team=", data.get("team"), " role=", data.get("role"))

func _on_state(_state: Dictionary) -> void:
	pass

func _input(event: InputEvent) -> void:
	# 英雄选择（对局未开始）
	if not game_started:
		if event.is_action_pressed("skill_q"):
			join_as("warrior")
		elif event.is_action_pressed("skill_w"):
			join_as("mage")
		elif event.is_action_pressed("skill_e"):
			join_as("archer")
		return

	# 技能释放
	if event.is_action_pressed("skill_q"):
		_cast_skill("q")
	if event.is_action_pressed("skill_w"):
		_cast_skill("w")
	if event.is_action_pressed("skill_e"):
		_cast_skill("e")
	if event.is_action_pressed("skill_r"):
		_cast_skill("r")
	if event.is_action_pressed("recall"):
		NetworkClient.start_recall()
	if event.is_action_pressed("basic_attack"):
		_basic_attack()
	if event.is_action_pressed("move_click"):
		_move_to_click()

func join_as(role: String) -> void:
	if selected_role != "":
		return
	selected_role = role
	NetworkClient.join(role)
	print("[Godot] 选择英雄: ", role)

func _cast_skill(slot: String) -> void:
	if not game_started:
		return
	var me := GameManager.get_my_hero()
	if me.is_empty() or me.get("dead", false):
		return
	var target_world := GameManager.screen_to_world(get_viewport().get_mouse_position())
	NetworkClient.cast_skill(slot, target_world.x, target_world.z, null)

func _basic_attack() -> void:
	if not game_started:
		return
	var me := GameManager.get_my_hero()
	if me.is_empty() or me.get("dead", false):
		return
	# 向服务器发送攻击，服务端自己找最近目标
	NetworkClient.send({"type": "attack", "targetId": -1})

func _move_to_click() -> void:
	if not game_started:
		return
	var target_world := GameManager.screen_to_world(get_viewport().get_mouse_position())
	NetworkClient.move_to(target_world.x, target_world.z)
	print("[Godot] 移动到 ", target_world.x, ", ", target_world.z)

func _process(_delta: float) -> void:
	if not game_started:
		return
	
	var me := GameManager.get_my_hero()
	if me.is_empty() or me.get("dead", false):
		return
	
	# WASD 持续移动（每 50ms 发送一次）
	var dx := Input.get_axis("move_left", "move_right")
	var dy := Input.get_axis("move_up", "move_down")
	if dx != 0 or dy != 0:
		var now := Time.get_ticks_msec()
		if now - last_move_send > 50:
			last_move_send = now
			var x := float(me.get("x", 0)) + dx * 200
			var y := float(me.get("y", 0)) + dy * 200
			NetworkClient.move_to(x, y)
