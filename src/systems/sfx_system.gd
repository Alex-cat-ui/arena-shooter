## sfx_system.gd
## SFXSystem - plays sound effects in response to EventBus events.
## CANON: Reads volume from GameConfig.sfx_volume.
## CANON: Uses a pool of AudioStreamPlayer nodes for overlapping sounds.
## CANON: All SFX loaded from res://assets/audio/sfx/.
class_name SFXSystem
extends Node

## SFX path base
const SFX_PATH := "res://assets/audio/sfx/"

## Pool size (max simultaneous sounds)
const POOL_SIZE := 12

## Audio player pool
var _players: Array[AudioStreamPlayer] = []

## Preloaded streams keyed by name
var _streams: Dictionary = {}

## Weapon → SFX mapping
const WEAPON_SFX := {
	"pistol": "pistol_shot",
	"auto": "auto_shot",
	"shotgun": "shotgun_shot",
	"plasma": "plasma_shot",
	"rocket": "rocket_shot",
	"chain_lightning": "chain_lightning",
}

## SFX files to preload
const SFX_FILES: Array[String] = [
	"pistol_shot",
	"auto_shot",
	"shotgun_shot",
	"plasma_shot",
	"rocket_shot",
	"rocket_explosion",
	"chain_lightning",
	"enemy_death",
	"player_hit",
	"player_death",
	"weapon_switch",
	"wave_start",
	"boss_spawn",
	"boss_death",
]


func _ready() -> void:
	# Create audio player pool
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer_%d" % i
		player.bus = "Master"
		add_child(player)
		_players.append(player)

	# Preload all SFX streams
	_preload_streams()

	# Subscribe to EventBus
	if EventBus:
		EventBus.player_shot.connect(_on_player_shot)
		EventBus.enemy_killed.connect(_on_enemy_killed)
		EventBus.player_damaged.connect(_on_player_damaged)
		EventBus.player_died.connect(_on_player_died)
		EventBus.rocket_exploded.connect(_on_rocket_exploded)
		EventBus.weapon_changed.connect(_on_weapon_changed)
		EventBus.wave_started.connect(_on_wave_started)
		EventBus.boss_spawned.connect(_on_boss_spawned)
		EventBus.boss_killed.connect(_on_boss_killed)

	print("[SFXSystem] Initialized (%d streams loaded, pool size %d)" % [_streams.size(), POOL_SIZE])


func _preload_streams() -> void:
	for sfx_name in SFX_FILES:
		var path := SFX_PATH + sfx_name + ".wav"
		var stream := load(path) as AudioStream
		if stream:
			_streams[sfx_name] = stream
		else:
			push_warning("[SFXSystem] Failed to load: %s" % path)


## Play a named SFX
func play(sfx_name: String, volume_scale: float = 1.0) -> void:
	if not _streams.has(sfx_name):
		return

	var player := _get_free_player()
	if not player:
		return

	# Calculate volume from GameConfig
	var base_volume: float = GameConfig.sfx_volume if GameConfig else 0.7
	var final_volume := base_volume * volume_scale
	if final_volume <= 0.0:
		return

	player.stream = _streams[sfx_name]
	player.volume_db = linear_to_db(final_volume)
	player.play()


## Get a free (not playing) player from pool, or steal oldest
func _get_free_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	# All busy - return first (oldest sound gets replaced)
	return _players[0]


## ============================================================================
## EVENT HANDLERS
## ============================================================================

func _on_player_shot(weapon_type: String, _position: Vector3, _direction: Vector3) -> void:
	var sfx_name: String = WEAPON_SFX.get(weapon_type, "pistol_shot")
	play(sfx_name)


func _on_enemy_killed(_enemy_id: int, _enemy_type: String, _wave_id: int) -> void:
	play("enemy_death")


func _on_player_damaged(_amount: int, _new_hp: int, _source: String) -> void:
	play("player_hit")


func _on_player_died() -> void:
	play("player_death")


func _on_rocket_exploded(_position: Vector3) -> void:
	play("rocket_explosion")


func _on_weapon_changed(_weapon_name: String, _weapon_index: int) -> void:
	play("weapon_switch")


func _on_wave_started(_wave_index: int, _wave_size: int) -> void:
	play("wave_start")


func _on_boss_spawned(_boss_id: int, _position: Vector3) -> void:
	play("boss_spawn")


func _on_boss_killed(_boss_id: int) -> void:
	play("boss_death")
