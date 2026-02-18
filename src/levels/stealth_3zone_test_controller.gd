extends Node

const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const STEALTH_TEST_CONFIG_SCRIPT := preload("res://src/levels/stealth_test_config.gd")
const SHADOW_ZONE_SCRIPT := preload("res://src/systems/stealth/shadow_zone.gd")
const DOOR_CONTROLLER_SCRIPT := preload("res://src/systems/door_controller_v3.gd")
const LAYOUT_DOOR_SYSTEM_SCRIPT := preload("res://src/systems/layout_door_system.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")
const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const GAME_OVER_SCENE := preload("res://scenes/ui/game_over.tscn")
const LEVEL_COMPLETE_SCENE := preload("res://scenes/ui/level_complete.tscn")
const MAIN_MENU_SCENE_PATH := "res://scenes/ui/main_menu.tscn"
const TEST_LEVEL_SCENE_PATH := "res://src/levels/stealth_3zone_test.tscn"

const WALL_THICKNESS := 16.0
const PROP_SIZE := Vector2(100.0, 100.0)

const ROOM_A1 := Rect2(0.0, 0.0, 640.0, 480.0)
const ROOM_A2 := Rect2(640.0, 0.0, 640.0, 480.0)
const ROOM_B := Rect2(0.0, 568.0, 800.0, 480.0)
const ROOM_C := Rect2(900.0, 568.0, 800.0, 600.0)

const CHOKE_AB := Rect2(270.0, 480.0, 128.0, 88.0)
const CHOKE_BC := Rect2(800.0, 680.0, 100.0, 128.0)
const DOOR_A1A2_OPENING := Rect2(632.0, 200.0, 16.0, 80.0)

const ZONE_CONFIG := [
	{"id": 0, "name": "A", "rooms": [0, 1]},
	{"id": 1, "name": "B", "rooms": [2]},
	{"id": 2, "name": "C", "rooms": [3]},
]
const ZONE_EDGES := [[0, 1], [1, 2]]

const ENEMY_SPAWNS := [
	{"spawn_name": "SpawnA1", "pos": Vector2(320.0, 240.0), "room": 0, "type": "zombie"},
	{"spawn_name": "SpawnA2", "pos": Vector2(960.0, 240.0), "room": 1, "type": "zombie"},
	{"spawn_name": "SpawnB", "pos": Vector2(400.0, 820.0), "room": 2, "type": "zombie"},
	{"spawn_name": "SpawnC1", "pos": Vector2(1300.0, 780.0), "room": 3, "type": "zombie"},
	{"spawn_name": "SpawnC2", "pos": Vector2(1300.0, 1000.0), "room": 3, "type": "zombie"},
]

const SHADOW_DEFS := [
	{"name": "ShadowA1", "pos": Vector2(120.0, 240.0), "size": Vector2(220.0, 180.0)},
	{"name": "ShadowA2", "pos": Vector2(800.0, 100.0), "size": Vector2(180.0, 140.0)},
	{"name": "ShadowB", "pos": Vector2(200.0, 700.0), "size": Vector2(220.0, 180.0)},
	{"name": "ShadowC1", "pos": Vector2(1000.0, 700.0), "size": Vector2(160.0, 200.0)},
	{"name": "ShadowC2", "pos": Vector2(1500.0, 900.0), "size": Vector2(200.0, 180.0)},
]

const PLAYER_SPAWN_FALLBACK := Vector2(100.0, 240.0)
const FLASHLIGHT_ANGLE_DEG := 55.0
const FLASHLIGHT_DISTANCE_PX := 1000.0
const FLASHLIGHT_BONUS := 2.5
const DOOR_INTERACT_RADIUS_PX := 20.0
const DOOR_KICK_RADIUS_PX := 40.0
const GEOMETRY_COLOR := Color(0.24, 0.26, 0.30, 1.0)
const PROP_COLOR := Color(0.72, 0.58, 0.38, 1.0)
const FLOOR_COLORS := [
	Color(0.11, 0.12, 0.15, 1.0),
	Color(0.12, 0.13, 0.16, 1.0),
	Color(0.10, 0.12, 0.14, 1.0),
	Color(0.11, 0.13, 0.15, 1.0),
]

class ThreeZoneLayout:
	extends RefCounted

	var valid: bool = true
	var rooms: Array = []
	var doors: Array = []
	var _door_adj: Dictionary = {}
	var _door_map: Dictionary = {}
	var _void_ids: Array = []
	var player_room_id: int = 0
	var _navigation_obstacle_rects: Array[Rect2] = []

	func _init(
		room_rects: Array,
		door_a1a2: Rect2,
		choke_ab: Rect2,
		choke_bc: Rect2,
		navigation_obstacle_rects: Array[Rect2] = []
	) -> void:
		rooms = []
		for room_id in range(room_rects.size()):
			var rect := room_rects[room_id] as Rect2
			rooms.append({
				"id": room_id,
				"rects": [rect],
				"center": rect.get_center(),
				"is_corridor": false,
			})
		doors = [door_a1a2, choke_ab, choke_bc]
		_door_adj = {
			0: [1, 2],
			1: [0],
			2: [0, 3],
			3: [2],
		}
		_door_map = {
			_rect_key(door_a1a2): [0, 1],
			_rect_key(choke_ab): [0, 2],
			_rect_key(choke_bc): [2, 3],
		}
		_void_ids = []
		player_room_id = 0
		_navigation_obstacle_rects = navigation_obstacle_rects.duplicate()

	func _room_id_at_point(point: Vector2) -> int:
		for room_id in range(rooms.size()):
			var room := rooms[room_id] as Dictionary
			for rect_variant in (room.get("rects", []) as Array):
				var rect := rect_variant as Rect2
				if rect.grow(0.25).has_point(point):
					return room_id
		return -1

	func _door_adjacent_room_ids(door: Rect2) -> Array:
		var key := _rect_key(door)
		if _door_map.has(key):
			return (_door_map[key] as Array).duplicate()
		return []

	func _door_wall_thickness() -> float:
		return WALL_THICKNESS

	func _navigation_obstacles() -> Array[Rect2]:
		return _navigation_obstacle_rects.duplicate()

	func _rect_key(rect: Rect2) -> String:
		return "%.2f:%.2f:%.2f:%.2f" % [
			rect.position.x,
			rect.position.y,
			rect.size.x,
			rect.size.y,
		]


var _layout: ThreeZoneLayout = null
var _suspicion_profile: Dictionary = {}
var _test_values: Dictionary = {}
var _enemy_id_counter: int = 15000
var _spawned_enemies: Array[Enemy] = []
var _door_a1a2: Node2D = null
var _door_system: Node = null
var _debug_accum: float = 0.0
var _pause_menu: Control = null
var _state_overlay: Control = null
var _main_menu_transition_pending: bool = false
var _level_restart_pending: bool = false
var _prop_obstacle_rects: Array[Rect2] = []

@onready var _level_root := get_parent() as Node2D
@onready var _navigation_root := _level_root.get_node("Navigation") as Node2D
@onready var _geometry_root := _level_root.get_node("Geometry") as Node2D
@onready var _doors_root := _level_root.get_node("Doors") as Node2D
@onready var _shadow_areas_root := _level_root.get_node("ShadowAreas") as Node2D
@onready var _entities_root := _level_root.get_node("Entities") as Node2D
@onready var _spawns_root := _level_root.get_node("Spawns") as Node2D
@onready var _systems_root := _level_root.get_node("Systems") as Node
@onready var _projectiles_root := _level_root.get_node("Projectiles") as Node2D
@onready var _camera := _level_root.get_node_or_null("Camera2D") as Camera2D
@onready var _debug_layer := _level_root.get_node_or_null("DebugUI") as CanvasLayer
@onready var _debug_label := _level_root.get_node_or_null("DebugUI/DebugLabel") as Label
@onready var _hint_label := _level_root.get_node_or_null("DebugUI/HintLabel") as Label

@onready var _player := _entities_root.get_node("Player") as CharacterBody2D
@onready var _zone_director := _systems_root.get_node("ZoneDirector")
@onready var _navigation_service := _systems_root.get_node("NavigationService")
@onready var _enemy_alert_system := _systems_root.get_node("EnemyAlertSystem")
@onready var _enemy_squad_system := _systems_root.get_node("EnemySquadSystem")
@onready var _enemy_aggro_coordinator := _systems_root.get_node("EnemyAggroCoordinator")
@onready var _combat_system := _systems_root.get_node("CombatSystem")
@onready var _projectile_system := _systems_root.get_node("ProjectileSystem")


func _ready() -> void:
	if RuntimeState:
		RuntimeState.is_frozen = false
		RuntimeState.player_visibility_mul = 1.0

	_test_values = STEALTH_TEST_CONFIG_SCRIPT.values()
	_suspicion_profile = STEALTH_TEST_CONFIG_SCRIPT.suspicion_profile()
	_ensure_playing_state_for_test_level()

	_build_geometry()
	_build_shadows()
	_build_door()
	_setup_door_system()
	_setup_player()
	_setup_layout_and_systems()
	_spawn_enemies()
	_update_hint_text()
	_refresh_debug_label(true)


func _unhandled_input(event: InputEvent) -> void:
	if event == null:
		return
	if event.is_action_pressed("pause", true):
		if StateManager and StateManager.current_state in [GameState.State.GAME_OVER, GameState.State.LEVEL_COMPLETE]:
			StateManager.change_state(GameState.State.MAIN_MENU)
		else:
			_toggle_pause_state()
		return
	if _door_system == null or _player == null:
		return
	if event.is_action_pressed("door_interact", true):
		if _door_system.has_method("interact_toggle"):
			_door_system.interact_toggle(_player.global_position, DOOR_INTERACT_RADIUS_PX)
	if event.is_action_pressed("door_kick", true):
		if _door_system.has_method("kick"):
			_door_system.kick(_player.global_position, DOOR_KICK_RADIUS_PX)


func _process(delta: float) -> void:
	_sync_pause_menu_from_state()
	if _main_menu_transition_pending:
		_try_open_main_menu_scene()
		return
	if _level_restart_pending:
		_try_restart_test_scene()
		return
	if RuntimeState and RuntimeState.is_frozen:
		return
	if _combat_system and _combat_system.has_method("update"):
		_combat_system.update(delta)
	if _zone_director and _zone_director.has_method("update"):
		_zone_director.update(delta)

	if _camera and _player and is_instance_valid(_player):
		_camera.global_position = _player.global_position

	_debug_accum += maxf(delta, 0.0)
	if _debug_accum >= 0.1:
		_debug_accum = 0.0
		_refresh_debug_label(false)


func _ensure_playing_state_for_test_level() -> void:
	if StateManager == null:
		return
	if StateManager.is_playing() or StateManager.is_paused():
		return
	StateManager.change_state(GameState.State.LEVEL_SETUP)
	StateManager.change_state(GameState.State.PLAYING)


func _toggle_pause_state() -> void:
	if StateManager == null:
		return
	if StateManager.is_playing():
		StateManager.change_state(GameState.State.PAUSED)
	elif StateManager.is_paused():
		StateManager.change_state(GameState.State.PLAYING)
	_sync_pause_menu_from_state()


func _sync_pause_menu_from_state() -> void:
	if StateManager == null:
		return
	var state := StateManager.current_state
	if state == GameState.State.MAIN_MENU:
		_main_menu_transition_pending = true
		_level_restart_pending = false
		_hide_pause_menu()
		_hide_state_overlay()
		return
	if state == GameState.State.LEVEL_SETUP:
		_main_menu_transition_pending = false
		_level_restart_pending = true
		_hide_pause_menu()
		_hide_state_overlay()
		return
	_level_restart_pending = false
	if state == GameState.State.GAME_OVER:
		_show_state_overlay(GAME_OVER_SCENE, "GameOver")
		_hide_pause_menu()
		return
	if state == GameState.State.LEVEL_COMPLETE:
		_show_state_overlay(LEVEL_COMPLETE_SCENE, "LevelComplete")
		_hide_pause_menu()
		return
	_hide_state_overlay()
	var should_show := StateManager.is_paused()
	if should_show:
		_show_pause_menu()
	else:
		_hide_pause_menu()


func _show_pause_menu() -> void:
	if _pause_menu and is_instance_valid(_pause_menu):
		_pause_menu.visible = true
		return
	if PAUSE_MENU_SCENE == null:
		return
	var menu := PAUSE_MENU_SCENE.instantiate() as Control
	if menu == null:
		return
	menu.name = "PauseMenu"
	_level_root.add_child(menu)
	_pause_menu = menu


func _hide_pause_menu() -> void:
	if _pause_menu and is_instance_valid(_pause_menu):
		_pause_menu.queue_free()
	_pause_menu = null


func _show_state_overlay(scene: PackedScene, node_name: String) -> void:
	if scene == null:
		return
	if _state_overlay and is_instance_valid(_state_overlay):
		if _state_overlay.name == node_name:
			_state_overlay.visible = true
			return
		_state_overlay.queue_free()
		_state_overlay = null
	var menu := scene.instantiate() as Control
	if menu == null:
		return
	menu.name = node_name
	_level_root.add_child(menu)
	_state_overlay = menu


func _hide_state_overlay() -> void:
	if _state_overlay and is_instance_valid(_state_overlay):
		_state_overlay.queue_free()
	_state_overlay = null


func _try_open_main_menu_scene() -> void:
	_main_menu_transition_pending = false
	if not ResourceLoader.exists(MAIN_MENU_SCENE_PATH):
		return
	var tree := get_tree()
	if tree == null:
		return
	tree.change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _try_restart_test_scene() -> void:
	_level_restart_pending = false
	if not ResourceLoader.exists(TEST_LEVEL_SCENE_PATH):
		return
	var tree := get_tree()
	if tree == null:
		return
	tree.change_scene_to_file(TEST_LEVEL_SCENE_PATH)


func debug_get_room_rects() -> Array[Rect2]:
	return [ROOM_A1, ROOM_A2, ROOM_B, ROOM_C]


func debug_get_choke_rect(name: String) -> Rect2:
	match name:
		"AB":
			return CHOKE_AB
		"BC":
			return CHOKE_BC
		_:
			return Rect2()


func debug_get_wall_thickness() -> float:
	return WALL_THICKNESS


func _setup_layout_and_systems() -> void:
	_layout = ThreeZoneLayout.new(
		[ROOM_A1, ROOM_A2, ROOM_B, ROOM_C],
		DOOR_A1A2_OPENING,
		CHOKE_AB,
		CHOKE_BC,
		_prop_obstacle_rects
	)
	if _door_system:
		_layout.set_meta("door_system", _door_system)

	if _navigation_service and _navigation_service.has_method("initialize"):
		_navigation_service.initialize(_layout, _entities_root, _player)
	if _navigation_service and _navigation_service.has_method("build_from_layout"):
		_navigation_service.build_from_layout(_layout, _navigation_root)

	if _enemy_alert_system and _enemy_alert_system.has_method("initialize"):
		_enemy_alert_system.initialize(_navigation_service)

	if _enemy_squad_system and _enemy_squad_system.has_method("initialize"):
		_enemy_squad_system.initialize(_player, _navigation_service, _entities_root)

	if _navigation_service and _navigation_service.has_method("bind_tactical_systems"):
		_navigation_service.bind_tactical_systems(_enemy_alert_system, _enemy_squad_system)

	if _zone_director and _zone_director.has_method("initialize"):
		var zone_config_typed: Array[Dictionary] = []
		for zone_variant in ZONE_CONFIG:
			zone_config_typed.append((zone_variant as Dictionary).duplicate(true))
		var zone_edges_typed: Array[Array] = []
		for edge_variant in ZONE_EDGES:
			zone_edges_typed.append((edge_variant as Array).duplicate())
		_zone_director.initialize(zone_config_typed, zone_edges_typed, _enemy_alert_system)

	if _navigation_service and _navigation_service.has_method("set_zone_director"):
		_navigation_service.set_zone_director(_zone_director)

	if _enemy_aggro_coordinator and _enemy_aggro_coordinator.has_method("initialize"):
		_enemy_aggro_coordinator.initialize(_entities_root, _navigation_service, _player)
	if _enemy_aggro_coordinator and _enemy_aggro_coordinator.has_method("set_zone_director"):
		_enemy_aggro_coordinator.set_zone_director(_zone_director)

	if _projectile_system and "projectiles_container" in _projectile_system:
		_projectile_system.projectiles_container = _projectiles_root

	if _combat_system and "player_node" in _combat_system:
		_combat_system.player_node = _player

	if _player and "projectile_system" in _player:
		_player.projectile_system = _projectile_system


func _setup_player() -> void:
	if not _player:
		return
	_player.global_position = _player_spawn_position()
	_player.velocity = Vector2.ZERO
	if not _player.is_in_group("player"):
		_player.add_to_group("player")
	if (_player.collision_mask & 1) == 0:
		_player.collision_mask |= 1
	if RuntimeState:
		RuntimeState.player_pos = Vector3(_player.global_position.x, _player.global_position.y, 0.0)


func _player_spawn_position() -> Vector2:
	var node := _spawns_root.get_node_or_null("PlayerSpawn") as Node2D
	if node:
		return node.global_position
	return PLAYER_SPAWN_FALLBACK


func _spawn_enemies() -> void:
	for child_variant in _entities_root.get_children():
		var child := child_variant as Node
		if child == null or not child.is_in_group("enemies"):
			continue
		child.queue_free()
	_spawned_enemies.clear()

	for spawn_variant in ENEMY_SPAWNS:
		var spawn := spawn_variant as Dictionary
		var enemy := ENEMY_SCENE.instantiate() as Enemy
		if enemy == null:
			continue

		enemy.position = _spawn_position(spawn)
		_entities_root.add_child(enemy)

		enemy.initialize(_enemy_id_counter, String(spawn.get("type", "zombie")))
		enemy.set_runtime_budget_scheduler_enabled(false)
		enemy.configure_stealth_test_flashlight(_flashlight_angle_deg(), _flashlight_distance_px(), _flashlight_bonus())
		enemy.enable_suspicion_test_profile(_suspicion_profile)
		enemy.set_flashlight_hit_for_detection(false)
		if _door_system:
			enemy.set_meta("door_system", _door_system)
		if _navigation_service:
			_navigation_service.call("_configure_enemy", enemy)

		_spawned_enemies.append(enemy)
		_enemy_id_counter += 1


func _spawn_position(spawn: Dictionary) -> Vector2:
	var node_name := String(spawn.get("spawn_name", ""))
	if node_name != "":
		var node := _spawns_root.get_node_or_null(node_name) as Node2D
		if node:
			return node.global_position
	return spawn.get("pos", Vector2.ZERO) as Vector2


func _flashlight_angle_deg() -> float:
	return float(_test_values.get("flashlight_angle_deg", FLASHLIGHT_ANGLE_DEG))


func _flashlight_distance_px() -> float:
	return float(_test_values.get("flashlight_distance_px", FLASHLIGHT_DISTANCE_PX))


func _flashlight_bonus() -> float:
	return float(_test_values.get("flashlight_bonus", FLASHLIGHT_BONUS))


func _setup_door_system() -> void:
	if _door_system and is_instance_valid(_door_system):
		_door_system.queue_free()
	_door_system = LAYOUT_DOOR_SYSTEM_SCRIPT.new()
	_door_system.name = "LayoutDoorSystem"
	add_child(_door_system)
	if _door_system.has_method("initialize"):
		_door_system.initialize(_doors_root)


func _build_door() -> void:
	_clear_children(_doors_root)
	_door_a1a2 = DOOR_CONTROLLER_SCRIPT.new()
	_door_a1a2.name = "DoorA1A2"
	_doors_root.add_child(_door_a1a2)
	_door_a1a2.configure_from_opening(DOOR_A1A2_OPENING, WALL_THICKNESS)
	_door_a1a2.reset_to_closed()


func _build_shadows() -> void:
	_clear_children(_shadow_areas_root)
	for shadow_variant in SHADOW_DEFS:
		var shadow := shadow_variant as Dictionary
		var zone := SHADOW_ZONE_SCRIPT.new() as Area2D
		if zone == null:
			continue
		zone.name = String(shadow.get("name", "ShadowZone"))
		zone.position = shadow.get("pos", Vector2.ZERO) as Vector2
		zone.collision_layer = 0
		zone.collision_mask = 1
		zone.shadow_multiplier = float(_test_values.get("shadow_multiplier_default", 0.35))

		var shape_node := CollisionShape2D.new()
		shape_node.name = "CollisionShape2D"
		var shape := RectangleShape2D.new()
		shape.size = shadow.get("size", Vector2(120.0, 80.0)) as Vector2
		shape_node.shape = shape
		zone.add_child(shape_node)

		var visual := Polygon2D.new()
		visual.name = "ShadowVisual"
		visual.color = Color(0.04, 0.06, 0.08, 0.58)
		visual.polygon = _rect_polygon(shape.size)
		zone.add_child(visual)

		_shadow_areas_root.add_child(zone)


func _build_geometry() -> void:
	_clear_children(_geometry_root)
	_prop_obstacle_rects.clear()

	var floor_root := Node2D.new()
	floor_root.name = "FloorVisual"
	_geometry_root.add_child(floor_root)
	_add_floor(floor_root, ROOM_A1, FLOOR_COLORS[0], "FloorA1")
	_add_floor(floor_root, ROOM_A2, FLOOR_COLORS[1], "FloorA2")
	_add_floor(floor_root, ROOM_B, FLOOR_COLORS[2], "FloorB")
	_add_floor(floor_root, ROOM_C, FLOOR_COLORS[3], "FloorC")
	_add_floor(floor_root, CHOKE_AB, FLOOR_COLORS[2], "FloorChokeAB")
	_add_floor(floor_root, CHOKE_BC, FLOOR_COLORS[3], "FloorChokeBC")

	_build_wall_body(_geometry_root, "WallsA1", [
		_h_segment(ROOM_A1.position.x, ROOM_A1.end.x, ROOM_A1.position.y),
		_v_segment(ROOM_A1.position.x, ROOM_A1.position.y, ROOM_A1.end.y),
		_h_segment(ROOM_A1.position.x, CHOKE_AB.position.x, ROOM_A1.end.y),
		_h_segment(CHOKE_AB.end.x, ROOM_A1.end.x, ROOM_A1.end.y),
		_v_segment(ROOM_A1.end.x, ROOM_A1.position.y, DOOR_A1A2_OPENING.position.y),
		_v_segment(ROOM_A1.end.x, DOOR_A1A2_OPENING.end.y, ROOM_A1.end.y),
	])

	_build_wall_body(_geometry_root, "WallsA2", [
		_h_segment(ROOM_A2.position.x, ROOM_A2.end.x, ROOM_A2.position.y),
		_h_segment(ROOM_A2.position.x, ROOM_A2.end.x, ROOM_A2.end.y),
		_v_segment(ROOM_A2.end.x, ROOM_A2.position.y, ROOM_A2.end.y),
	])

	_build_wall_body(_geometry_root, "WallsB", [
		_h_segment(ROOM_B.position.x, CHOKE_AB.position.x, ROOM_B.position.y),
		_h_segment(CHOKE_AB.end.x, ROOM_B.end.x, ROOM_B.position.y),
		_v_segment(ROOM_B.position.x, ROOM_B.position.y, ROOM_B.end.y),
		_h_segment(ROOM_B.position.x, ROOM_B.end.x, ROOM_B.end.y),
		_v_segment(ROOM_B.end.x, ROOM_B.position.y, CHOKE_BC.position.y),
		_v_segment(ROOM_B.end.x, CHOKE_BC.end.y, ROOM_B.end.y),
	])

	_build_wall_body(_geometry_root, "WallsC", [
		_h_segment(ROOM_C.position.x, ROOM_C.end.x, ROOM_C.position.y),
		_h_segment(ROOM_C.position.x, ROOM_C.end.x, ROOM_C.end.y),
		_v_segment(ROOM_C.end.x, ROOM_C.position.y, ROOM_C.end.y),
		_v_segment(ROOM_C.position.x, ROOM_C.position.y, CHOKE_BC.position.y),
		_v_segment(ROOM_C.position.x, CHOKE_BC.end.y, ROOM_C.end.y),
	])

	_build_wall_body(_geometry_root, "ChokeAB", [
		_v_segment(CHOKE_AB.position.x, CHOKE_AB.position.y, CHOKE_AB.end.y),
		_v_segment(CHOKE_AB.end.x, CHOKE_AB.position.y, CHOKE_AB.end.y),
	])

	_build_wall_body(_geometry_root, "ChokeBC", [
		_h_segment(CHOKE_BC.position.x, CHOKE_BC.end.x, CHOKE_BC.position.y),
		_h_segment(CHOKE_BC.position.x, CHOKE_BC.end.x, CHOKE_BC.end.y),
	])

	_prop_obstacle_rects = _build_props(_geometry_root)


func _build_wall_body(parent: Node, name: String, segments: Array[Rect2]) -> void:
	var body := StaticBody2D.new()
	body.name = name
	body.collision_layer = 1
	body.collision_mask = 1
	parent.add_child(body)
	for i in range(segments.size()):
		var rect := segments[i] as Rect2
		if rect.size.x <= 0.1 or rect.size.y <= 0.1:
			continue

		var shape_node := CollisionShape2D.new()
		shape_node.name = "CollisionShape2D_%d" % i
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		shape_node.shape = shape
		shape_node.position = rect.get_center()
		body.add_child(shape_node)

		var visual := Polygon2D.new()
		visual.name = "WallVisual_%d" % i
		visual.position = rect.get_center()
		visual.color = GEOMETRY_COLOR
		visual.polygon = _rect_polygon(rect.size)
		body.add_child(visual)


func _build_props(parent: Node) -> Array[Rect2]:
	var props_root := Node2D.new()
	props_root.name = "Props"
	parent.add_child(props_root)

	var rects := _shadow_prop_rects()
	for i in range(rects.size()):
		var rect := rects[i] as Rect2
		_build_prop_body(props_root, "ShadowProp_%d" % i, rect)
	return rects


func _build_prop_body(parent: Node, name: String, rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.name = name
	body.collision_layer = 1
	body.collision_mask = 1
	parent.add_child(body)

	var shape_node := CollisionShape2D.new()
	shape_node.name = "CollisionShape2D"
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	shape_node.shape = shape
	shape_node.position = rect.get_center()
	body.add_child(shape_node)

	var visual := Polygon2D.new()
	visual.name = "PropVisual"
	visual.position = rect.get_center()
	visual.color = PROP_COLOR
	visual.polygon = _rect_polygon(rect.size)
	body.add_child(visual)


func _shadow_prop_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for shadow_variant in SHADOW_DEFS:
		var shadow := shadow_variant as Dictionary
		var center := shadow.get("pos", Vector2.ZERO) as Vector2
		rects.append(Rect2(center - PROP_SIZE * 0.5, PROP_SIZE))
	return rects


func _add_floor(parent: Node, rect: Rect2, color: Color, name: String) -> void:
	var poly := Polygon2D.new()
	poly.name = name
	poly.color = color
	poly.position = rect.get_center()
	poly.polygon = _rect_polygon(rect.size)
	parent.add_child(poly)


func _rect_polygon(size: Vector2) -> PackedVector2Array:
	var half := size * 0.5
	return PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])


func _h_segment(x0: float, x1: float, y: float) -> Rect2:
	return Rect2(x0, y - WALL_THICKNESS * 0.5, maxf(x1 - x0, 0.0), WALL_THICKNESS)


func _v_segment(x: float, y0: float, y1: float) -> Rect2:
	return Rect2(x - WALL_THICKNESS * 0.5, y0, WALL_THICKNESS, maxf(y1 - y0, 0.0))


func _update_hint_text() -> void:
	if _hint_label == null:
		return
	_hint_label.text = "3-Zone test level (Phase 5)\nA(rooms 0,1) <-> B(room 2) <-> C(room 3) | 5 enemies deterministic | door A1<->A2 starts closed\nE = interact door | Q = kick door"


func _refresh_debug_label(force: bool) -> void:
	if _debug_label == null:
		return
	if _debug_layer and not _debug_layer.visible and not force:
		return

	var zone_a := _zone_state_name(_zone_state(0))
	var zone_b := _zone_state_name(_zone_state(1))
	var zone_c := _zone_state_name(_zone_state(2))

	var lines: Array[String] = []
	lines.append("zones: A=%s B=%s C=%s" % [zone_a, zone_b, zone_c])
	lines.append("door_a1a2_closed=%s enemies=%d" % [str(_door_closed()), _spawned_enemies.size()])
	lines.append(_runtime_debug_line())

	for enemy in _spawned_enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		var snap := enemy.get_ui_awareness_snapshot() if enemy.has_method("get_ui_awareness_snapshot") else {}
		var state_name := ENEMY_ALERT_LEVELS_SCRIPT.level_name(int(snap.get("state", 0)))
		var confirm01 := float(snap.get("confirm01", 0.0))
		var zone_state := _zone_state_name(int(snap.get("zone_state", -1)))
		lines.append("enemy#%d state=%s confirm=%.2f zone=%s" % [enemy.entity_id, state_name, confirm01, zone_state])

	_debug_label.text = "\n".join(lines)


func _door_closed() -> bool:
	if _door_a1a2 == null:
		return false
	if _door_a1a2.has_method("is_closed_or_nearly_closed"):
		return bool(_door_a1a2.is_closed_or_nearly_closed(0.5))
	if _door_a1a2.has_method("get_debug_metrics"):
		var metrics := _door_a1a2.get_debug_metrics() as Dictionary
		return absf(float(metrics.get("angle_deg", 90.0))) <= 0.5
	return false


func _zone_state(zone_id: int) -> int:
	if _zone_director == null or not _zone_director.has_method("get_zone_state"):
		return -1
	return int(_zone_director.get_zone_state(zone_id))


func _zone_state_name(state: int) -> String:
	match state:
		0:
			return "CALM"
		1:
			return "ELEVATED"
		2:
			return "LOCKDOWN"
		_:
			return "NONE"


func _runtime_debug_line() -> String:
	var state_name := "NONE"
	var frozen := false
	var player_hp := -1
	if StateManager:
		state_name = GameState.state_to_string(int(StateManager.current_state))
	if RuntimeState:
		frozen = bool(RuntimeState.is_frozen)
		player_hp = int(RuntimeState.player_hp)
	return "runtime state=%s frozen=%s player_hp=%d" % [state_name, str(frozen), player_hp]


func _clear_children(node: Node) -> void:
	if node == null:
		return
	for child_variant in node.get_children():
		var child := child_variant as Node
		if child == null:
			continue
		node.remove_child(child)
		child.queue_free()
