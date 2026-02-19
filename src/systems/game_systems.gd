class_name GameSystems
extends Node

const SYSTEM_SLOT_NAMES := [
	"aim_system",
	"physics_world",
	"spawner_system",
	"combat_system",
	"projectile_system",
	"vfx_system",
	"stats_system",
	"ability_system",
	"music_system",
]

var aim_system: Node = null
var physics_world: Node = null
var spawner_system: Node = null
var combat_system: Node = null
var projectile_system: Node = null
var vfx_system: Node = null
var stats_system: Node = null
var ability_system: Node = null
var music_system: Node = null

var _systems_paused: bool = false

func update_systems(delta: float) -> void:
	if _systems_paused:
		return
	for system in _active_systems():
		_call_update(system, delta)


func pause_systems() -> void:
	_systems_paused = true
	for system in _active_systems():
		_apply_pause_state(system, true)


func resume_systems() -> void:
	_systems_paused = false
	for system in _active_systems():
		_apply_pause_state(system, false)


func register_system(slot_name: StringName, system: Node) -> bool:
	var slot := String(slot_name)
	if slot not in SYSTEM_SLOT_NAMES:
		return false
	set(slot, system)
	return true


func is_paused() -> bool:
	return _systems_paused


func _active_systems() -> Array[Node]:
	var systems: Array[Node] = []
	var seen_ids: Dictionary = {}
	for slot in SYSTEM_SLOT_NAMES:
		var system: Node = get(slot)
		if system == null:
			continue
		var instance_id := system.get_instance_id()
		if seen_ids.has(instance_id):
			continue
		seen_ids[instance_id] = true
		systems.append(system)
	return systems


func _call_update(system: Object, delta: float) -> void:
	if _method_accepts_arg_count(system, &"system_update", 1):
		system.call(&"system_update", delta)
		return
	if _method_accepts_arg_count(system, &"update", 1):
		system.call(&"update", delta)
		return
	if _method_accepts_arg_count(system, &"tick", 1):
		system.call(&"tick", delta)
		return
	if _method_accepts_arg_count(system, &"runtime_budget_tick", 1):
		system.call(&"runtime_budget_tick", delta)


func _apply_pause_state(system: Node, paused: bool) -> void:
	if _method_accepts_arg_count(system, &"set_paused", 1):
		system.call(&"set_paused", paused)
	elif paused and _method_accepts_arg_count(system, &"pause", 0):
		system.call(&"pause")
	elif (not paused) and _method_accepts_arg_count(system, &"resume", 0):
		system.call(&"resume")
	var enabled := not paused
	system.set_process(enabled)
	system.set_physics_process(enabled)
	system.set_process_input(enabled)
	system.set_process_unhandled_input(enabled)


func _method_accepts_arg_count(obj: Object, method_name: StringName, arg_count: int) -> bool:
	for method_variant in obj.get_method_list():
		var method := method_variant as Dictionary
		if StringName(method.get("name", "")) != method_name:
			continue
		var args := method.get("args", []) as Array
		var default_args := method.get("default_args", []) as Array
		var total := args.size()
		var required := maxi(total - default_args.size(), 0)
		return required <= arg_count and arg_count <= total
	return false
