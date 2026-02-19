extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const SUSPICION_RING_PRESENTER_SCRIPT := preload("res://src/systems/stealth/suspicion_ring_presenter.gd")
const ENEMY_ALERT_MARKER_PRESENTER_SCRIPT := preload("res://src/systems/enemy_alert_marker_presenter.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class SnapshotParent:
	extends Node2D

	var snapshot: Dictionary = {}

	func get_ui_awareness_snapshot() -> Dictionary:
		return snapshot


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("UI SNAPSHOT DRIVEN TEST")
	print("============================================================")

	await _test_ring_shows_confirm_progress()
	await _test_ring_hidden_in_combat()
	await _test_ring_hidden_in_suspicious()
	_test_marker_hostile_permanent()
	_test_marker_lockdown_no_exclamation()
	await _test_snapshot_fields_complete()

	_t.summary("UI SNAPSHOT DRIVEN RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _spawn_ring_fixture() -> Dictionary:
	var holder := SnapshotParent.new()
	add_child(holder)
	holder.set_meta("awareness_state", "CALM")
	var ring := SUSPICION_RING_PRESENTER_SCRIPT.new() as SuspicionRingPresenter
	holder.add_child(ring)
	await get_tree().process_frame
	ring.set_enabled(true)
	return {
		"holder": holder,
		"ring": ring,
	}


func _test_ring_shows_confirm_progress() -> void:
	var fixture := await _spawn_ring_fixture()
	var holder := fixture.get("holder") as SnapshotParent
	var ring := fixture.get("ring") as SuspicionRingPresenter
	holder.snapshot = {
		"state": ENEMY_AWARENESS_SYSTEM_SCRIPT.State.SUSPICIOUS,
		"confirm01": 0.5,
	}
	ring.update_from_snapshot(holder.snapshot)
	await get_tree().process_frame
	_t.run_test("ring_shows_confirm_progress", is_equal_approx(ring.get_progress(), 0.5) and ring.visible)
	holder.queue_free()
	await get_tree().process_frame


func _test_ring_hidden_in_combat() -> void:
	var fixture := await _spawn_ring_fixture()
	var holder := fixture.get("holder") as SnapshotParent
	var ring := fixture.get("ring") as SuspicionRingPresenter
	holder.snapshot = {
		"state": ENEMY_AWARENESS_SYSTEM_SCRIPT.State.COMBAT,
		"confirm01": 0.8,
	}
	holder.set_meta("awareness_state", "COMBAT")
	ring.update_from_snapshot(holder.snapshot)
	await get_tree().process_frame
	_t.run_test("ring_hidden_in_combat", not ring.visible)
	holder.queue_free()
	await get_tree().process_frame


func _test_ring_hidden_in_suspicious() -> void:
	var fixture := await _spawn_ring_fixture()
	var holder := fixture.get("holder") as SnapshotParent
	var ring := fixture.get("ring") as SuspicionRingPresenter
	holder.snapshot = {
		"state": ENEMY_AWARENESS_SYSTEM_SCRIPT.State.SUSPICIOUS,
		"confirm01": 0.3,
	}
	holder.set_meta("awareness_state", "SUSPICIOUS")
	ring.update_from_snapshot(holder.snapshot)
	await get_tree().process_frame
	_t.run_test("ring_hidden_in_suspicious", not ring.visible)
	holder.queue_free()
	await get_tree().process_frame


func _test_marker_hostile_permanent() -> void:
	var sprite := Sprite2D.new()
	add_child(sprite)
	var presenter := ENEMY_ALERT_MARKER_PRESENTER_SCRIPT.new()
	presenter.setup(sprite)

	var hostile_snap := {
		"state": ENEMY_AWARENESS_SYSTEM_SCRIPT.State.ALERT,
		"hostile_contact": true,
		"hostile_damaged": false,
		"zone_state": 0,
	}
	presenter.update_from_snapshot(hostile_snap, sprite)
	var first_ok := sprite.visible and sprite.texture != null

	hostile_snap["state"] = ENEMY_AWARENESS_SYSTEM_SCRIPT.State.CALM
	presenter.update_from_snapshot(hostile_snap, sprite)
	var second_ok := sprite.visible and sprite.texture != null

	_t.run_test("marker_hostile_permanent", first_ok and second_ok)
	sprite.queue_free()


func _test_marker_lockdown_no_exclamation() -> void:
	var sprite := Sprite2D.new()
	add_child(sprite)
	var presenter := ENEMY_ALERT_MARKER_PRESENTER_SCRIPT.new()
	presenter.setup(sprite)

	var lockdown_snap := {
		"state": ENEMY_AWARENESS_SYSTEM_SCRIPT.State.CALM,
		"hostile_contact": false,
		"hostile_damaged": false,
		"zone_state": 2,
	}
	presenter.update_from_snapshot(lockdown_snap, sprite)
	_t.run_test("marker_lockdown_no_exclamation", not sprite.visible and sprite.texture == null)
	sprite.queue_free()


func _test_snapshot_fields_complete() -> void:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	add_child(enemy)
	await get_tree().process_frame
	enemy.initialize(96001, "zombie")
	await get_tree().process_frame

	var snap := enemy.get_ui_awareness_snapshot() as Dictionary
	var has_all := (
		snap.has("state")
		and snap.has("combat_phase")
		and snap.has("confirm01")
		and snap.has("hostile_contact")
		and snap.has("hostile_damaged")
		and snap.has("zone_state")
	)
	_t.run_test("snapshot_fields_complete", has_all)

	enemy.queue_free()
	await get_tree().process_frame
