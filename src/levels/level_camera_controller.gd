extends RefCounted
class_name LevelCameraController

const CAMERA_FOLLOW_LERP_MOVING = 2.5
const CAMERA_FOLLOW_LERP_STOPPING = 1.0
const CAMERA_VELOCITY_EPSILON = 6.0


func update_follow(ctx, delta: float) -> void:
	if not ctx.player or not ctx.camera:
		return
	if not ctx.camera_follow_initialized:
		ctx.camera_follow_pos = ctx.player.position
		ctx.camera_follow_initialized = true
	var speed = ctx.player.velocity.length()
	var follow_speed = CAMERA_FOLLOW_LERP_MOVING if speed > CAMERA_VELOCITY_EPSILON else CAMERA_FOLLOW_LERP_STOPPING
	var w = clampf(1.0 - exp(-follow_speed * delta), 0.0, 1.0)
	ctx.camera_follow_pos = ctx.camera_follow_pos.lerp(ctx.player.position, w)
	ctx.camera.position = ctx.camera_follow_pos
	ctx.camera.rotation = 0
	if ctx.camera_shake:
		ctx.camera_shake.update(delta)


func reset_follow(ctx) -> void:
	if not ctx.player or not ctx.camera:
		return
	ctx.camera.enabled = true
	ctx.camera.make_current()
	ctx.camera_follow_pos = ctx.player.position
	ctx.camera_follow_initialized = true
	ctx.camera.position = ctx.camera_follow_pos
	ctx.camera.rotation = 0
