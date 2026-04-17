## Player — 8-direction smooth movement, pixel-perfect collision, animation.
##
## Attach to a CharacterBody2D. Expects:
##   AnimatedSprite2D  as $AnimatedSprite2D
##   RayCast2D         as $InteractRay
##   Timer             as $StepTimer   (footstep sound pacing)
##
## Animation naming convention:
##   idle_down / idle_up / idle_left / idle_right
##   walk_down / walk_up / walk_left / walk_right
## If your SpriteFrames only has four directions, that is fine — the
## _play_anim helper falls back to "idle" if the exact name is missing.
extends CharacterBody2D

# ---------------------------------------------------------------------------
# Exported tunables — adjust in the Inspector without touching code.
# ---------------------------------------------------------------------------
## Pixels per second at normal walk speed.
@export var walk_speed  : float = 80.0
## Multiplier applied on top of walk_speed while the run button is held.
@export var run_mult    : float = 1.6
## Tile size in pixels — must match the TileSet.
@export var tile_size   : int   = 16

# ---------------------------------------------------------------------------
# Node references (populated at ready via @onready)
# ---------------------------------------------------------------------------
@onready var sprite      : AnimatedSprite2D = $AnimatedSprite2D
@onready var interact_ray: RayCast2D        = $InteractRay
@onready var step_timer  : Timer            = $StepTimer

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
## Movement is disabled while this is true (cutscenes, dialogue, menus).
var locked       : bool    = false
## Last non-zero direction — used for idle animation and interact ray.
var facing       : Vector2 = Vector2.DOWN
var _is_running  : bool    = false

# ---------------------------------------------------------------------------
# _physics_process — called every physics tick (60 Hz)
# ---------------------------------------------------------------------------
func _physics_process(_delta: float) -> void:
	# Respect locks from dialogue / cutscenes.
	if locked or StoryManager.is_in_dialogue():
		velocity = Vector2.ZERO
		_play_anim("idle_" + _dir_name())
		return

	var dir : Vector2 = _read_input()

	if dir != Vector2.ZERO:
		# Remember the last direction for facing / idle / interact.
		facing      = dir
		_is_running = Input.is_action_pressed("cancel")  # B-button = run

		var speed : float = walk_speed * (run_mult if _is_running else 1.0)
		# Normalise so diagonal movement is not faster than cardinal.
		velocity    = dir.normalized() * speed
		_play_anim("walk_" + _dir_name())
		_point_interact_ray()
	else:
		velocity = Vector2.ZERO
		_play_anim("idle_" + _dir_name())

	move_and_slide()

	# Persist tile-space position to GameManager every frame so saving
	# mid-dungeon always records the correct location.
	GameManager.player_position = position / float(tile_size)

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if locked:
		return
	if event.is_action_pressed("interact"):
		_try_interact()

## Returns a raw (possibly diagonal) direction vector from current input.
func _read_input() -> Vector2:
	var dir : Vector2 = Vector2.ZERO
	if Input.is_action_pressed("move_right"): dir.x += 1.0
	if Input.is_action_pressed("move_left"):  dir.x -= 1.0
	if Input.is_action_pressed("move_down"):  dir.y += 1.0
	if Input.is_action_pressed("move_up"):    dir.y -= 1.0
	return dir

# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------
func _point_interact_ray() -> void:
	# Keep the ray aimed one tile in the direction the player faces.
	interact_ray.target_position = facing.normalized() * float(tile_size)

func _try_interact() -> void:
	_point_interact_ray()
	interact_ray.force_raycast_update()
	if interact_ray.is_colliding():
		var obj : Object = interact_ray.get_collider()
		if obj.has_method("interact"):
			obj.interact(self)

# ---------------------------------------------------------------------------
# Animation helpers
# ---------------------------------------------------------------------------

## Returns the short direction name used in animation keys.
func _dir_name() -> String:
	# Prefer horizontal when moving diagonally so it looks responsive.
	if facing.x > 0.1:   return "right"
	if facing.x < -0.1:  return "left"
	if facing.y < -0.1:  return "up"
	return "down"

## Plays `anim` if it exists; falls back through sensible alternatives.
func _play_anim(anim: String) -> void:
	if not sprite or not sprite.sprite_frames:
		return
	if sprite.sprite_frames.has_animation(anim):
		if sprite.animation != anim:
			sprite.play(anim)
		return
	# Fallback: try direction-agnostic "idle" / "walk".
	var base : String = anim.split("_")[0]
	if sprite.sprite_frames.has_animation(base):
		if sprite.animation != base:
			sprite.play(base)
		return
	# Last resort — play whatever is available.
	if sprite.sprite_frames.has_animation("idle"):
		sprite.play("idle")

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Prevent all player movement (e.g. during cutscenes or dialogue).
func lock_movement() -> void:
	locked   = true
	velocity = Vector2.ZERO

## Re-enable player movement.
func unlock_movement() -> void:
	locked = false

## Instantly move the player to a tile coordinate.
func teleport_to(tile_pos: Vector2) -> void:
	position                 = tile_pos * float(tile_size)
	GameManager.player_position = tile_pos
