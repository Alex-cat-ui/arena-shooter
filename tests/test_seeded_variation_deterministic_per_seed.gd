extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeOwner:
	extends CharacterBody2D

	var entity_id: int = 0

	func _init(p_entity_id: int = 0) -> void:
		entity_id = p_entity_id


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("SEEDED VARIATION DETERMINISTIC PER SEED TEST")
	print("============================================================")

	_test_seeded_pursuit_same_entity_same_seed_identical_sequence()
	_test_seeded_pursuit_different_entity_different_sequence()
	_test_seeded_pursuit_null_owner_fallback()

	_t.summary("SEEDED VARIATION DETERMINISTIC RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_seeded_pursuit_same_entity_same_seed_identical_sequence() -> void:
	var old_layout_seed := int(GameConfig.layout_seed) if GameConfig else 0
	if GameConfig:
		GameConfig.layout_seed = 1337

	var owner_a := FakeOwner.new(7)
	var owner_b := FakeOwner.new(7)
	var pursuit_a: Variant = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner_a, null, 2.0)
	var pursuit_b: Variant = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner_b, null, 2.0)

	var same_seed := int(pursuit_a._rng.seed) == int(pursuit_b._rng.seed)
	var seq_a := _sample_rng(pursuit_a, 5)
	var seq_b := _sample_rng(pursuit_b, 5)

	_t.run_test("same entity + same layout_seed yields same pursuit seed", same_seed)
	_t.run_test("same entity + same layout_seed yields identical rng sequence", _arrays_equal_approx(seq_a, seq_b))

	owner_a.free()
	owner_b.free()
	if GameConfig:
		GameConfig.layout_seed = old_layout_seed


func _test_seeded_pursuit_different_entity_different_sequence() -> void:
	var old_layout_seed := int(GameConfig.layout_seed) if GameConfig else 0
	if GameConfig:
		GameConfig.layout_seed = 1337

	var owner_a := FakeOwner.new(7)
	var owner_b := FakeOwner.new(8)
	var pursuit_a: Variant = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner_a, null, 2.0)
	var pursuit_b: Variant = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(owner_b, null, 2.0)

	_t.run_test(
		"different entity ids yield different pursuit seeds with same layout_seed",
		int(pursuit_a._rng.seed) != int(pursuit_b._rng.seed)
	)

	owner_a.free()
	owner_b.free()
	if GameConfig:
		GameConfig.layout_seed = old_layout_seed


func _test_seeded_pursuit_null_owner_fallback() -> void:
	var pursuit: Variant = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(null, null, 2.0)
	_t.run_test("null owner pursuit seed fallback is golden ratio salt", int(pursuit._compute_pursuit_seed()) == 2654435761)


func _sample_rng(pursuit, count: int) -> Array[float]:
	var out: Array[float] = []
	for _i in range(count):
		out.append(float(pursuit._rng.randf()))
	return out


func _arrays_equal_approx(a: Array[float], b: Array[float]) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if not is_equal_approx(a[i], b[i]):
			return false
	return true
