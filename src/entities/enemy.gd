## enemy.gd
## Base enemy entity.
## CANON: Uses modular perception + pursuit systems.
class_name Enemy
extends CharacterBody2D

const SHOTGUN_SPREAD_SCRIPT := preload("res://src/systems/shotgun_spread.gd")
const SHOTGUN_DAMAGE_MODEL_SCRIPT := preload("res://src/systems/shotgun_damage_model.gd")
const ENEMY_PERCEPTION_SYSTEM_SCRIPT := preload("res://src/systems/enemy_perception_system.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")
const WEAPON_SHOTGUN := "shotgun"

const SIGHT_FOV_DEG := 180.0
const SIGHT_MAX_DISTANCE_PX := 1500.0
const FIRE_ATTACK_RANGE_MAX_PX := 600.0
const FIRE_SPAWN_OFFSET_PX := 20.0
const FIRE_RAY_RANGE_PX := 2000.0
const VISION_DEBUG_COLOR := Color(1.0, 0.96, 0.62, 0.9)
const VISION_DEBUG_COLOR_DIM := Color(1.0, 0.96, 0.62, 0.55)
const VISION_DEBUG_WIDTH := 2.0
const VISION_DEBUG_FILL_COLOR := Color(1.0, 0.96, 0.62, 0.20)
const VISION_DEBUG_FILL_COLOR_DIM := Color(1.0, 0.96, 0.62, 0.11)
const VISION_DEBUG_FILL_RAY_COUNT := 24
const AWARENESS_COMBAT := "COMBAT"

## Enemy stats per type
const ENEMY_STATS := {
	"zombie": {"hp": 100, "damage": 10, "speed": 2.0},
	"fast": {"hp": 100, "damage": 7, "speed": 4.0},
	"tank": {"hp": 100, "damage": 15, "speed": 1.5},
	"swarm": {"hp": 100, "damage": 5, "speed": 3.0},
}

## Unique entity ID
var entity_id: int = 0

## Enemy type name
var enemy_type: String = "zombie"

## Wave this enemy belongs to
var wave_id: int = 0

## Current HP
var hp: int = 30

## Max HP (for potential HP bars)
var max_hp: int = 30

## Contact damage (kept for compatibility)
var contact_damage: int = 10

## Runtime toggle from LevelMVP (F7).
var weapons_enabled: bool = false

## Movement speed in tiles/sec
var speed_tiles: float = 2.0

## Is enemy dead?
var is_dead: bool = false

## Stagger timer (melee knockback, blocks movement)
var stagger_timer: float = 0.0

## Knockback velocity (decays over time)
var knockback_vel: Vector2 = Vector2.ZERO

## Reference to sprite
@onready var sprite: Sprite2D = $Sprite2D

## Reference to collision shape
@onready var collision: CollisionShape2D = $CollisionShape2D

## Room/nav wiring (kept for compatibility with RoomNavSystem)
var nav_system: Node = null
var home_room_id: int = -1

## Weapon timing
var _shot_cooldown: float = 0.0
var _player_visible_prev: bool = false
var _shot_rng := RandomNumberGenerator.new()

## Modular AI systems
var _perception = null
var _pursuit = null
var _awareness = null
var _vision_fill_poly: Polygon2D = null
var _vision_center_line: Line2D = null
var _vision_left_line: Line2D = null
var _vision_right_line: Line2D = null


func _ready() -> void:
	add_to_group("enemies")
	_shot_rng.randomize()
	_perception = ENEMY_PERCEPTION_SYSTEM_SCRIPT.new(self)
	_pursuit = ENEMY_PURSUIT_SYSTEM_SCRIPT.new(self, sprite, speed_tiles)
	_awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	_awareness.reset()
	set_meta("awareness_state", _awareness.get_state_name())
	_connect_event_bus_signals()
	_setup_vision_debug_lines()
	_play_spawn_animation()


## Initialize enemy with ID, type, and wave
func initialize(id: int, type: String, wave: int) -> void:
	entity_id = id
	enemy_type = type
	wave_id = wave

	if ENEMY_STATS.has(type):
		var stats: Dictionary = ENEMY_STATS[type]
		hp = stats.hp
		max_hp = stats.hp
		contact_damage = stats.damage
		speed_tiles = stats.speed
	else:
		push_warning("[Enemy] Unknown enemy type: %s" % type)

	if _pursuit:
		_pursuit.set_speed_tiles(speed_tiles)
	if _awareness:
		_awareness.reset()
		set_meta("awareness_state", _awareness.get_state_name())


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if RuntimeState and RuntimeState.is_frozen:
		return

	if _shot_cooldown > 0.0:
		_shot_cooldown = maxf(0.0, _shot_cooldown - delta)

	# Handle stagger (blocks normal movement)
	if stagger_timer > 0:
		stagger_timer -= delta
		if knockback_vel.length_squared() > 1.0:
			velocity = knockback_vel
			move_and_slide()
			knockback_vel = knockback_vel.lerp(Vector2.ZERO, minf(10.0 * delta, 1.0))
		return

	# Decay any residual knockback
	if knockback_vel.length_squared() > 1.0:
		knockback_vel = knockback_vel.lerp(Vector2.ZERO, minf(10.0 * delta, 1.0))

	if not _perception or not _pursuit:
		return

	var player_valid: bool = bool(_perception.has_player())
	var player_pos: Vector2 = _perception.get_player_position()
	var player_visible: bool = bool(_perception.can_see_player(
		global_position,
		_pursuit.get_facing_dir(),
		SIGHT_FOV_DEG,
		SIGHT_MAX_DISTANCE_PX,
		_ray_excludes()
	))
	if _awareness:
		_apply_awareness_transitions(_awareness.process(delta, player_visible))
	if player_visible and not _player_visible_prev:
		if EventBus:
			EventBus.emit_enemy_player_spotted(entity_id, Vector3(player_pos.x, player_pos.y, 0.0))
	_player_visible_prev = player_visible if player_valid else false

	var use_room_nav: bool = nav_system != null and home_room_id >= 0
	_pursuit.update(delta, use_room_nav, player_valid, player_pos, player_visible)
	if weapons_enabled and _should_fire_player_target(player_visible, player_pos):
		_try_fire_at_player(player_pos)
	_update_vision_debug_lines(player_valid, player_pos, player_visible)


func set_room_navigation(p_nav_system: Node, p_home_room_id: int) -> void:
	nav_system = p_nav_system
	home_room_id = p_home_room_id
	if _pursuit:
		_pursuit.configure_navigation(p_nav_system, p_home_room_id)


func on_heard_shot(shot_room_id: int, shot_pos: Vector2) -> void:
	if _awareness:
		_apply_awareness_transitions(_awareness.register_noise())
	if _pursuit:
		_pursuit.on_heard_shot(shot_room_id, shot_pos)


func apply_room_alert_propagation(_source_enemy_id: int, _source_room_id: int) -> void:
	if _awareness:
		_apply_awareness_transitions(_awareness.register_room_alert_propagation())


func _connect_event_bus_signals() -> void:
	if not EventBus:
		return
	if EventBus.has_signal("enemy_reinforcement_called") and not EventBus.enemy_reinforcement_called.is_connected(_on_enemy_reinforcement_called):
		EventBus.enemy_reinforcement_called.connect(_on_enemy_reinforcement_called)


func _on_enemy_reinforcement_called(source_enemy_id: int, _source_room_id: int, target_room_ids: Array) -> void:
	if is_dead:
		return
	if source_enemy_id == entity_id:
		return
	var own_room_id := _resolve_room_id_for_events()
	if own_room_id < 0:
		return
	if not target_room_ids.has(own_room_id):
		return
	if _awareness:
		_apply_awareness_transitions(_awareness.register_reinforcement())


func _apply_awareness_transitions(transitions: Array[Dictionary]) -> void:
	for transition_variant in transitions:
		var transition := transition_variant as Dictionary
		if transition.is_empty():
			continue
		_emit_awareness_transition(transition)
		if transition.has("to_state"):
			set_meta("awareness_state", String(transition.get("to_state", "")))


func _emit_awareness_transition(transition: Dictionary) -> void:
	if not EventBus or not EventBus.has_method("emit_enemy_state_changed"):
		return
	var from_state := String(transition.get("from_state", ""))
	var to_state := String(transition.get("to_state", ""))
	if from_state == "" or to_state == "":
		return
	EventBus.emit_enemy_state_changed(
		entity_id,
		from_state,
		to_state,
		_resolve_room_id_for_events(),
		String(transition.get("reason", "timer"))
	)


func _resolve_room_id_for_events() -> int:
	var room_id := int(get_meta("room_id", home_room_id))
	if room_id < 0 and nav_system and nav_system.has_method("room_id_at_point"):
		room_id = int(nav_system.room_id_at_point(global_position))
		set_meta("room_id", room_id)
	return room_id


func _try_fire_at_player(player_pos: Vector2) -> void:
	if _shot_cooldown > 0.0:
		return
	if not _is_combat_awareness_active():
		return

	var aim_dir := (player_pos - global_position).normalized()
	if aim_dir.length_squared() <= 0.0001:
		return
	if _pursuit:
		_pursuit.face_towards(player_pos)

	var muzzle := global_position + aim_dir * FIRE_SPAWN_OFFSET_PX
	_fire_enemy_shotgun(muzzle, aim_dir)
	_shot_cooldown = _shotgun_cooldown_sec()

	if EventBus:
		EventBus.emit_enemy_shot(
			entity_id,
			WEAPON_SHOTGUN,
			Vector3(muzzle.x, muzzle.y, 0),
			Vector3(aim_dir.x, aim_dir.y, 0)
		)


func _should_fire_player_target(player_visible: bool, player_pos: Vector2) -> bool:
	if not player_visible:
		return false
	if not _is_combat_awareness_active():
		return false
	return global_position.distance_to(player_pos) <= FIRE_ATTACK_RANGE_MAX_PX


func _is_combat_awareness_active() -> bool:
	if not _awareness:
		return false
	return _awareness.get_state_name() == AWARENESS_COMBAT


func _fire_enemy_shotgun(origin: Vector2, aim_dir: Vector2) -> void:
	if not _perception:
		return
	var stats := _shotgun_stats()
	var pellets := maxi(int(stats.get("pellets", 16)), 1)
	var cone_deg := maxf(float(stats.get("cone_deg", 8.0)), 0.0)
	var spread_profile := SHOTGUN_SPREAD_SCRIPT.sample_pellets(pellets, cone_deg, _shot_rng)

	var hits := 0
	for pellet_variant in spread_profile:
		var pellet := pellet_variant as Dictionary
		var angle_offset := float(pellet.get("angle_offset", 0.0))
		var dir := aim_dir.rotated(angle_offset)
		if _perception.ray_hits_player(origin, dir, FIRE_RAY_RANGE_PX, _ray_excludes()):
			hits += 1

	if hits <= 0 or not EventBus:
		return

	var shot_total_damage := maxf(float(stats.get("shot_damage_total", 25.0)), 0.0)
	var applied_damage := 0
	if SHOTGUN_DAMAGE_MODEL_SCRIPT.is_lethal_hits(hits, pellets):
		applied_damage = _player_lethal_damage()
	else:
		applied_damage = SHOTGUN_DAMAGE_MODEL_SCRIPT.damage_for_hits(hits, pellets, shot_total_damage)

	if applied_damage > 0:
		EventBus.emit_enemy_contact(entity_id, "enemy_shotgun", applied_damage)


func _ray_excludes() -> Array[RID]:
	return [get_rid()]


func _setup_vision_debug_lines() -> void:
	_vision_fill_poly = _create_vision_fill_poly()
	_vision_center_line = _create_vision_line()
	_vision_left_line = _create_vision_line()
	_vision_right_line = _create_vision_line()
	add_child(_vision_fill_poly)
	add_child(_vision_center_line)
	add_child(_vision_left_line)
	add_child(_vision_right_line)


func _create_vision_line() -> Line2D:
	var line := Line2D.new()
	line.width = VISION_DEBUG_WIDTH
	line.default_color = VISION_DEBUG_COLOR
	line.antialiased = true
	line.z_as_relative = false
	line.z_index = 220
	line.points = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	return line


func _create_vision_fill_poly() -> Polygon2D:
	var poly := Polygon2D.new()
	poly.color = VISION_DEBUG_FILL_COLOR_DIM
	poly.z_as_relative = false
	poly.z_index = 210
	poly.polygon = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	return poly


func _update_vision_debug_lines(player_valid: bool, player_pos: Vector2, player_visible: bool) -> void:
	if not _vision_center_line or not _vision_left_line or not _vision_right_line or not _vision_fill_poly:
		return
	var facing: Vector2 = Vector2.RIGHT
	if _pursuit:
		facing = _pursuit.get_facing_dir() as Vector2
	if facing.length_squared() <= 0.0001:
		facing = Vector2.RIGHT

	var half_fov := deg_to_rad(SIGHT_FOV_DEG) * 0.5
	var left_dir: Vector2 = facing.rotated(-half_fov)
	var right_dir: Vector2 = facing.rotated(half_fov)

	var center_end := _vision_ray_end(facing, SIGHT_MAX_DISTANCE_PX)
	var left_end := _vision_ray_end(left_dir, SIGHT_MAX_DISTANCE_PX)
	var right_end := _vision_ray_end(right_dir, SIGHT_MAX_DISTANCE_PX)
	if player_valid and player_visible:
		center_end = player_pos

	var color := VISION_DEBUG_COLOR if player_visible else VISION_DEBUG_COLOR_DIM
	_vision_fill_poly.color = VISION_DEBUG_FILL_COLOR if player_visible else VISION_DEBUG_FILL_COLOR_DIM
	_vision_center_line.default_color = color
	_vision_left_line.default_color = color
	_vision_right_line.default_color = color

	var fan_points := PackedVector2Array()
	fan_points.append(Vector2.ZERO)
	for i in range(VISION_DEBUG_FILL_RAY_COUNT + 1):
		var t := float(i) / float(VISION_DEBUG_FILL_RAY_COUNT)
		var angle_offset := -half_fov + t * (half_fov * 2.0)
		var sample_dir := facing.rotated(angle_offset)
		var sample_end := _vision_ray_end(sample_dir, SIGHT_MAX_DISTANCE_PX)
		fan_points.append(to_local(sample_end))
	_vision_fill_poly.polygon = fan_points

	_set_vision_line_points(_vision_center_line, center_end)
	_set_vision_line_points(_vision_left_line, left_end)
	_set_vision_line_points(_vision_right_line, right_end)


func _set_vision_line_points(line: Line2D, world_end: Vector2) -> void:
	line.points = PackedVector2Array([
		Vector2.ZERO,
		to_local(world_end)
	])


func _vision_ray_end(dir: Vector2, max_range: float) -> Vector2:
	var n_dir := dir.normalized()
	if n_dir.length_squared() <= 0.0001:
		return global_position
	var target := global_position + n_dir * max_range
	var query := PhysicsRayQueryParameters2D.create(global_position, target)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = _ray_excludes()

	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return target
	return hit.get("position", target) as Vector2


func _shotgun_stats() -> Dictionary:
	if GameConfig and GameConfig.weapon_stats.has(WEAPON_SHOTGUN):
		return GameConfig.weapon_stats[WEAPON_SHOTGUN] as Dictionary
	return {
		"cooldown_sec": 1.2,
		"rpm": 50.0,
		"pellets": 16,
		"cone_deg": 8.0,
	}


func _shotgun_cooldown_sec() -> float:
	var stats := _shotgun_stats()
	var cooldown_sec := float(stats.get("cooldown_sec", -1.0))
	if cooldown_sec > 0.0:
		return cooldown_sec
	var rpm := maxf(float(stats.get("rpm", 60.0)), 1.0)
	return 60.0 / rpm


func _player_lethal_damage() -> int:
	if RuntimeState:
		return maxi(int(RuntimeState.player_hp), 1)
	return GameConfig.player_max_hp if GameConfig else 100


## Apply damage from any source (melee, projectile, etc.)
## Reduces HP, emits EventBus signals, handles death once.
func apply_damage(amount: int, source: String) -> void:
	if is_dead:
		return
	hp -= amount
	if sprite:
		var flash_dur := GameConfig.hit_flash_duration if GameConfig else 0.06
		sprite.modulate = Color(3.0, 3.0, 3.0, 1.0)
		var tween := create_tween()
		tween.tween_property(sprite, "modulate", Color.WHITE, flash_dur)
	if RuntimeState:
		RuntimeState.damage_dealt += amount
	if EventBus:
		EventBus.emit_damage_dealt(entity_id, amount, source)
	if hp <= 0:
		die()


## Apply stagger (blocks movement for duration)
func apply_stagger(sec: float) -> void:
	stagger_timer = maxf(stagger_timer, sec)


## Apply knockback impulse
func apply_knockback(impulse: Vector2) -> void:
	knockback_vel = impulse


## Take damage (legacy, used by CombatSystem projectile pipeline)
func take_damage(amount: int) -> void:
	if is_dead:
		return

	hp -= amount

	if sprite:
		var flash_dur := GameConfig.hit_flash_duration if GameConfig else 0.06
		sprite.modulate = Color(3.0, 3.0, 3.0, 1.0)
		var tween := create_tween()
		tween.tween_property(sprite, "modulate", Color.WHITE, flash_dur)

	if hp <= 0:
		die()


## Enemy death
func die() -> void:
	if is_dead:
		return

	is_dead = true

	if RuntimeState:
		RuntimeState.kills += 1

	if collision:
		collision.set_deferred("disabled", true)

	if EventBus:
		EventBus.emit_enemy_killed(entity_id, enemy_type, wave_id)

	_play_death_effect()


func _cleanup_after_death() -> void:
	remove_from_group("enemies")
	set_physics_process(false)
	queue_free()


## Spawn scale-in animation + flash
func _play_spawn_animation() -> void:
	if not sprite:
		return
	sprite.scale = Vector2(0.1, 0.1)
	sprite.modulate = Color(2.0, 2.0, 2.0, 1.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.2)


## Kill feedback: scale pop 1.0 -> kill_pop_scale -> 0 + fade
func _play_death_effect() -> void:
	if not sprite:
		call_deferred("_cleanup_after_death")
		return

	var pop_scale := GameConfig.kill_pop_scale if GameConfig else 1.2
	var pop_dur := GameConfig.kill_pop_duration if GameConfig else 0.1

	sprite.modulate = Color(3.0, 3.0, 3.0, 1.0)
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector2(pop_scale, pop_scale), pop_dur * 0.5).set_ease(Tween.EASE_OUT)
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2(0, 0), pop_dur * 0.5).set_ease(Tween.EASE_IN)
	tween.tween_property(sprite, "modulate:a", 0.0, pop_dur * 0.5)
	tween.set_parallel(false)
	tween.tween_callback(_cleanup_after_death)
