extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LEVEL_CONTEXT_SCRIPT := preload("res://src/levels/level_context.gd")
const LEVEL_BOOTSTRAP_CONTROLLER_SCRIPT := preload("res://src/levels/level_bootstrap_controller.gd")
const LEVEL_LAYOUT_CONTROLLER_SCRIPT := preload("res://src/levels/level_layout_controller.gd")
const LEVEL_TRANSITION_CONTROLLER_SCRIPT := preload("res://src/levels/level_transition_controller.gd")
const LEVEL_CAMERA_CONTROLLER_SCRIPT := preload("res://src/levels/level_camera_controller.gd")
const LEVEL_ENEMY_RUNTIME_CONTROLLER_SCRIPT := preload("res://src/levels/level_enemy_runtime_controller.gd")
const LEVEL_RUNTIME_GUARD_SCRIPT := preload("res://src/levels/level_runtime_guard.gd")
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
	print("LEVEL BOOTSTRAP CONTROLLER TEST")
	print("============================================================")

	await _test_system_creation_and_wiring_order()

	_t.summary("LEVEL BOOTSTRAP CONTROLLER RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_system_creation_and_wiring_order() -> void:
	var ctx = _make_context_graph()
	var bootstrap = LEVEL_BOOTSTRAP_CONTROLLER_SCRIPT.new()
	var layout_controller = LEVEL_LAYOUT_CONTROLLER_SCRIPT.new()
	var transition_controller = LEVEL_TRANSITION_CONTROLLER_SCRIPT.new()
	var camera_controller = LEVEL_CAMERA_CONTROLLER_SCRIPT.new()
	var enemy_runtime = LEVEL_ENEMY_RUNTIME_CONTROLLER_SCRIPT.new()
	var runtime_guard = LEVEL_RUNTIME_GUARD_SCRIPT.new()
	var hud_controller = LEVEL_HUD_CONTROLLER_SCRIPT.new()

	layout_controller.set_dependencies(transition_controller, camera_controller, enemy_runtime, runtime_guard)
	bootstrap.init_runtime_state(ctx, transition_controller.current_mission_index(ctx))
	bootstrap.init_systems(ctx, layout_controller, transition_controller, camera_controller)
	bootstrap.init_visual_polish(ctx, hud_controller)

	_t.run_test("bootstrap creates core systems", ctx.combat_system != null and ctx.projectile_system != null and ctx.vfx_system != null)
	_t.run_test("bootstrap creates layout and tactical systems", ctx.layout_door_system != null and ctx.room_nav_system != null and ctx.enemy_alert_system != null and ctx.enemy_squad_system != null)
	_t.run_test("bootstrap creates runtime budget scheduler", ctx.runtime_budget_controller != null)
	_t.run_test("bootstrap creates visual polish systems", ctx.shadow_system != null and ctx.combat_feedback_system != null and ctx.atmosphere_system != null)

	var combat_idx := _child_index(ctx.level, "CombatSystem")
	var projectile_idx := _child_index(ctx.level, "ProjectileSystem")
	var vfx_idx := _child_index(ctx.level, "VFXSystem")
	_t.run_test("bootstrap ordering keeps Combat -> Projectile -> VFX", combat_idx < projectile_idx and projectile_idx < vfx_idx)

	var walls_idx := _child_index(ctx.level, "LayoutWalls")
	var doors_idx := _child_index(ctx.level, "LayoutDoors")
	var debug_idx := _child_index(ctx.level, "LayoutDebug")
	_t.run_test("bootstrap ordering keeps LayoutWalls -> LayoutDoors -> LayoutDebug", walls_idx < doors_idx and doors_idx < debug_idx)

	ctx.level.queue_free()
	await get_tree().process_frame


func _make_context_graph():
	var ctx = LEVEL_CONTEXT_SCRIPT.new()
	var level = Node2D.new()
	add_child(level)

	var floor_root := Node2D.new()
	floor_root.name = "Floor"
	var floor_sprite := Sprite2D.new()
	floor_sprite.name = "FloorSprite"
	floor_sprite.texture = _make_test_texture()
	floor_root.add_child(floor_sprite)
	level.add_child(floor_root)

	var entities := Node2D.new()
	entities.name = "Entities"
	level.add_child(entities)

	var player := CharacterBody2D.new()
	player.name = "Player"
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	player.add_child(sprite)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	player.add_child(shape)
	entities.add_child(player)

	var camera := Camera2D.new()
	camera.name = "Camera2D"
	level.add_child(camera)

	var hud := CanvasLayer.new()
	hud.name = "HUD"
	var hud_container := VBoxContainer.new()
	hud_container.name = "HUDContainer"
	hud.add_child(hud_container)
	var hp := Label.new(); hp.name = "HPLabel"; hud_container.add_child(hp)
	var st := Label.new(); st.name = "StateLabel"; hud_container.add_child(st)
	var tm := Label.new(); tm.name = "TimeLabel"; hud_container.add_child(tm)
	var wp := Label.new(); wp.name = "WeaponLabel"; hud_container.add_child(wp)
	var hint := Label.new(); hint.name = "DebugHint"; hud.add_child(hint)
	level.add_child(hud)

	var projectiles := Node2D.new(); projectiles.name = "Projectiles"; level.add_child(projectiles)
	var decals := Node2D.new(); decals.name = "Decals"; level.add_child(decals)
	var corpses := Node2D.new(); corpses.name = "Corpses"; level.add_child(corpses)
	var footprints := Node2D.new(); footprints.name = "Footprints"; level.add_child(footprints)

	ctx.level = level
	ctx.player = player
	ctx.camera = camera
	ctx.hud = hud
	ctx.hp_label = hp
	ctx.state_label = st
	ctx.time_label = tm
	ctx.weapon_label = wp
	ctx.debug_hint_label = hint
	ctx.floor_root = floor_root
	ctx.floor_sprite = floor_sprite
	ctx.entities_container = entities
	ctx.projectiles_container = projectiles
	ctx.decals_container = decals
	ctx.corpses_container = corpses
	ctx.footprints_container = footprints
	return ctx


func _make_test_texture() -> ImageTexture:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.5, 1.0))
	return ImageTexture.create_from_image(img)


func _child_index(parent: Node, name: String) -> int:
	for i in range(parent.get_child_count()):
		if parent.get_child(i).name == name:
			return i
	return 9999
