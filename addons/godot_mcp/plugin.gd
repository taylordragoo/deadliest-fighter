@tool
extends EditorPlugin
## Godot MCP Plugin
## Connects to multiple godot-mcp-server instances via WebSocket.
## Supports concurrent connections on ports 6505-6510 so multiple
## AI assistants (Claude, Codex, etc.) can share one Godot editor.

const MCPClientScript = preload("res://addons/godot_mcp/mcp_client.gd")
const ToolExecutorScript = preload("res://addons/godot_mcp/tool_executor.gd")

const PORT_RANGE_START := 6505
const PORT_RANGE_END := 6510  # inclusive

var _clients: Array = []  # Array of MCPClient nodes
var _tool_executor: Node  # ToolExecutor (shared)
var _status_label: Label

func _enter_tree() -> void:
	print("[Godot MCP] Plugin loading (multi-port mode: %d-%d)..." % [PORT_RANGE_START, PORT_RANGE_END])

	# Create shared tool executor
	_tool_executor = ToolExecutorScript.new()
	_tool_executor.name = "ToolExecutor"
	add_child(_tool_executor)
	_tool_executor.set_editor_plugin(self)

	# Create one MCP client per port
	for port in range(PORT_RANGE_START, PORT_RANGE_END + 1):
		var client: Node = MCPClientScript.new()
		client.name = "MCPClient_%d" % port
		add_child(client)

		client.connected.connect(_on_client_connected.bind(port))
		client.disconnected.connect(_on_client_disconnected.bind(port))
		client.tool_requested.connect(_on_tool_requested.bind(client))

		client.connect_to_server("ws://localhost:%d" % port)
		_clients.append(client)

	# Add status indicator to editor
	_setup_status_indicator()

	print("[Godot MCP] Plugin loaded - scanning ports %d-%d..." % [PORT_RANGE_START, PORT_RANGE_END])

func _exit_tree() -> void:
	print("[Godot MCP] Plugin unloading...")

	for client in _clients:
		if client:
			client.disconnect_from_server()
			client.queue_free()
	_clients.clear()

	if _tool_executor:
		_tool_executor.queue_free()

	if _status_label:
		remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, _status_label)
		_status_label.queue_free()

	print("[Godot MCP] Plugin unloaded")

func _setup_status_indicator() -> void:
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 12)
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, _status_label)
	_update_status_label()

func _get_connected_ports() -> Array:
	var ports: Array = []
	for client in _clients:
		if client and client.is_connected_to_server():
			var port := int(client.server_url.split(":")[-1])
			ports.append(port)
	return ports

func _update_status_label() -> void:
	if not _status_label:
		return
	var ports := _get_connected_ports()
	if ports.is_empty():
		_status_label.text = "MCP: No connections"
		_status_label.add_theme_color_override("font_color", Color.RED)
	else:
		var port_strs: Array = []
		for p in ports:
			port_strs.append(str(p))
		_status_label.text = "MCP: %d conn (%s)" % [ports.size(), ", ".join(port_strs)]
		_status_label.add_theme_color_override("font_color", Color.GREEN)

func _on_client_connected(port: int) -> void:
	print("[Godot MCP] Connected on port %d" % port)
	_update_status_label()

func _on_client_disconnected(port: int) -> void:
	print("[Godot MCP] Disconnected from port %d" % port)
	_update_status_label()

func _on_tool_requested(request_id: String, tool_name: String, args: Dictionary, client: Node) -> void:
	print("[Godot MCP] Executing tool: %s (port: %s)" % [tool_name, client.server_url])

	var result: Dictionary = _tool_executor.execute_tool(tool_name, args)

	var success: bool = result.get("ok", false)
	if success:
		result.erase("ok")
		client.send_tool_result(request_id, true, result)
	else:
		var error: String = result.get("error", "Unknown error")
		client.send_tool_result(request_id, false, null, error)
