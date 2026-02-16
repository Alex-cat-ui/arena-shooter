extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LEVEL_CONTEXT_SCRIPT := preload("res://src/levels/level_context.gd")
const LEVEL_HUD_CONTROLLER_SCRIPT := preload("res://src/levels/level_hud_controller.gd")

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
	print("LEVEL HUD CONTROLLER TEST")
	print("============================================================")

	await _test_hud_strings_and_hint()
	await _test_debug_overlay_updates()
	await _test_overlay_creation_idempotent()

	_t.summary("LEVEL HUD CONTROLLER RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_hud_strings_and_hint() -> void:
	var controller = LEVEL_HUD_CONTROLLER_SCRIPT.new()
	var ctx = _make_ctx_with_hud()

	if StateManager.current_state != GameState.State.MAIN_MENU:
		StateManager.change_state(GameState.State.MAIN_MENU)
	StateManager.change_state(GameState.State.LEVEL_SETUP)
	StateManager.change_state(GameState.State.PLAYING)

	RuntimeState.player_hp = 77
	RuntimeState.time_elapsed = 12.3
	RuntimeState.kills = 5
	ctx.start_delay_finished = false
	ctx.start_delay_timer = 0.9
	ctx.ability_system = AbilitySystem.new()
	add_child(ctx.ability_system)

	controller.style_hud_labels(ctx)
	controller.update_hud(ctx)

	_t.run_test("HUD HP string uses current runtime hp", ctx.hp_label.text == "HP: 77 / 100")
	_t.run_test("HUD state string includes start delay", ctx.state_label.text == "State: PLAYING (0.9)")
	_t.run_test("HUD time/kills string format preserved", ctx.time_label.text == "Time: 12.3 | Kills: 5")
	_t.run_test("HUD weapon string format preserved", ctx.weapon_label.text == "GUN PISTOL [1/6]")

	ctx.enemy_weapons_enabled = true
	GameConfig.god_mode = true
	controller.refresh_right_debug_hint(ctx)
	_t.run_test("Right debug hint includes Enemy Guns line", ctx.debug_hint_label.text.find("Enemy Guns: ON") >= 0)
	_t.run_test("Right debug hint includes God Mode line", ctx.debug_hint_label.text.find("God Mode: ON") >= 0)

	ctx.ability_system.queue_free()
	ctx.level.queue_free()
	await get_tree().process_frame
	StateManager.change_state(GameState.State.MAIN_MENU)
	GameConfig.god_mode = false


func _test_debug_overlay_updates() -> void:
	var controller = LEVEL_HUD_CONTROLLER_SCRIPT.new()
	var ctx = _make_ctx_with_hud()
	ctx.debug_overlay_visible = true
	ctx.enemy_weapons_enabled = true

	ctx.projectiles_container = Node2D.new()
	ctx.decals_container = Node2D.new()
	ctx.level.add_child(ctx.projectiles_container)
	ctx.level.add_child(ctx.decals_container)

	ctx.layout_room_stats = {
		"corridors": 1,
		"interior_rooms": 2,
		"exterior_rooms": 3,
		"closets": 4,
	}

	controller.create_debug_overlay(ctx)
	controller.update_debug_overlay(ctx)

	var room_label := ctx.debug_container.get_node_or_null("RoomTypesLabel") as Label
	_t.run_test("Debug overlay creates RoomTypesLabel", room_label != null)
	_t.run_test("RoomTypesLabel includes enemy toggle status", room_label != null and room_label.text.find("enemy_guns=ON") >= 0)

	ctx.level.queue_free()
	await get_tree().process_frame


func _test_overlay_creation_idempotent() -> void:
	var controller = LEVEL_HUD_CONTROLLER_SCRIPT.new()
	var ctx = _make_ctx_with_hud()
	ctx.debug_overlay_visible = true

	controller.create_vignette(ctx)
	controller.create_debug_overlay(ctx)
	controller.create_vignette(ctx)
	controller.create_debug_overlay(ctx)

	var vignette_count := 0
	var debug_overlay_count := 0
	for child_variant in ctx.hud.get_children():
		var child := child_variant as Node
		if child == null:
			continue
		if child.name == "Vignette":
			vignette_count += 1
		if child.name == "DebugOverlay":
			debug_overlay_count += 1

	var debug_label_count: int = ctx.debug_container.get_child_count() if ctx.debug_container else 0
	_t.run_test("Vignette creation is idempotent", vignette_count == 1)
	_t.run_test("Debug overlay creation is idempotent", debug_overlay_count == 1)
	_t.run_test("Debug overlay labels are not duplicated", debug_label_count == 7)

	ctx.level.queue_free()
	await get_tree().process_frame


func _make_ctx_with_hud():
	var ctx = LEVEL_CONTEXT_SCRIPT.new()
	var level = Node2D.new()
	var hud_layer = CanvasLayer.new()
	level.add_child(hud_layer)
	add_child(level)

	ctx.level = level
	ctx.hud = hud_layer
	ctx.hp_label = Label.new()
	ctx.state_label = Label.new()
	ctx.time_label = Label.new()
	ctx.weapon_label = Label.new()
	ctx.debug_hint_label = Label.new()
	hud_layer.add_child(ctx.hp_label)
	hud_layer.add_child(ctx.state_label)
	hud_layer.add_child(ctx.time_label)
	hud_layer.add_child(ctx.weapon_label)
	hud_layer.add_child(ctx.debug_hint_label)

	ctx.projectiles_container = null
	ctx.decals_container = null
	ctx.vfx_system = null
	ctx.footprint_system = null
	ctx.atmosphere_system = null

	return ctx
