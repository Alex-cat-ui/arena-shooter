## combat_feedback_system.gd
## CombatFeedbackSystem - visual hit/kill/damage feedback effects.
## CANON: Pure visual, no gameplay impact.
## CANON: Pooled nodes, spawn once per event, auto cleanup.
class_name CombatFeedbackSystem
extends Node

## Directional damage arc container (CanvasLayer child)
var _damage_arc_container: CanvasLayer = null

## Edge kill pulse container
var _edge_pulse_container: CanvasLayer = null

## Active feedback effects
var _active_effects: Array[Dictionary] = []

## Pool of ColorRect nodes for damage arcs
var _arc_pool: Array[ColorRect] = []

## Pool for edge pulse
var _pulse_pool: Array[ColorRect] = []

const ARC_POOL_SIZE := 4
const PULSE_POOL_SIZE := 4


## Initialize
func initialize(hud_layer: CanvasLayer) -> void:
	_damage_arc_container = hud_layer
	_edge_pulse_container = hud_layer

	# Create damage arc pool (directional red overlay)
	for i in range(ARC_POOL_SIZE):
		var rect := ColorRect.new()
		rect.color = Color(1.0, 0.0, 0.0, 0.0)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.visible = false
		rect.anchors_preset = Control.PRESET_FULL_RECT
		rect.anchor_right = 1.0
		rect.anchor_bottom = 1.0
		hud_layer.add_child(rect)
		_arc_pool.append(rect)

	# Create edge pulse pool (kill flash)
	for i in range(PULSE_POOL_SIZE):
		var rect := ColorRect.new()
		rect.color = Color(1.0, 1.0, 1.0, 0.0)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.visible = false
		rect.anchors_preset = Control.PRESET_FULL_RECT
		rect.anchor_right = 1.0
		rect.anchor_bottom = 1.0
		hud_layer.add_child(rect)
		_pulse_pool.append(rect)

	# Subscribe to events
	if EventBus:
		EventBus.player_damaged.connect(_on_player_damaged)
		EventBus.enemy_killed.connect(_on_enemy_killed)

	print("[CombatFeedbackSystem] Initialized")


## Update called each frame
func update(delta: float) -> void:
	var i := 0
	while i < _active_effects.size():
		var entry: Dictionary = _active_effects[i]
		entry["time_left"] -= delta
		if entry["time_left"] <= 0:
			var node: CanvasItem = entry["node"]
			node.visible = false
			_active_effects.remove_at(i)
			continue
		else:
			# Fade out
			var ratio: float = float(entry["time_left"]) / float(entry["max_time"])
			var node: CanvasItem = entry["node"]
			if node is ColorRect:
				(node as ColorRect).color.a = float(entry["base_alpha"]) * ratio
		i += 1


## Spawn directional damage arc overlay
func _on_player_damaged(_amount: int, _new_hp: int, _source: String) -> void:
	var duration := GameConfig.damage_arc_duration if GameConfig else 0.12
	var alpha := 0.2

	# Get a pooled arc
	var rect: ColorRect = null
	for r in _arc_pool:
		if not r.visible:
			rect = r
			break
	if not rect:
		return

	rect.color = Color(1.0, 0.0, 0.0, alpha)
	rect.visible = true

	_active_effects.append({
		"node": rect,
		"time_left": duration,
		"max_time": duration,
		"base_alpha": alpha,
	})


## Spawn subtle edge pulse on kill
func _on_enemy_killed(_enemy_id: int, _enemy_type: String, _wave_id: int) -> void:
	var alpha := GameConfig.kill_edge_pulse_alpha if GameConfig else 0.15
	var duration := GameConfig.kill_pop_duration if GameConfig else 0.1

	# Get a pooled pulse
	var rect: ColorRect = null
	for r in _pulse_pool:
		if not r.visible:
			rect = r
			break
	if not rect:
		return

	rect.color = Color(1.0, 1.0, 1.0, alpha)
	rect.visible = true

	_active_effects.append({
		"node": rect,
		"time_left": duration,
		"max_time": duration,
		"base_alpha": alpha,
	})
