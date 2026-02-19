extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")

class FakePerception:
	extends RefCounted
	var hit_on_call: int = 1
	var _calls: int = 0

	func ray_hits_player(_origin: Vector2, _direction: Vector2, _max_range: float, _exclude: Array[RID]) -> bool:
		_calls += 1
		return _calls == hit_on_call


var embedded_mode: bool = false
var _t := TestHelpers.new()
var _captured_contacts: Array[Dictionary] = []


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ENEMY DAMAGE EXACTLY 1HP PER SUCCESSFUL SHOT TEST")
	print("============================================================")

	await _test_enemy_damage_is_exactly_1hp_per_successful_shot()

	_t.summary("ENEMY DAMAGE EXACTLY 1HP PER SUCCESSFUL SHOT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_enemy_damage_is_exactly_1hp_per_successful_shot() -> void:
	if EventBus and EventBus.has_signal("enemy_contact") and not EventBus.enemy_contact.is_connected(_on_enemy_contact):
		EventBus.enemy_contact.connect(_on_enemy_contact)
	_captured_contacts.clear()

	var world := Node2D.new()
	add_child(world)
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(7604, "zombie")
	enemy.set_physics_process(false)

	var fake_perception := FakePerception.new()
	enemy.set("_perception", fake_perception)
	enemy.call("_fire_enemy_shotgun", Vector2.ZERO, Vector2.RIGHT)
	await get_tree().process_frame
	if EventBus and EventBus.has_method("_process"):
		EventBus.call("_process", 0.016)
	await get_tree().process_frame

	var one_event := _captured_contacts.size() == 1
	var damage_one := one_event and int(_captured_contacts[0].get("damage", -1)) == 1
	var source_shotgun := one_event and String(_captured_contacts[0].get("enemy_type", "")) == "enemy_shotgun"

	_t.run_test("successful shot-level hit emits one contact event", one_event)
	_t.run_test("successful shot-level hit applies exactly 1 HP", damage_one)
	_t.run_test("event source stays enemy_shotgun", source_shotgun)

	if EventBus and EventBus.has_signal("enemy_contact") and EventBus.enemy_contact.is_connected(_on_enemy_contact):
		EventBus.enemy_contact.disconnect(_on_enemy_contact)
	world.queue_free()
	await get_tree().process_frame


func _on_enemy_contact(_enemy_id: int, enemy_type: String, damage: int) -> void:
	_captured_contacts.append({
		"enemy_type": enemy_type,
		"damage": damage,
	})
