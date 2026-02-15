## test_room_enemy_spawner.gd
## Verifies static room enemy spawn quotas and spacing constraints.
extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")

const SEED_COUNT := 20
const ARENA := Rect2(-1100, -1100, 2200, 2200)
const TEST_MISSION := 3
# MIN_SPACING_PX=100 ~= half of practical enemy collision diameter budget.
const MIN_SPACING_PX := 100.0

const SPAWNER_SCRIPT := preload("res://src/systems/room_enemy_spawner.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")


func _room_expected_count(layout, room_id: int) -> int:
	var size_class := str(layout._room_size_class(room_id))
	match size_class:
		"LARGE":
			return 3
		"MEDIUM":
			return 2
		_:
			return 1


func _street_entry_room_id(layout) -> int:
	if not ("north_exit_rect" in layout):
		return -1
	var gate := layout.north_exit_rect as Rect2
	if gate == Rect2():
		return -1
	if not layout.has_method("_room_id_at_point"):
		return -1
	var probe := gate.get_center() + Vector2(0.0, 24.0)
	return int(layout._room_id_at_point(probe))


func _ready() -> void:
	print("=" .repeat(60))
	print("ROOM ENEMY SPAWNER TEST: %d seeds" % SEED_COUNT)
	print("=" .repeat(60))

	var failures := 0
	var total_spawned := 0
	for seed_id in range(1, SEED_COUNT + 1):
		var built := TestHelpers.create_layout(self, seed_id, ARENA, TEST_MISSION)
		var layout = built["layout"]
		var walls := built["walls"] as Node2D
		var debug := built["debug"] as Node2D
		var player := built["player"] as CharacterBody2D
		if not layout.valid:
			print("[FAIL] seed=%d layout invalid" % seed_id)
			failures += 1
			walls.queue_free()
			debug.queue_free()
			player.queue_free()
			await get_tree().process_frame
			continue

		var entities := Node2D.new()
		add_child(entities)
		var spawner = SPAWNER_SCRIPT.new()
		add_child(spawner)
		spawner.initialize(ENEMY_SCENE, entities)
		spawner.rebuild_for_layout(layout)
		var street_room_id := _street_entry_room_id(layout)

		var room_points: Dictionary = {}
		for i in range(layout.rooms.size()):
			room_points[i] = []
		for child in entities.get_children():
			if not child.is_in_group("room_static_enemy"):
				continue
			var room_id := int(child.get_meta("room_id", -1))
			if room_id < 0 or room_id >= layout.rooms.size():
				print("[FAIL] seed=%d spawned enemy with invalid room_id=%d" % [seed_id, room_id])
				failures += 1
				continue
			(room_points[room_id] as Array).append((child as Node2D).position)
			total_spawned += 1

		for room_id in range(layout.rooms.size()):
			if room_id in layout._void_ids:
				continue
			if room_id == int(layout.player_room_id):
				continue
			if room_id == street_room_id:
				continue
			if layout._is_closet_room(room_id):
				continue
			if bool((layout.rooms[room_id] as Dictionary).get("is_corridor", false)):
				continue
			var points := room_points[room_id] as Array
			var expected := _room_expected_count(layout, room_id)
			if points.size() != expected:
				print("[FAIL] seed=%d room=%d expected=%d actual=%d class=%s" % [
					seed_id, room_id, expected, points.size(), str(layout._room_size_class(room_id))
				])
				failures += 1

			for p_variant in points:
				var p := p_variant as Vector2
				if TestHelpers.room_id_at_point(layout, p) != room_id:
					print("[FAIL] seed=%d room=%d point outside room: %s" % [seed_id, room_id, str(p)])
					failures += 1

			for i in range(points.size()):
				var a := points[i] as Vector2
				for j in range(i + 1, points.size()):
					var b := points[j] as Vector2
					if a.distance_to(b) < MIN_SPACING_PX - 0.5:
						print("[FAIL] seed=%d room=%d spacing %.1f < %.1f" % [
							seed_id, room_id, a.distance_to(b), MIN_SPACING_PX
						])
						failures += 1

		spawner.queue_free()
		entities.queue_free()
		walls.queue_free()
		debug.queue_free()
		player.queue_free()
		await get_tree().process_frame

	print("Total spawned enemies: %d" % total_spawned)
	print("Failures: %d" % failures)
	print("=" .repeat(60))
	get_tree().quit(1 if failures > 0 else 0)
