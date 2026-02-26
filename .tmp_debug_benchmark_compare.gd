extends Node

const LONG_RUN_SCENE := preload("res://tests/test_ai_long_run_stress.tscn")

func _ready() -> void:
	await _run_case("no_force_collision", {
		"seed": 1337,
		"duration_sec": 30.0,
		"enemy_count": 12,
		"fixed_physics_frames": 1800,
		"scene_path": "res://src/levels/stealth_3zone_test.tscn",
		"force_collision_repath": false,
	})
	await _run_case("force_collision", {
		"seed": 1337,
		"duration_sec": 30.0,
		"enemy_count": 12,
		"fixed_physics_frames": 1800,
		"scene_path": "res://src/levels/stealth_3zone_test.tscn",
		"force_collision_repath": true,
	})
	get_tree().quit(0)

func _run_case(label: String, cfg: Dictionary) -> void:
	var node := LONG_RUN_SCENE.instantiate() as Node
	if node == null:
		print("CASE_" + label + "=ERR_INSTANTIATE")
		return
	if _has_property(node, "embedded_mode"):
		node.set("embedded_mode", true)
	add_child(node)
	await get_tree().process_frame
	await get_tree().physics_frame
	if not node.has_method("run_benchmark_contract"):
		print("CASE_" + label + "=ERR_METHOD")
		node.queue_free()
		await get_tree().process_frame
		return
	var report := await node.call("run_benchmark_contract", cfg) as Dictionary
	print("CASE_" + label + "_JSON=" + JSON.stringify(report))
	node.queue_free()
	await get_tree().process_frame

func _has_property(obj: Object, property_name: String) -> bool:
	for p_variant in obj.get_property_list():
		var p := p_variant as Dictionary
		if String(p.get("name", "")) == property_name:
			return true
	return false
