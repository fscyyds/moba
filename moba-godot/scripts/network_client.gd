extends Node

signal state_received(state: Dictionary)
signal event_received(type: String, data: Dictionary)
signal connected_to_server()
signal disconnected_from_server()
signal error_message(msg: String)

@export var server_url: String = "ws://localhost:8080"

var socket := WebSocketPeer.new()
var is_socket_open := false
var my_team: int = -1
var my_hero_id: int = -1
var selected_role: String = ""

func _ready() -> void:
	connect_to_server()

func connect_to_server() -> void:
	var err := socket.connect_to_url(server_url)
	if err != OK:
		error_message.emit("连接服务器失败: " + server_url)

func _process(_delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()
	match state:
		WebSocketPeer.STATE_OPEN:
			if not is_socket_open:
				is_socket_open = true
				connected_to_server.emit()
			while socket.get_available_packet_count() > 0:
				var packet := socket.get_packet()
				var text := packet.get_string_from_utf8()
				_handle_message(text)
		WebSocketPeer.STATE_CLOSED:
			if is_socket_open:
				is_socket_open = false
				disconnected_from_server.emit()

func _handle_message(text: String) -> void:
	var data = JSON.parse_string(text)
	if data == null or not data is Dictionary:
		return
	
	if data.has("type"):
		var type: String = data.type
		if type == "joined":
			my_team = int(data.get("team", -1))
			my_hero_id = int(data.get("id", -1))
			selected_role = data.get("role", "")
			event_received.emit(type, data)
		elif type == "hello":
			# 服务器握手，可以自动加入（如果需要）
			event_received.emit(type, data)
		else:
			event_received.emit(type, data)
	elif data.has("state"):
		# 服务端状态广播
		state_received.emit(data)
	else:
		# 兜底：也当作状态处理
		state_received.emit(data)

func send(data: Dictionary) -> void:
	if is_socket_open:
		socket.send_text(JSON.stringify(data))

func join(role: String) -> void:
	selected_role = role
	send({"type": "join", "role": role})

func move_to(x: float, y: float) -> void:
	send({"type": "move", "x": x, "y": y})

func attack_target(target_id: int) -> void:
	send({"type": "attack", "targetId": target_id})

func cast_skill(slot: String, x: float, y: float, target_id = null) -> void:
	var payload := {
		"type": "skill",
		"slot": slot,
		"x": x,
		"y": y,
		"targetId": target_id
	}
	send(payload)

func start_recall() -> void:
	send({"type": "recall"})

func dev_command(cmd: String) -> void:
	send({"type": cmd})
