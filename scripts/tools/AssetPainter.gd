extends Control

# ── Config ────────────────────────────────────────────────────────────────────
@export var canvas_width:  int = 16
@export var canvas_height: int = 16
@export var pixel_size:    int = 16   # display scale — each pixel = 16x16 screen px

# ── Node refs ─────────────────────────────────────────────────────────────────
@onready var canvas_display: TextureRect   = $UI/Main/CanvasContainer/Canvas
@onready var color_palette:  GridContainer = $UI/Left/ColorPalette
@onready var tool_bar:       HBoxContainer = $UI/Main/Top/ToolBar
@onready var status_bar:     Label         = $UI/Main/Bottom/Status
@onready var file_name_input: LineEdit     = $UI/Main/Top/FileNameInput
@onready var canvas_size_x:  SpinBox      = $UI/Main/Top/CanvasSizeX
@onready var canvas_size_y:  SpinBox      = $UI/Main/Top/CanvasSizeY

# ── State ─────────────────────────────────────────────────────────────────────
enum Tool { PENCIL, ERASER, FILL, EYEDROP, LINE, RECT }
var current_tool:   Tool   = Tool.PENCIL
var primary_color:  Color  = Color.WHITE
var secondary_color: Color = Color.BLACK
var pixel_data:     PackedColorArray
var canvas_texture: ImageTexture
var canvas_image:   Image
var undo_stack:     Array[PackedColorArray] = []
var redo_stack:     Array[PackedColorArray] = []
const MAX_UNDO := 30
const SAVE_PATH := "user://sprites/"

# Line/Rect tool state
var tool_start: Vector2i = Vector2i(-1, -1)
var is_drawing: bool = false

# ── Built-in 16-color CGA/retro palette ───────────────────────────────────────
const PALETTE := [
	Color(0.0,  0.0,  0.0),   # Black
	Color(0.0,  0.0,  0.67),  # Dark Blue
	Color(0.0,  0.67, 0.0),   # Dark Green
	Color(0.0,  0.67, 0.67),  # Dark Cyan
	Color(0.67, 0.0,  0.0),   # Dark Red
	Color(0.67, 0.0,  0.67),  # Dark Magenta
	Color(0.67, 0.33, 0.0),   # Brown
	Color(0.67, 0.67, 0.67),  # Light Gray
	Color(0.33, 0.33, 0.33),  # Dark Gray
	Color(0.33, 0.33, 1.0),   # Blue
	Color(0.33, 1.0,  0.33),  # Green
	Color(0.33, 1.0,  1.0),   # Cyan
	Color(1.0,  0.33, 0.33),  # Red
	Color(1.0,  0.33, 1.0),   # Magenta
	Color(1.0,  1.0,  0.33),  # Yellow
	Color(1.0,  1.0,  1.0),   # White
]

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_PATH)
	_init_canvas(canvas_width, canvas_height)
	_build_palette()
	_build_toolbar()
	_set_status("Asset Painter | Left=Draw Right=Secondary | Ctrl+S=Save Ctrl+Z=Undo")

# ── Canvas init ───────────────────────────────────────────────────────────────
func _init_canvas(w: int, h: int) -> void:
	canvas_width  = w
	canvas_height = h
	pixel_data    = PackedColorArray()
	pixel_data.resize(w * h)
	pixel_data.fill(Color(0, 0, 0, 0))  # Transparent

	canvas_image   = Image.create(w, h, false, Image.FORMAT_RGBA8)
	canvas_texture = ImageTexture.create_from_image(canvas_image)
	canvas_display.texture = canvas_texture
	canvas_display.custom_minimum_size = Vector2(w * pixel_size, h * pixel_size)
	_refresh_texture()

# ── Input ─────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: _set_tool(Tool.PENCIL)
			KEY_2: _set_tool(Tool.ERASER)
			KEY_3: _set_tool(Tool.FILL)
			KEY_4: _set_tool(Tool.EYEDROP)
			KEY_5: _set_tool(Tool.LINE)
			KEY_6: _set_tool(Tool.RECT)
			KEY_S:
				if event.ctrl_pressed: _save_sprite()
			KEY_L:
				if event.ctrl_pressed: _load_sprite_dialog()
			KEY_N:
				if event.ctrl_pressed: _new_canvas()
			KEY_Z:
				if event.ctrl_pressed and event.shift_pressed: _redo()
				elif event.ctrl_pressed: _undo()

	if event is InputEventMouseButton:
		var px: Vector2i = _screen_to_pixel(event.position)
		if px == INVALID_PX:
			return
		if event.pressed:
			_push_undo()
			is_drawing  = true
			tool_start  = px
			if event.button_index == MOUSE_BUTTON_LEFT:
				_apply_tool(px, primary_color)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_apply_tool(px, secondary_color)
		else:
			is_drawing = false
			tool_start = Vector2i(-1, -1)

	if event is InputEventMouseMotion and is_drawing:
		var px: Vector2i = _screen_to_pixel(event.position)
		if px == INVALID_PX:
			return
		var color := primary_color if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else secondary_color
		if current_tool in [Tool.PENCIL, Tool.ERASER]:
			_apply_tool(px, color)

# ── Tool dispatch ─────────────────────────────────────────────────────────────
func _apply_tool(px: Vector2i, color: Color) -> void:
	match current_tool:
		Tool.PENCIL:  _set_pixel(px.x, px.y, color)
		Tool.ERASER:  _set_pixel(px.x, px.y, Color(0, 0, 0, 0))
		Tool.FILL:    _flood_fill(px, color)
		Tool.EYEDROP: _eyedrop(px)
		Tool.LINE:
			if tool_start != Vector2i(-1, -1):
				_draw_line_bresenham(tool_start, px, color)
		Tool.RECT:
			if tool_start != Vector2i(-1, -1):
				_draw_rect_outline(tool_start, px, color)
	_refresh_texture()

# ── Pixel operations ──────────────────────────────────────────────────────────
func _set_pixel(x: int, y: int, color: Color) -> void:
	if x < 0 or x >= canvas_width or y < 0 or y >= canvas_height:
		return
	pixel_data[y * canvas_width + x] = color

func _get_pixel(x: int, y: int) -> Color:
	if x < 0 or x >= canvas_width or y < 0 or y >= canvas_height:
		return Color(0, 0, 0, 0)
	return pixel_data[y * canvas_width + x]

func _eyedrop(px: Vector2i) -> void:
	primary_color = _get_pixel(px.x, px.y)
	_set_status("Eyedrop: %s" % primary_color.to_html())

# ── Bresenham line ────────────────────────────────────────────────────────────
func _draw_line_bresenham(a: Vector2i, b: Vector2i, color: Color) -> void:
	var dx: int = abs(b.x - a.x)
	var dy: int = abs(b.y - a.y)
	var sx: int = 1 if a.x < b.x else -1
	var sy: int = 1 if a.y < b.y else -1
	var err: int = dx - dy
	var cx: int = a.x
	var cy: int = a.y
	while true:
		_set_pixel(cx, cy, color)
		if cx == b.x and cy == b.y:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			cx  += sx
		if e2 < dx:
			err += dx
			cy  += sy

# ── Rect outline ──────────────────────────────────────────────────────────────
func _draw_rect_outline(a: Vector2i, b: Vector2i, color: Color) -> void:
	var x0: int = min(a.x, b.x)
	var y0: int = min(a.y, b.y)
	var x1: int = max(a.x, b.x)
	var y1: int = max(a.y, b.y)
	for x in range(x0, x1 + 1):
		_set_pixel(x, y0, color)
		_set_pixel(x, y1, color)
	for y in range(y0, y1 + 1):
		_set_pixel(x0, y, color)
		_set_pixel(x1, y, color)

# ── Flood fill (BFS) ──────────────────────────────────────────────────────────
func _flood_fill(start: Vector2i, new_color: Color) -> void:
	var target := _get_pixel(start.x, start.y)
	if target == new_color:
		return
	var queue:   Array[Vector2i] = [start]
	var visited: Dictionary      = {}
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	while queue.size() > 0:
		var px: Vector2i = queue.pop_front()
		var key := "%d,%d" % [px.x, px.y]
		if visited.has(key):
			continue
		visited[key] = true
		if _get_pixel(px.x, px.y) != target:
			continue
		_set_pixel(px.x, px.y, new_color)
		for d: Vector2i in dirs:
			var np: Vector2i = px + d
			if np.x >= 0 and np.x < canvas_width and np.y >= 0 and np.y < canvas_height:
				queue.append(np)

# ── Texture update ────────────────────────────────────────────────────────────
func _refresh_texture() -> void:
	for y in canvas_height:
		for x in canvas_width:
			canvas_image.set_pixel(x, y, pixel_data[y * canvas_width + x])
	canvas_texture.update(canvas_image)

# ── Undo / Redo ───────────────────────────────────────────────────────────────
func _push_undo() -> void:
	undo_stack.append(pixel_data.duplicate())
	if undo_stack.size() > MAX_UNDO:
		undo_stack.pop_front()
	redo_stack.clear()

func _undo() -> void:
	if undo_stack.is_empty():
		return
	redo_stack.append(pixel_data.duplicate())
	pixel_data = undo_stack.pop_back()
	_refresh_texture()
	_set_status("Undo")

func _redo() -> void:
	if redo_stack.is_empty():
		return
	undo_stack.append(pixel_data.duplicate())
	pixel_data = redo_stack.pop_back()
	_refresh_texture()
	_set_status("Redo")

# ── Save / Load ───────────────────────────────────────────────────────────────
func _save_sprite() -> void:
	var name := file_name_input.text.strip_edges()
	if name == "":
		name = "sprite"
	var path := SAVE_PATH + name + ".png"
	var err := canvas_image.save_png(path)
	if err == OK:
		_set_status("Saved: %s" % path)
	else:
		_set_status("Save failed: error %d" % err)

func _load_sprite(path: String) -> void:
	if not FileAccess.file_exists(path):
		_set_status("Not found: %s" % path)
		return
	var img := Image.load_from_file(path)
	if not img:
		_set_status("Load failed")
		return
	_init_canvas(img.get_width(), img.get_height())
	for y in canvas_height:
		for x in canvas_width:
			_set_pixel(x, y, img.get_pixel(x, y))
	_refresh_texture()
	_set_status("Loaded: %s" % path)

func _load_sprite_dialog() -> void:
	var dir := DirAccess.open(SAVE_PATH)
	if not dir:
		return
	dir.list_dir_begin()
	var files: Array[String] = []
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".png"):
			files.append(SAVE_PATH + fname)
		fname = dir.get_next()
	if files.size() > 0:
		files.sort()
		_load_sprite(files.back())

func _new_canvas() -> void:
	var w := int(canvas_size_x.value) if canvas_size_x else 16
	var h := int(canvas_size_y.value) if canvas_size_y else 16
	_push_undo()
	_init_canvas(w, h)
	_set_status("New %dx%d canvas" % [w, h])

# ── Palette UI ────────────────────────────────────────────────────────────────
func _build_palette() -> void:
	for c in PALETTE:
		var btn := ColorRect.new()
		btn.color              = c
		btn.custom_minimum_size = Vector2(20, 20)
		btn.gui_input.connect(_on_palette_click.bind(c))
		color_palette.add_child(btn)

func _on_palette_click(event: InputEvent, color: Color) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			primary_color = color
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			secondary_color = color
		_set_status("Colors: L=%s R=%s" % [primary_color.to_html(), secondary_color.to_html()])

# ── Toolbar ───────────────────────────────────────────────────────────────────
func _build_toolbar() -> void:
	var tools := [["Pencil(1)", Tool.PENCIL], ["Eraser(2)", Tool.ERASER],
				  ["Fill(3)", Tool.FILL],   ["Pick(4)", Tool.EYEDROP],
				  ["Line(5)", Tool.LINE],   ["Rect(6)", Tool.RECT]]
	for t in tools:
		var btn := Button.new()
		btn.text = t[0]
		btn.pressed.connect(_set_tool.bind(t[1]))
		tool_bar.add_child(btn)

func _set_tool(tool: Tool) -> void:
	current_tool = tool
	_set_status("Tool: %s" % Tool.keys()[tool])

# ── Helpers ───────────────────────────────────────────────────────────────────
const INVALID_PX := Vector2i(-1, -1)

func _screen_to_pixel(_screen_pos: Vector2) -> Vector2i:
	if not canvas_display:
		return INVALID_PX
	var local := canvas_display.get_local_mouse_position()
	var px := int(local.x / pixel_size)
	var py := int(local.y / pixel_size)
	if px < 0 or px >= canvas_width or py < 0 or py >= canvas_height:
		return INVALID_PX
	return Vector2i(px, py)

func _set_status(msg: String) -> void:
	if status_bar:
		status_bar.text = msg
