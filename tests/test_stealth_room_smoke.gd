extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const STEALTH_ROOM_SCENE := preload("res://src/levels/stealth_test_room.tscn")
const ROOM_NAV_SYSTEM_SCRIPT := preload("res://src/systems/room_nav_system.gd")
const ENEMY_ALERT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_alert_system.gd")
const ENEMY_SQUAD_SYSTEM_SCRIPT := preload("res://src/systems/enemy_squad_system.gd")
const ENEMY_AGGRO_COORDINATOR_SCRIPT := preload("res://src/systems/enemy_aggro_coordinator.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("STEALTH TEST ROOM SMOKE")
	print("============================================================")

	await _test_scene_bootstrap_and_entities()
	await _test_autoload_reuse_without_local_duplicates()

	_t.summary("STEALTH TEST ROOM SMOKE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_scene_bootstrap_and_entities() -> void:
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := room.get_node_or_null("StealthTestController")
	_t.run_test("stealth room has controller node", controller != null)

	var players := _members_in_group_under("player", room)
	var enemies := _members_in_group_under("enemies", room)
	_t.run_test("stealth room has player", players.size() >= 1)
	_t.run_test("stealth room has enemy", enemies.size() >= 1)
	var enemy := enemies[0] as Enemy if not enemies.is_empty() else null
	var suspicion_ring := enemy.get_node_or_null("SuspicionRing") if enemy else null
	_t.run_test("stealth room enemy has suspicion ring", suspicion_ring != null)
	if suspicion_ring and suspicion_ring.has_method("get_progress"):
		_t.run_test("stealth room ring starts at zero", is_zero_approx(float(suspicion_ring.call("get_progress"))))
	var debug_label := room.get_node_or_null("DebugUI/DebugLabel") as Label
	_t.run_test("stealth room has debug label", debug_label != null)
	if debug_label:
		var text := debug_label.text
		var has_required_fields := (
			text.find("state=") >= 0
			and text.find("intent=") >= 0
			and text.find("LOS=") >= 0
			and text.find("suspicion=") >= 0
			and text.find("vis=") >= 0
			and text.find("dist=") >= 0
			and text.find("last_seen_age=") >= 0
			and text.find("weapons=") >= 0
			and text.find("flashlight_active=") >= 0
			and text.find("in_cone=") >= 0
			and text.find("los_to_player=") >= 0
			and text.find("flashlight_hit=") >= 0
			and text.find("flashlight_bonus_raw=") >= 0
			and text.find("effective_visibility_pre_clamp=") >= 0
			and text.find("effective_visibility_post_clamp=") >= 0
			and text.find("facing_used_for_flashlight=") >= 0
		)
		_t.run_test("stealth overlay exposes required telemetry fields", has_required_fields)

	room.queue_free()
	await get_tree().process_frame


func _test_autoload_reuse_without_local_duplicates() -> void:
	var created_nodes: Array[Node] = []
	_ensure_root_system("RoomNavSystem", ROOM_NAV_SYSTEM_SCRIPT, created_nodes)
	_ensure_root_system("EnemyAlertSystem", ENEMY_ALERT_SYSTEM_SCRIPT, created_nodes)
	_ensure_root_system("EnemySquadSystem", ENEMY_SQUAD_SYSTEM_SCRIPT, created_nodes)
	_ensure_root_system("EnemyAggroCoordinator", ENEMY_AGGRO_COORDINATOR_SCRIPT, created_nodes)

	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := room.get_node_or_null("StealthTestController")
	_t.run_test("controller available in autoload reuse case", controller != null)
	if controller and controller.has_method("debug_get_system_summary"):
		var summary := controller.call("debug_get_system_summary") as Dictionary
		_t.run_test("room nav reuses root singleton", bool(summary.get("room_nav_from_autoload", false)))
		_t.run_test("alert reuses root singleton", bool(summary.get("enemy_alert_from_autoload", false)))
		_t.run_test("squad reuses root singleton", bool(summary.get("enemy_squad_from_autoload", false)))
		_t.run_test("aggro reuses root singleton", bool(summary.get("enemy_aggro_from_autoload", false)))
		_t.run_test("no local RoomNavSystem duplicate", not bool(summary.get("local_room_nav_exists", true)))
		_t.run_test("no local EnemyAlertSystem duplicate", not bool(summary.get("local_enemy_alert_exists", true)))
		_t.run_test("no local EnemySquadSystem duplicate", not bool(summary.get("local_enemy_squad_exists", true)))
		_t.run_test("no local EnemyAggroCoordinator duplicate", not bool(summary.get("local_enemy_aggro_exists", true)))
	else:
		_t.run_test("debug_get_system_summary available", false)

	room.queue_free()
	await get_tree().process_frame

	for node in created_nodes:
		if node and is_instance_valid(node):
			node.queue_free()
	await get_tree().process_frame


func _ensure_root_system(name: String, script: Script, created_nodes: Array[Node]) -> Node:
	var existing := get_tree().root.get_node_or_null(name)
	if existing:
		return existing
	var node := script.new() as Node
	node.name = name
	get_tree().root.add_child(node)
	created_nodes.append(node)
	return node


func _members_in_group_under(group_name: String, ancestor: Node) -> Array[Node]:
	var out: Array[Node] = []
	for member_variant in get_tree().get_nodes_in_group(group_name):
		var member := member_variant as Node
		if member == null:
			continue
		if member == ancestor or ancestor.is_ancestor_of(member):
			out.append(member)
	return out
