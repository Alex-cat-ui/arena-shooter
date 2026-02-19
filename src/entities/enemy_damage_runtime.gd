## enemy_damage_runtime.gd
## Shared runtime damage flow for Enemy.
class_name EnemyDamageRuntime
extends RefCounted

const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")


static func apply_damage(enemy: Node, amount: int, source: String, from_player: bool = false) -> void:
	if enemy == null:
		return
	if amount <= 0:
		return
	if bool(enemy.get("is_dead")):
		return

	var awareness: Variant = enemy.get("_awareness")
	if from_player and awareness:
		var is_first_hostile_damage := not bool(awareness.hostile_damaged)
		awareness.hostile_damaged = true
		if int(awareness.get_state()) == int(ENEMY_AWARENESS_SYSTEM_SCRIPT.State.COMBAT):
			awareness.combat_phase = ENEMY_AWARENESS_SYSTEM_SCRIPT.CombatPhase.ENGAGED
			awareness.hostile_contact = true
		elif awareness.has_method("_transition_to_combat_from_damage") and enemy.has_method("_apply_awareness_transitions"):
			var transitions: Array[Dictionary] = awareness._transition_to_combat_from_damage()
			enemy.call("_apply_awareness_transitions", transitions, "damage")
		if is_first_hostile_damage and EventBus and EventBus.has_method("emit_hostile_escalation"):
			EventBus.emit_hostile_escalation(int(enemy.get("entity_id")), "damaged")

	var hp_now := int(enemy.get("hp")) - amount
	enemy.set("hp", hp_now)

	var sprite := enemy.get("sprite") as Sprite2D
	if sprite:
		var flash_dur := GameConfig.hit_flash_duration if GameConfig else 0.06
		sprite.modulate = Color(3.0, 3.0, 3.0, 1.0)
		var tween := enemy.create_tween()
		tween.tween_property(sprite, "modulate", Color.WHITE, flash_dur)

	if RuntimeState:
		RuntimeState.damage_dealt += amount
	if EventBus:
		EventBus.emit_damage_dealt(int(enemy.get("entity_id")), amount, source)

	if hp_now <= 0 and enemy.has_method("die"):
		enemy.call("die")
