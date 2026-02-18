extends RefCounted
class_name LevelInputController

const DOOR_INTERACT_RADIUS = 20.0
const DOOR_KICK_RADIUS = 40.0
const STEALTH_TEST_SCENE_PATH = "res://src/levels/stealth_3zone_test.tscn"

var on_regenerate_layout: Callable = Callable()
var on_toggle_god_mode: Callable = Callable()
var on_open_stealth_test_scene: Callable = Callable()


func configure_callbacks(
	regen_cb: Callable,
	toggle_god_cb: Callable,
	open_stealth_test_scene_cb: Callable = Callable()
) -> void:
	on_regenerate_layout = regen_cb
	on_toggle_god_mode = toggle_god_cb
	on_open_stealth_test_scene = open_stealth_test_scene_cb


func handle_input(ctx) -> void:
	if Input.is_action_just_pressed("pause"):
		if StateManager:
			if StateManager.is_playing():
				StateManager.change_state(GameState.State.PAUSED)
			elif StateManager.is_paused():
				StateManager.change_state(GameState.State.PLAYING)

	if Input.is_action_just_pressed("debug_game_over"):
		if StateManager and StateManager.is_playing():
			print("[LevelMVP] Debug: Forcing GAME_OVER")
			StateManager.change_state(GameState.State.GAME_OVER)

	if Input.is_action_just_pressed("debug_level_complete"):
		if StateManager and StateManager.is_playing():
			print("[LevelMVP] Debug: Forcing LEVEL_COMPLETE")
			StateManager.change_state(GameState.State.LEVEL_COMPLETE)

	if Input.is_action_just_pressed("debug_toggle"):
		ctx.debug_overlay_visible = not ctx.debug_overlay_visible
		if ctx.debug_container:
			ctx.debug_container.visible = ctx.debug_overlay_visible
		if GameConfig:
			GameConfig.debug_overlay_visible = ctx.debug_overlay_visible
		print("[LevelMVP] Debug overlay: %s" % ("ON" if ctx.debug_overlay_visible else "OFF"))

	if ctx.player and ctx.layout_door_system:
		if Input.is_action_just_pressed("door_interact"):
			ctx.layout_door_system.interact_toggle(ctx.player.global_position, DOOR_INTERACT_RADIUS)
		if Input.is_action_just_pressed("door_kick"):
			ctx.layout_door_system.kick(ctx.player.global_position, DOOR_KICK_RADIUS)


func handle_unhandled_key_input(_ctx, event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return

	if event.keycode == KEY_F4:
		print("[LevelMVP] F4: Regenerating layout")
		if on_regenerate_layout.is_valid():
			on_regenerate_layout.call()
	elif event.keycode == KEY_F8:
		if _is_key_assigned_in_input_map(KEY_F8):
			if on_toggle_god_mode.is_valid():
				on_toggle_god_mode.call()
			return
		if on_open_stealth_test_scene.is_valid():
			on_open_stealth_test_scene.call()
		else:
			_open_stealth_test_scene(_ctx)


func _is_key_assigned_in_input_map(keycode: Key) -> bool:
	for action_name in InputMap.get_actions():
		for input_event in InputMap.action_get_events(action_name):
			if not (input_event is InputEventKey):
				continue
			var key_event := input_event as InputEventKey
			if key_event.keycode == keycode or key_event.physical_keycode == keycode:
				return true
	return false


func _open_stealth_test_scene(ctx) -> void:
	if not ResourceLoader.exists(STEALTH_TEST_SCENE_PATH):
		push_warning("[LevelInputController] F8 fallback scene missing: %s" % STEALTH_TEST_SCENE_PATH)
		return

	var tree: SceneTree = null
	if ctx and ctx.level and ctx.level.get_tree():
		tree = ctx.level.get_tree()
	elif Engine.get_main_loop() is SceneTree:
		tree = Engine.get_main_loop() as SceneTree

	if not tree:
		push_warning("[LevelInputController] F8 fallback scene requested, but no SceneTree is available")
		return

	var err := tree.change_scene_to_file(STEALTH_TEST_SCENE_PATH)
	if err != OK:
		push_warning("[LevelInputController] Failed opening F8 fallback scene (%s), err=%d" % [STEALTH_TEST_SCENE_PATH, err])
