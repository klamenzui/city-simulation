extends SceneTree

# Screenshot tool so the assistant can visually inspect the running scene.
#
# IMPORTANT: run WITHOUT --headless (it needs the real renderer; --headless only has the
# dummy renderer and produces a blank image):
#
#   "<godot_console.exe>" --path . --script res://tools/codex_screenshot.gd -- \
#       --out=res://.ai/screenshots/latest.png --pos=40,35,40 --look=20,2,10 --size=1024x576
#
# All args after `--` are optional:
#   --out=<res:// or absolute path>   where to save the PNG (default below)
#   --pos=x,y,z                       camera world position
#   --look=x,y,z                      point the camera looks at
#   --size=WxH                        render resolution
#   --settle=N                        extra render frames before capture (default 6)
#
# With no --pos/--look it frames an angled view on the park (city_park group), which is the
# current area of interest. Because it runs the real scene, the capture reflects the actual
# in-game look (matte pass, park tint, sky, etc.).

const DEFAULT_OUT := "res://.ai/screenshots/latest.png"

func _initialize() -> void:
	var args := _parse_args()
	var size: Vector2i = args.get("size", Vector2i(1024, 576))
	DisplayServer.window_set_size(size)

	var main_scene := load("res://Main.tscn")
	if main_scene == null:
		push_error("codex_screenshot: cannot load Main.tscn")
		quit(1)
		return
	var main: Node = main_scene.instantiate()
	root.add_child(main)

	# Let bootstrap + physics + async textures settle.
	for _i in range(10):
		await physics_frame
	for _i in range(int(args.get("settle", 6))):
		await process_frame

	# Main.tscn boots to the menu; hide all 2D UI and neutralize existing cameras so we
	# capture the 3D world itself.
	_hide_ui(main)
	for node in _all_nodes(main):
		if node is Camera3D:
			(node as Camera3D).current = false

	var focus := _park_aabb(main)
	var center := focus.position + focus.size * 0.5
	var extent: float = maxf(maxf(focus.size.x, focus.size.z), 4.0)
	var dist := extent * 1.4 + 6.0
	var look: Vector3 = args.get("look", center + Vector3(0.0, 1.5, 0.0))
	var pos: Vector3 = args.get("pos", center + Vector3(0.72, 0.7, 0.72) * dist)

	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.far = 6000.0
	root.add_child(cam)
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	cam.make_current()

	# Freeze menu/game logic so nothing re-claims the camera before the capture.
	# (This script IS the SceneTree, so set the property directly.)
	paused = true

	for _i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var image := root.get_texture().get_image()
	var out_path: String = args.get("out", DEFAULT_OUT)
	var abs_path := ProjectSettings.globalize_path(out_path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var err := image.save_png(out_path)
	if err != OK:
		push_error("codex_screenshot: save_png failed err=%d" % err)
		quit(1)
		return
	print("SCREENSHOT_SAVED path=", abs_path, " size=", size, " pos=", pos, " look=", look)
	quit(0)

# AABB enclosing the park tiles, so the default shot auto-frames the park.
func _park_aabb(main: Node) -> AABB:
	var tree := main.get_tree()
	var aabb := AABB(Vector3(-10, 0, -10), Vector3(20, 1, 20))
	if tree == null:
		return aabb
	var has := false
	for node in tree.get_nodes_in_group("city_park"):
		if node is Node3D:
			var p := (node as Node3D).global_position
			if not has:
				aabb = AABB(p, Vector3.ZERO)
				has = true
			else:
				aabb = aabb.expand(p)
	return aabb

func _hide_ui(root_node: Node) -> void:
	for node in _all_nodes(root_node):
		if node is Control:
			(node as Control).visible = false

func _all_nodes(root_node: Node) -> Array:
	var out: Array = [root_node]
	for child in root_node.get_children():
		out.append_array(_all_nodes(child))
	return out

func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			parsed["out"] = arg.substr(6)
		elif arg.begins_with("--pos="):
			parsed["pos"] = _to_vec3(arg.substr(6))
		elif arg.begins_with("--look="):
			parsed["look"] = _to_vec3(arg.substr(7))
		elif arg.begins_with("--settle="):
			parsed["settle"] = int(arg.substr(9))
		elif arg.begins_with("--size="):
			var parts := arg.substr(7).split("x")
			if parts.size() == 2:
				parsed["size"] = Vector2i(int(parts[0]), int(parts[1]))
	return parsed

func _to_vec3(text: String) -> Vector3:
	var parts := text.split(",")
	if parts.size() == 3:
		return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	return Vector3.ZERO
