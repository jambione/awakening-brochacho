## TouchController — floating joystick + context action button for mobile.
##
## Autoloaded at layer 99 (below EraLayer at 100). Injects standard InputEventAction
## events so Player.gd and DialoguePlayer.gd need zero touch-specific code.
##
## Joystick:  spawns wherever the left-half thumb lands (floating origin).
##            Deflection 0–60 % = walk, 60–100 % = run.
## Action:    right-half tap fires "interact" (advance dialogue, open chest, talk).
## Both controls are invisible on non-touch platforms at runtime.
extends Node

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------
const JOY_RADIUS_FRAC : float = 0.12   ## Joystick ring radius as fraction of screen width.
const BTN_RADIUS_FRAC : float = 0.09   ## Action button radius as fraction of screen width.
const BTN_MARGIN_FRAC : float = 0.06   ## Distance from right/bottom edge as fraction of screen height.
const RUN_THRESHOLD   : float = 0.60   ## Deflection fraction that switches walk → run.
const FADE_ALPHA      : float = 0.55   ## Resting alpha for controls.

# ---------------------------------------------------------------------------
# Node structure (built programmatically — no .tscn required)
# ---------------------------------------------------------------------------
var _canvas        : CanvasLayer
var _joy_base      : Polygon2D
var _joy_knob      : Polygon2D
var _action_btn    : Polygon2D

# ---------------------------------------------------------------------------
# Touch state
# ---------------------------------------------------------------------------
var _joy_touch_id  : int     = -1
var _joy_origin    : Vector2 = Vector2.ZERO
var _btn_touch_id  : int     = -1
var _joy_active    : bool    = false

# ---------------------------------------------------------------------------
# Built-ins
# ---------------------------------------------------------------------------
func _ready() -> void:
	if not _is_touch_platform():
		return
	_build_canvas()
	_build_joystick()
	_build_action_button()
	_hide_joystick()
	# Connect to era changes for future skin swaps.
	if EraManager.has_signal("era_changed"):
		EraManager.era_changed.connect(_on_era_changed)

func _input(event: InputEvent) -> void:
	if not _is_touch_platform():
		return
	if event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_drag(event as InputEventScreenDrag)

# ---------------------------------------------------------------------------
# Touch handlers
# ---------------------------------------------------------------------------

func _handle_touch(touch: InputEventScreenTouch) -> void:
	var sw : float = float(DisplayServer.window_get_size().x)

	if touch.pressed:
		if touch.position.x < sw * 0.5:
			# Left half → spawn joystick.
			if _joy_touch_id == -1:
				_joy_touch_id = touch.index
				_joy_origin   = touch.position
				_show_joystick(touch.position)
		else:
			# Right half → action button.
			if _btn_touch_id == -1:
				_btn_touch_id = touch.index
				_fire_interact()
	else:
		if touch.index == _joy_touch_id:
			_joy_touch_id = -1
			_joy_active   = false
			_release_all_directions()
			_hide_joystick()
		elif touch.index == _btn_touch_id:
			_btn_touch_id = -1

func _handle_drag(drag: InputEventScreenDrag) -> void:
	if drag.index != _joy_touch_id:
		return
	var delta     : Vector2 = drag.position - _joy_origin
	var joy_r     : float   = float(DisplayServer.window_get_size().x) * JOY_RADIUS_FRAC
	var deflect   : float   = clampf(delta.length() / joy_r, 0.0, 1.0)
	var direction : Vector2 = delta.normalized() if delta.length() > 4.0 else Vector2.ZERO

	# Move the knob visually (clamped to ring).
	if _joy_knob:
		_joy_knob.position = _joy_origin + direction * minf(delta.length(), joy_r)

	# Inject directional actions.
	_release_all_directions()
	if direction.length() > 0.1:
		var snapped : Vector2 = _snap_8(direction)
		if snapped.y < -0.3: _press_action("move_up")
		if snapped.y >  0.3: _press_action("move_down")
		if snapped.x < -0.3: _press_action("move_left")
		if snapped.x >  0.3: _press_action("move_right")

	# Run when thumb pushes to outer 40 % of ring.
	if deflect >= RUN_THRESHOLD:
		Input.action_press("cancel")
	else:
		Input.action_release("cancel")

# ---------------------------------------------------------------------------
# Input injection helpers
# ---------------------------------------------------------------------------

func _press_action(action: String) -> void:
	Input.action_press(action)

func _release_all_directions() -> void:
	for a : String in ["move_up", "move_down", "move_left", "move_right", "cancel"]:
		Input.action_release(a)

func _fire_interact() -> void:
	var ev : InputEventAction = InputEventAction.new()
	ev.action  = "interact"
	ev.pressed = true
	get_viewport().push_input(ev, true)

# ---------------------------------------------------------------------------
# 8-directional snap
# ---------------------------------------------------------------------------

func _snap_8(dir: Vector2) -> Vector2:
	var angle  : float = dir.angle()
	var sector : int   = int(round(angle / (PI / 4.0)))
	return Vector2(cos(sector * PI / 4.0), sin(sector * PI / 4.0))

# ---------------------------------------------------------------------------
# Visual construction
# ---------------------------------------------------------------------------

func _build_canvas() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer                  = 99
	_canvas.follow_viewport_enabled = false
	add_child(_canvas)

func _build_joystick() -> void:
	var joy_r : float = float(DisplayServer.window_get_size().x) * JOY_RADIUS_FRAC

	_joy_base = _make_circle(joy_r, Color(1, 1, 1, 0.25))
	_canvas.add_child(_joy_base)

	var knob_r : float = joy_r * 0.40
	_joy_knob = _make_circle(knob_r, Color(1, 1, 1, FADE_ALPHA))
	_canvas.add_child(_joy_knob)

func _build_action_button() -> void:
	var sh    : float  = float(DisplayServer.window_get_size().y)
	var sw    : float  = float(DisplayServer.window_get_size().x)
	var btn_r : float  = sw * BTN_RADIUS_FRAC
	var margin: float  = sh * BTN_MARGIN_FRAC

	_action_btn          = _make_circle(btn_r, Color(1, 0.85, 0.2, FADE_ALPHA))
	_action_btn.position = Vector2(sw - margin - btn_r, sh - margin - btn_r)
	_canvas.add_child(_action_btn)

## Build a filled circle Polygon2D with `segments` vertices.
func _make_circle(radius: float, color: Color, segments: int = 24) -> Polygon2D:
	var poly     : Polygon2D       = Polygon2D.new()
	var points   : PackedVector2Array = PackedVector2Array()
	for i : int in range(segments):
		var a : float = (TAU * float(i)) / float(segments)
		points.append(Vector2(cos(a), sin(a)) * radius)
	poly.polygon = points
	poly.color   = color
	return poly

# ---------------------------------------------------------------------------
# Joystick show / hide
# ---------------------------------------------------------------------------

func _show_joystick(origin: Vector2) -> void:
	if not _joy_base or not _joy_knob:
		return
	_joy_base.position = origin
	_joy_knob.position = origin
	_joy_base.visible  = true
	_joy_knob.visible  = true
	_joy_active        = true

func _hide_joystick() -> void:
	if _joy_base: _joy_base.visible = false
	if _joy_knob: _joy_knob.visible = false

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------

func _is_touch_platform() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()

# ---------------------------------------------------------------------------
# Era skin (future — swap colors/shapes per era)
# ---------------------------------------------------------------------------

func _on_era_changed(era: int) -> void:
	# Placeholder — era-aware skin swaps go here once art is finalized.
	pass
