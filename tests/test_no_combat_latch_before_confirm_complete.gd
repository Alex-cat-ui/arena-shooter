extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const STEALTH_ROOM_SCENE := preload("res://src/levels/stealth_test_room.tscn")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

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
	print("NO COMBAT LATCH BEFORE CONFIRM COMPLETE TEST")
	print("============================================================")

	await _test_room_stays_below_combat_before_confirm_complete()

	_t.summary("NO COMBAT LATCH BEFORE CONFIRM COMPLETE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_room_stays_below_combat_before_confirm_complete() -> void:
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := room.get_node_or_null("StealthTestController")
	var enemy := _first_member_in_group_under("enemies", room) as Enemy
	var player := room.get_node_or_null("Entities/Player") as CharacterBody2D
	var alert_system: Variant = controller.get("_enemy_alert_system") if controller else null

	_t.run_test("no-latch: controller exists", controller != null)
	_t.run_test("no-latch: enemy exists", enemy != null)
	_t.run_test("no-latch: player exists", player != null)
	_t.run_test("no-latch: alert system exists", alert_system != null)
	if controller == null or enemy == null or player == null or alert_system == null:
		room.queue_free()
		await get_tree().process_frame
		return

	if RuntimeState:
		RuntimeState.is_frozen = false
	player.global_position = enemy.global_position + Vector2(80.0, 0.0)
	player.velocity = Vector2.ZERO
	if enemy.has_method("set_physics_process"):
		enemy.set_physics_process(false)
	var pursuit_variant: Variant = enemy.get("_pursuit")
	if pursuit_variant != null:
		var pursuit_obj := pursuit_variant as Object
		if pursuit_obj:
			if pursuit_obj.has_method("set_speed_tiles"):
				pursuit_obj.call("set_speed_tiles", 0.0)
			var face_dir := (player.global_position - enemy.global_position).normalized()
			pursuit_obj.set("facing_dir", face_dir)
			pursuit_obj.set("_target_facing_dir", face_dir)

	for _i in range(49):
		_sync_enemy_facing(enemy, player.global_position)
		enemy.runtime_budget_tick(0.1)
		await get_tree().process_frame

	var room_id := int(enemy.get_meta("room_id", -1))
	if room_id < 0 and enemy.has_method("_resolve_room_id_for_events"):
		room_id = int(enemy.call("_resolve_room_id_for_events"))
	var state_before := String(enemy.get_meta("awareness_state", "CALM"))
	var room_effective_before := int(alert_system.get_room_effective_level(room_id)) if room_id >= 0 and alert_system.has_method("get_room_effective_level") else ENEMY_ALERT_LEVELS_SCRIPT.CALM

	_t.run_test(
		"no-latch: before 5s enemy is below COMBAT",
		state_before != "COMBAT"
	)
	_t.run_test(
		"no-latch: room effective is below COMBAT before 5s",
		room_effective_before < ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
	)

	var reached_combat := false
	for _i in range(24):
		_sync_enemy_facing(enemy, player.global_position)
		enemy.runtime_budget_tick(0.1)
		await get_tree().process_frame
		if String(enemy.get_meta("awareness_state", "CALM")) == "COMBAT":
			reached_combat = true
			break

	var room_effective_after := int(alert_system.get_room_effective_level(room_id)) if room_id >= 0 and alert_system.has_method("get_room_effective_level") else ENEMY_ALERT_LEVELS_SCRIPT.CALM
	_t.run_test("no-latch: confirm completion eventually reaches COMBAT", reached_combat)
	_t.run_test("no-latch: room latch reaches COMBAT only after confirm", room_effective_after == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT)

	room.queue_free()
	await get_tree().process_frame


func _first_member_in_group_under(group_name: String, ancestor: Node) -> Node:
	for member_variant in get_tree().get_nodes_in_group(group_name):
		var member := member_variant as Node
		if member == null:
			continue
		if member == ancestor or ancestor.is_ancestor_of(member):
			return member
	return null


func _sync_enemy_facing(enemy: Enemy, target_pos: Vector2) -> void:
	var pursuit_variant: Variant = enemy.get("_pursuit")
	if pursuit_variant == null:
		return
	var pursuit_obj := pursuit_variant as Object
	if pursuit_obj == null:
		return
	var face_dir := (target_pos - enemy.global_position).normalized()
	if face_dir.length_squared() <= 0.0001:
		return
	pursuit_obj.set("facing_dir", face_dir)
	pursuit_obj.set("_target_facing_dir", face_dir)
