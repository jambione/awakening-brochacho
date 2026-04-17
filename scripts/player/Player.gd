extends CharacterBody2D

# ── Config ────────────────────────────────────────────────────────────────────
@export var move_speed: float = 80.0   # pixels per second (fits 16-px grid nicely)
@export var tile_size:  int   = 16

# ── Node refs ─────────────────────────────────────────────────────────────────
@onready var sprite:          AnimatedSprite2D = $AnimatedSprite2D
@onready var interact_ray:    RayCast2D        = $InteractRay
@onready var step_timer:      Timer            = $StepTimer

# ── State ─────────────────────────────────────────────────────────────────────
enum State { IDLE, WALK, INTERACT, LOCKED }
var state:     State   = State.IDLE
var facing:    Vector2 = Vector2.DOWN
var is_running: bool   = false

# ── Movement ──────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if state == State.LOCKED or StoryManager.is_in_dialogue():
		velocity = Vector2.ZERO
		_play_anim("idle")
		return

	var dir := _get_input_direction()

	if dir != Vector2.ZERO:
		facing   = dir.normalized()
		velocity = facing * (move_speed * (1.5 if is_running else 1.0))
		state    = State.WALK
		_update_interact_ray()
		_play_walk_anim(dir)
	else:
		velocity = Vector2.ZERO
		state    = State.IDLE
		_play_anim("idle_%s" % _dir_name())

	move_and_slide()

	# Save position to GameManager every second (handled by timer in scene)
	GameManager.player_position = position / tile_size

func _unhandled_input(event: InputEvent) -> void:
	if state == State.LOCKED:
		return
	if event.is_action_pressed("interact"):
		_try_interact()

# ── Input helpers ─────────────────────────────────────────────────────────────
func _get_input_direction() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_right"): dir.x += 1
	if Input.is_action_pressed("move_left"):  dir.x -= 1
	if Input.is_action_pressed("move_down"):  dir.y += 1
	if Input.is_action_pressed("move_up"):    dir.y -= 1
	# Normalize so diagonal isn't faster, but keep 8-way feel
	return dir.normalized() if dir.length() > 0 else dir

# ── Interaction ───────────────────────────────────────────────────────────────
func _update_interact_ray() -> void:
	interact_ray.target_position = facing * tile_size

func _try_interact() -> void:
	interact_ray.target_position = facing * tile_size
	interact_ray.force_raycast_update()
	if interact_ray.is_colliding():
		var obj := interact_ray.get_collider()
		if obj.has_method("interact"):
			obj.interact(self)

# ── Animation ─────────────────────────────────────────────────────────────────
func _dir_name() -> String:
	if   facing == Vector2.UP:    return "up"
	elif facing == Vector2.DOWN:  return "down"
	elif facing == Vector2.LEFT:  return "left"
	else:                          return "right"

func _play_walk_anim(dir: Vector2) -> void:
	var d := "right" if dir.x > 0 else ("left" if dir.x < 0 else ("up" if dir.y < 0 else "down"))
	_play_anim("walk_%s" % d)

func _play_anim(anim: String) -> void:
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		if sprite.animation != anim:
			sprite.play(anim)
	elif sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("idle"):
		if sprite.animation != "idle":
			sprite.play("idle")

# ── Public API ────────────────────────────────────────────────────────────────
func lock_movement() -> void:
	state = State.LOCKED
	velocity = Vector2.ZERO

func unlock_movement() -> void:
	state = State.IDLE

func teleport_to(tile_pos: Vector2) -> void:
	position = tile_pos * tile_size
	GameManager.player_position = tile_pos
