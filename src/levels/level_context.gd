extends RefCounted
class_name LevelContext

var level: Node2D = null

# Scene refs
var player: CharacterBody2D = null
var camera: Camera2D = null
var hud: CanvasLayer = null
var hp_label: Label = null
var state_label: Label = null
var time_label: Label = null
var weapon_label: Label = null
var floor_root: Node2D = null
var floor_sprite: Sprite2D = null
var debug_hint_label: Label = null

# Container refs
var entities_container: Node2D = null
var projectiles_container: Node2D = null
var decals_container: Node2D = null
var corpses_container: Node2D = null
var footprints_container: Node2D = null

# Runtime systems
var combat_system: CombatSystem = null
var projectile_system: ProjectileSystem = null
var vfx_system: VFXSystem = null
var footprint_system: FootprintSystem = null
var room_enemy_spawner = null
var room_nav_system = null
var enemy_alert_system = null
var enemy_squad_system = null
var enemy_aggro_coordinator = null
var layout_door_system = null
var runtime_budget_controller = null

# Weapons/polish systems
var ability_system: AbilitySystem = null
var camera_shake: CameraShake = null
var arena_boundary: ArenaBoundary = null

var shadow_system: ShadowSystem = null
var combat_feedback_system: CombatFeedbackSystem = null
var atmosphere_system: AtmosphereSystem = null

# Layout state
var layout_walls: Node2D = null
var layout_doors: Node2D = null
var layout_debug: Node2D = null
var layout = null
var walkable_floor: Node2D = null
var non_walkable_floor_bg: Sprite2D = null
var layout_room_memory: Array = []
var north_transition_rect: Rect2 = Rect2()
var north_transition_enabled: bool = false
var north_transition_cooldown: float = 0.0
var mission_cycle: Array[int] = [3, 1, 2]
var mission_cycle_pos: int = 0
var layout_room_stats: Dictionary = {
	"corridors": 0,
	"interior_rooms": 0,
	"exterior_rooms": 0,
	"closets": 0,
}

# Runtime state
var start_delay_timer: float = 0.0
var start_delay_finished: bool = false
var arena_min: Vector2 = Vector2(-500, -500)
var arena_max: Vector2 = Vector2(500, 500)

# HUD/debug/cache
var debug_overlay_visible: bool = false
var vignette_rect: ColorRect = null
var floor_overlay: ColorRect = null
var debug_container: VBoxContainer = null
var momentum_label: Label = null
var music_system_ref: MusicSystem = null

# Camera follow runtime
var camera_follow_pos: Vector2 = Vector2.ZERO
var camera_follow_initialized: bool = false

# Cached textures for floor patches
var cached_white_pixel_tex: ImageTexture = null
var cached_black_pixel_tex: ImageTexture = null

# Runtime toggles
var enemy_weapons_enabled: bool = false

# Runtime budget frame stats (AI/pathing scheduler)
var runtime_budget_last_frame: Dictionary = {}
