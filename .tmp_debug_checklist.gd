extends SceneTree

func _init() -> void:
	var scene := load("res://tests/test_level_stealth_checklist.tscn") as PackedScene
	if scene == null:
		print("ERR: scene load")
		quit(1)
		return
	var node := scene.instantiate() as Node
	if node == null:
		print("ERR: instantiate")
		quit(1)
		return
	if _has_property(node, "embedded_mode"):
		node.set("embedded_mode", true)
	root.add_child(node)
	await process_frame
	await physics_frame
	if not node.has_method("run_gate_report"):
		print("ERR: run_gate_report missing")
		quit(1)
		return
	var report := await node.call("run_gate_report") as Dictionary
	print(JSON.stringify(report))
	node.queue_free()
	await process_frame
	quit(0)

func _has_property(obj: Object, property_name: String) -> bool:
	for p_variant in obj.get_property_list():
		var p := p_variant as Dictionary
		if String(p.get("name", "")) == property_name:
			return true
	return false
