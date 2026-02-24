## enemy_combat_role_runtime.gd
## Phase 2 skeleton owner for combat-role domain.
class_name EnemyCombatRoleRuntime
extends RefCounted

var _owner: Node = null


func _init(owner: Node = null) -> void:
	_owner = owner


func bind(owner: Node) -> void:
	_owner = owner


func get_owner() -> Node:
	return _owner
