extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_AGGRO_COORDINATOR_SCRIPT := preload("res://src/systems/enemy_aggro_coordinator.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeEnemy:
	extends Node

	var entity_id: int = 0
	var teammate_calls: int = 0

	func _init(p_entity_id: int, room_id: int) -> void:
		entity_id = p_entity_id
		set_meta("room_id", room_id)
		add_to_group("enemies")

	func apply_teammate_call(_source_enemy_id: int, _source_room_id: int, _call_id: int = -1, _shot_pos: Vector2 = Vector2.ZERO) -> bool:
		teammate_calls += 1
		return true


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("COMM DELAY PREVENTS TELEPATHY TEST")
	print("============================================================")

	await _test_comm_delay_queue_entry_has_fire_at_sec()
	await _test_comm_delay_not_applied_before_fire_at_sec_elapses()
	await _test_comm_delay_applied_after_fire_at_sec()
	await _test_comm_delay_null_enemy_ref_skipped()

	_t.summary("COMM DELAY PREVENTS TELEPATHY RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_comm_delay_queue_entry_has_fire_at_sec() -> void:
	var fixture := _build_fixture()
	var coordinator: Variant = fixture["coordinator"]
	var target := fixture["target"] as FakeEnemy

	coordinator._on_enemy_teammate_call(100, 10, 1, coordinator._now_sec(), Vector2(12.0, 24.0))
	var pending := coordinator.get("_pending_teammate_calls") as Array
	var queued: bool = pending.size() == 1
	var fire_at_ok := false
	if queued:
		var entry := pending[0] as Dictionary
		fire_at_ok = float(entry.get("fire_at_sec", -1.0)) > coordinator._now_sec()

	_t.run_test("comm delay queue entry is created", queued)
	_t.run_test("comm delay queue entry fire_at_sec is in the future", fire_at_ok)
	_t.run_test("teammate call not applied immediately on enqueue", target.teammate_calls == 0)
	await _cleanup_fixture(fixture)


func _test_comm_delay_not_applied_before_fire_at_sec_elapses() -> void:
	var fixture := _build_fixture()
	var coordinator: Variant = fixture["coordinator"]
	var target := fixture["target"] as FakeEnemy

	var pending := coordinator.get("_pending_teammate_calls") as Array
	pending.clear()
	pending.append(_queue_entry_for_target(target, coordinator._now_sec() + 10.0))
	coordinator._drain_pending_teammate_calls()
	var pending_after := coordinator.get("_pending_teammate_calls") as Array

	_t.run_test("future comm delay entry remains queued", pending_after.size() == 1)
	_t.run_test("future comm delay entry does not call target", target.teammate_calls == 0)
	await _cleanup_fixture(fixture)


func _test_comm_delay_applied_after_fire_at_sec() -> void:
	var fixture := _build_fixture()
	var coordinator: Variant = fixture["coordinator"]
	var target := fixture["target"] as FakeEnemy
	coordinator.debug_set_time_override_sec(999.0)
	var pending := coordinator.get("_pending_teammate_calls") as Array
	pending.clear()
	pending.append(_queue_entry_for_target(target, 0.0))

	coordinator._drain_pending_teammate_calls()
	var pending_after := coordinator.get("_pending_teammate_calls") as Array
	var target_last_accept_sec := coordinator.get("_target_last_accept_sec") as Dictionary

	_t.run_test("due comm delay entry is drained", pending_after.is_empty())
	_t.run_test("due comm delay entry invokes apply_teammate_call", target.teammate_calls == 1)
	_t.run_test(
		"target last accept timestamp updated on delayed delivery",
		is_equal_approx(float(target_last_accept_sec.get(target.entity_id, -1.0)), 999.0)
	)
	await _cleanup_fixture(fixture)


func _test_comm_delay_null_enemy_ref_skipped() -> void:
	var fixture := _build_fixture()
	var coordinator: Variant = fixture["coordinator"]
	var temp := FakeEnemy.new(999, 10)
	var dead_ref: WeakRef = weakref(temp)
	temp.free()

	var pending := coordinator.get("_pending_teammate_calls") as Array
	pending.clear()
	pending.append({
		"enemy_ref": dead_ref,
		"source_enemy_id": 100,
		"source_room_id": 10,
		"target_enemy_id": 999,
		"target_room_id": 10,
		"call_id": 5,
		"shot_pos": Vector2.ZERO,
		"fire_at_sec": 0.0,
	})
	coordinator.debug_set_time_override_sec(123.0)
	coordinator._drain_pending_teammate_calls()
	var pending_after := coordinator.get("_pending_teammate_calls") as Array

	_t.run_test("null weakref entry is removed without crash", pending_after.is_empty())
	await _cleanup_fixture(fixture)


func _build_fixture() -> Dictionary:
	var entities := Node2D.new()
	entities.name = "Entities"
	add_child(entities)

	var target := FakeEnemy.new(200, 10)
	entities.add_child(target)

	var coordinator = ENEMY_AGGRO_COORDINATOR_SCRIPT.new()
	add_child(coordinator)
	coordinator.initialize(entities, null, null)
	coordinator.debug_set_time_override_sec(100.0)

	return {
		"entities": entities,
		"target": target,
		"coordinator": coordinator,
	}


func _queue_entry_for_target(target: FakeEnemy, fire_at_sec: float) -> Dictionary:
	return {
		"enemy_ref": weakref(target),
		"source_enemy_id": 100,
		"source_room_id": 10,
		"target_enemy_id": target.entity_id,
		"target_room_id": 10,
		"call_id": 1,
		"shot_pos": Vector2(32.0, 48.0),
		"fire_at_sec": fire_at_sec,
	}


func _cleanup_fixture(fixture: Dictionary) -> void:
	var coordinator := fixture.get("coordinator", null) as Node
	if coordinator:
		coordinator.queue_free()
	var entities := fixture.get("entities", null) as Node
	if entities:
		entities.queue_free()
	await get_tree().process_frame
