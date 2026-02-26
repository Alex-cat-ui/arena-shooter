extends Node

func _ready() -> void:
	var scene := load("res://tests/test_ai_performance_gate.tscn") as PackedScene
	if scene == null:
		print("ERR: scene load")
		get_tree().quit(1)
		return
	var node := scene.instantiate() as Node
	if node == null:
		print("ERR: instantiate")
		get_tree().quit(1)
		return
	if _has_property(node, "embedded_mode"):
		node.set("embedded_mode", true)
	add_child(node)
	await get_tree().process_frame
	await get_tree().physics_frame
	if not node.has_method("run_gate_report"):
		print("ERR: run_gate_report missing")
		get_tree().quit(1)
		return
	var report := await node.call("run_gate_report") as Dictionary
	print("PERF_GATE_REPORT_JSON=" + JSON.stringify(report))
	node.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)

func _has_property(obj: Object, property_name: String) -> bool:
	for p_variant in obj.get_property_list():
		var p := p_variant as Dictionary
		if String(p.get("name", "")) == property_name:
			return true
	return false
