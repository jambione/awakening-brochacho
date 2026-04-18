## AssetPainter — in-game pixel sprite editor.
##
## Tools:
##   1 Pencil   2 Eraser   3 Fill   4 Eyedrop   5 Line   6 Rect   7 RectFill
##
## Keyboard:
##   Ctrl+S  Save PNG        Ctrl+L  Load latest PNG
##   Ctrl+N  New canvas      Ctrl+Z  Undo    Ctrl+Shift+Z  Redo
##   G       Toggle grid     +/-     Zoom in/out
##   [/]     Cycle palette   Tab     Swap primary/secondary
##   H       Flip horizontal mirror  V  Flip vertical mirror
##
## Left-click = primary colour.   Right-click = secondary colour.
## Line/Rect/RectFill show a live preview while dragging; commit on release.
extends Control

# ---------------------------------------------------------------------------
# Inspector tunables
# ---------------------------------------------------------------------------
@export var canvas_width  : int = 16
@export var canvas_height : int = 16
@export var pixel_size    : int = 16   ## Screen pixels per canvas pixel.

# ---------------------------------------------------------------------------
# Node references (must match AssetPainter.tscn)
# ---------------------------------------------------------------------------
@onready var canvas_display  : TextureRect   = $UI/Main/CanvasContainer/Canvas
@onready var grid_overlay    : Control       = $UI/Main/CanvasContainer/GridOverlay
@onready var color_palette   : GridContainer = $UI/Left/ColorPalette
@onready var tool_bar        : HBoxContainer = $UI/Main/Top/ToolBar
@onready var status_bar      : Label         = $UI/Main/Bottom/Status
@onready var file_name_input : LineEdit      = $UI/Main/Top/FileNameInput
@onready var canvas_size_x   : SpinBox       = $UI/Main/Top/CanvasSizeX
@onready var canvas_size_y   : SpinBox       = $UI/Main/Top/CanvasSizeY
@onready var primary_swatch  : ColorRect     = $UI/Left/Swatches/Primary
@onready var secondary_swatch: ColorRect     = $UI/Left/Swatches/Secondary
@onready var preview_rect    : TextureRect   = $UI/Left/Preview

# ---------------------------------------------------------------------------
# Tool enum
# ---------------------------------------------------------------------------
enum Tool { PENCIL, ERASER, FILL, EYEDROP, LINE, RECT, RECT_FILL }

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const SAVE_PATH : String   = "user://sprites/"
const MAX_UNDO  : int      = 40
const INVALID_PX: Vector2i = Vector2i(-1, -1)

## 32-colour Link's Awakening-inspired palette — vivid, chunky, retro.
const PALETTE : Array[Color] = [
	Color("#000000"), Color("#ffffff"), Color("#ff0000"), Color("#00cc00"),
	Color("#0044ff"), Color("#ffff00"), Color("#ff8800"), Color("#cc00cc"),
	Color("#00cccc"), Color("#884400"), Color("#ff88aa"), Color("#88ff88"),
	Color("#88aaff"), Color("#ffcc88"), Color("#aaaaaa"), Color("#444444"),
	Color("#220044"), Color("#002244"), Color("#003322"), Color("#442200"),
	Color("#660000"), Color("#006600"), Color("#000066"), Color("#555500"),
	Color("#ff4444"), Color("#44ff44"), Color("#4488ff"), Color("#ffaa44"),
	Color("#cc88ff"), Color("#88ffff"), Color("#ffccff"), Color("#ccffcc"),
]

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var current_tool    : Tool           = Tool.PENCIL
var primary_color   : Color          = Color.WHITE
var secondary_color : Color          = Color.BLACK
var palette_idx     : int            = 1
var pixel_data      : PackedColorArray
var canvas_image    : Image
var canvas_texture  : ImageTexture
var undo_stack      : Array[PackedColorArray] = []
var redo_stack      : Array[PackedColorArray] = []
var tool_start      : Vector2i       = INVALID_PX
var is_drawing      : bool           = false
var show_grid       : bool           = true

## Captured at the start of LINE / RECT / RECT_FILL so preview can be redrawn
## each motion event without permanently dirtying pixel_data until release.
var stroke_snapshot : PackedColorArray
## Colour committed at mouse-press so right-click release uses the same colour.
var drawing_color   : Color          = Color.WHITE

## Mirror drawing axes — toggled with H / V keys.
var mirror_h        : bool           = false
var mirror_v        : bool           = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_PATH)
	_init_canvas(canvas_width, canvas_height)
	_build_palette()
	_build_toolbar()
	_update_swatches()
	_set_status("Asset Painter  |  1-7 Tools  G Grid  +/- Zoom  Tab Swap  H/V Mirror  Ctrl+S Save")

# ---------------------------------------------------------------------------
# Canvas initialisation
# ---------------------------------------------------------------------------

func _init_canvas(w: int, h: int) -> void:
	canvas_width  = w
	canvas_height = h
	pixel_data    = PackedColorArray()
	pixel_data.resize(w * h)
	pixel_data.fill(Color(0.0, 0.0, 0.0, 0.0))

	canvas_image   = Image.create(w, h, false, Image.FORMAT_RGBA8)
	canvas_texture = ImageTexture.create_from_image(canvas_image)
	canvas_display.texture             = canvas_texture
	canvas_display.custom_minimum_size = Vector2(float(w * pixel_size), float(h * pixel_size))

	if preview_rect:
		preview_rect.texture = canvas_texture

	_refresh_texture()
	_queue_redraw_grid()

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# ── Keyboard ────────────────────────────────────────────────────────────
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: _set_tool(Tool.PENCIL)
			KEY_2: _set_tool(Tool.ERASER)
			KEY_3: _set_tool(Tool.FILL)
			KEY_4: _set_tool(Tool.EYEDROP)
			KEY_5: _set_tool(Tool.LINE)
			KEY_6: _set_tool(Tool.RECT)
			KEY_7: _set_tool(Tool.RECT_FILL)
			KEY_G:
				show_grid = not show_grid
				_queue_redraw_grid()
				_set_status("Grid %s" % ("on" if show_grid else "off"))
			KEY_H:
				mirror_h = not mirror_h
				_set_status("Mirror H %s" % ("on" if mirror_h else "off"))
			KEY_V:
				mirror_v = not mirror_v
				_set_status("Mirror V %s" % ("on" if mirror_v else "off"))
			KEY_TAB:
				var tmp : Color = primary_color
				primary_color   = secondary_color
				secondary_color = tmp
				_update_swatches()
				_set_status("Colors swapped")
			KEY_EQUAL:   # + zoom in
				pixel_size = min(pixel_size + 2, 32)
				_resize_canvas_display()
			KEY_MINUS:   # - zoom out
				pixel_size = max(pixel_size - 2, 4)
				_resize_canvas_display()
			KEY_BRACKETRIGHT:
				palette_idx   = (palette_idx + 1) % PALETTE.size()
				primary_color = PALETTE[palette_idx]
				_update_swatches()
				_set_status("Palette → #%s" % primary_color.to_html(false))
			KEY_BRACKETLEFT:
				palette_idx   = (palette_idx - 1 + PALETTE.size()) % PALETTE.size()
				primary_color = PALETTE[palette_idx]
				_update_swatches()
				_set_status("Palette → #%s" % primary_color.to_html(false))
			KEY_S:
				if event.ctrl_pressed: _save_sprite()
			KEY_L:
				if event.ctrl_pressed: _load_latest_sprite()
			KEY_N:
				if event.ctrl_pressed: _new_canvas()
			KEY_Z:
				if event.ctrl_pressed and event.shift_pressed: _redo()
				elif event.ctrl_pressed: _undo()

	# ── Mouse buttons ────────────────────────────────────────────────────────
	if event is InputEventMouseButton:
		var px : Vector2i = _screen_to_pixel(event.position)

		if event.pressed:
			if px == INVALID_PX:
				return
			is_drawing    = true
			tool_start    = px
			drawing_color = primary_color if event.button_index == MOUSE_BUTTON_LEFT else secondary_color

			match current_tool:
				Tool.EYEDROP:
					# Eyedrop never modifies pixels — no undo needed.
					_apply_tool(px, drawing_color)
				Tool.LINE, Tool.RECT, Tool.RECT_FILL:
					# Capture clean state before the stroke; apply on release.
					_push_undo()
					stroke_snapshot = pixel_data.duplicate()
				_:
					_push_undo()
					_apply_tool(px, drawing_color)

		else:
			# Mouse release — commit LINE / RECT / RECT_FILL.
			if current_tool in [Tool.LINE, Tool.RECT, Tool.RECT_FILL] and is_drawing and tool_start != INVALID_PX:
				var release_px : Vector2i = px if px != INVALID_PX else tool_start
				pixel_data = stroke_snapshot.duplicate()
				_commit_shape(tool_start, release_px, drawing_color)
				_refresh_texture()

			is_drawing = false
			tool_start = INVALID_PX

	# ── Mouse motion ─────────────────────────────────────────────────────────
	if event is InputEventMouseMotion:
		var px : Vector2i = _screen_to_pixel(event.position)

		# Always show coordinates while hovering.
		if px != INVALID_PX:
			var hover_col : Color = _get_pixel(px.x, px.y)
			_set_status("[%d, %d]  #%s  | Tool: %s%s%s" % [
				px.x, px.y, hover_col.to_html(false),
				Tool.keys()[current_tool],
				"  H" if mirror_h else "",
				"  V" if mirror_v else "",
			])

		if not is_drawing:
			return
		if px == INVALID_PX:
			return

		var col : Color = primary_color if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else secondary_color

		match current_tool:
			Tool.PENCIL, Tool.ERASER:
				_apply_tool(px, col)
			Tool.EYEDROP:
				_apply_tool(px, col)
			Tool.LINE, Tool.RECT, Tool.RECT_FILL:
				# Live preview: restore baseline and redraw candidate shape.
				if tool_start != INVALID_PX:
					pixel_data = stroke_snapshot.duplicate()
					_commit_shape(tool_start, px, drawing_color)
					_refresh_texture()

# ---------------------------------------------------------------------------
# Tool dispatch
# ---------------------------------------------------------------------------

func _apply_tool(px: Vector2i, col: Color) -> void:
	match current_tool:
		Tool.PENCIL:
			_paint_with_mirror(px, col)
		Tool.ERASER:
			_paint_with_mirror(px, Color(0.0, 0.0, 0.0, 0.0))
		Tool.FILL:
			_flood_fill(px, col)
		Tool.EYEDROP:
			_eyedrop(px)
			return   # Eyedrop does not write pixels; skip refresh.
		Tool.LINE, Tool.RECT, Tool.RECT_FILL:
			pass   # Handled at mouse-button level.
	_refresh_texture()

## Commit the final shape for LINE / RECT / RECT_FILL.
func _commit_shape(a: Vector2i, b: Vector2i, col: Color) -> void:
	match current_tool:
		Tool.LINE:      _draw_line_bresenham(a, b, col)
		Tool.RECT:      _draw_rect_outline(a, b, col)
		Tool.RECT_FILL: _draw_rect_filled(a, b, col)

# ---------------------------------------------------------------------------
# Pixel operations
# ---------------------------------------------------------------------------

func _set_pixel(x: int, y: int, col: Color) -> void:
	if x < 0 or x >= canvas_width or y < 0 or y >= canvas_height:
		return
	pixel_data[y * canvas_width + x] = col

func _get_pixel(x: int, y: int) -> Color:
	if x < 0 or x >= canvas_width or y < 0 or y >= canvas_height:
		return Color(0.0, 0.0, 0.0, 0.0)
	return pixel_data[y * canvas_width + x]

## Write a pixel and apply mirror axes if enabled.
func _paint_with_mirror(px: Vector2i, col: Color) -> void:
	_set_pixel(px.x, px.y, col)
	if mirror_h:
		_set_pixel(canvas_width - 1 - px.x, px.y, col)
	if mirror_v:
		_set_pixel(px.x, canvas_height - 1 - px.y, col)
	if mirror_h and mirror_v:
		_set_pixel(canvas_width - 1 - px.x, canvas_height - 1 - px.y, col)

func _eyedrop(px: Vector2i) -> void:
	var picked : Color = _get_pixel(px.x, px.y)
	primary_color = picked
	# Sync palette index to the closest palette entry.
	var best_dist : float = INF
	var best_idx  : int   = palette_idx
	for i : int in PALETTE.size():
		var d : float = (abs(picked.r - PALETTE[i].r)
			+ abs(picked.g - PALETTE[i].g)
			+ abs(picked.b - PALETTE[i].b))
		if d < best_dist:
			best_dist = d
			best_idx  = i
	palette_idx = best_idx
	_update_swatches()
	_set_status("Picked: #%s" % picked.to_html(false))

# ---------------------------------------------------------------------------
# Drawing primitives
# ---------------------------------------------------------------------------

func _draw_line_bresenham(a: Vector2i, b: Vector2i, col: Color) -> void:
	var dx : int = abs(b.x - a.x)
	var dy : int = abs(b.y - a.y)
	var sx : int = 1 if a.x < b.x else -1
	var sy : int = 1 if a.y < b.y else -1
	var err: int = dx - dy
	var cx : int = a.x
	var cy : int = a.y
	while true:
		_set_pixel(cx, cy, col)
		if cx == b.x and cy == b.y:
			break
		var e2 : int = 2 * err
		if e2 > -dy: err -= dy; cx += sx
		if e2 <  dx: err += dx; cy += sy

func _draw_rect_outline(a: Vector2i, b: Vector2i, col: Color) -> void:
	var x0 : int = min(a.x, b.x)
	var y0 : int = min(a.y, b.y)
	var x1 : int = max(a.x, b.x)
	var y1 : int = max(a.y, b.y)
	for x : int in range(x0, x1 + 1):
		_set_pixel(x, y0, col)
		_set_pixel(x, y1, col)
	for y : int in range(y0, y1 + 1):
		_set_pixel(x0, y, col)
		_set_pixel(x1, y, col)

func _draw_rect_filled(a: Vector2i, b: Vector2i, col: Color) -> void:
	var x0 : int = min(a.x, b.x)
	var y0 : int = min(a.y, b.y)
	var x1 : int = max(a.x, b.x)
	var y1 : int = max(a.y, b.y)
	for y : int in range(y0, y1 + 1):
		for x : int in range(x0, x1 + 1):
			_set_pixel(x, y, col)

func _flood_fill(start: Vector2i, new_col: Color) -> void:
	var target : Color         = _get_pixel(start.x, start.y)
	if target == new_col:
		return
	var queue  : Array[Vector2i] = [start]
	var visited: Dictionary      = {}
	var dirs   : Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	while queue.size() > 0:
		var px  : Vector2i = queue.pop_front()
		var key : String   = "%d,%d" % [px.x, px.y]
		if visited.has(key): continue
		visited[key] = true
		if _get_pixel(px.x, px.y) != target: continue
		_set_pixel(px.x, px.y, new_col)
		for d : Vector2i in dirs:
			var np : Vector2i = px + d
			if np.x >= 0 and np.x < canvas_width and np.y >= 0 and np.y < canvas_height:
				queue.append(np)

# ---------------------------------------------------------------------------
# Texture refresh
# ---------------------------------------------------------------------------

func _refresh_texture() -> void:
	for y : int in canvas_height:
		for x : int in canvas_width:
			canvas_image.set_pixel(x, y, pixel_data[y * canvas_width + x])
	canvas_texture.update(canvas_image)
	if preview_rect:
		preview_rect.texture = canvas_texture

# ---------------------------------------------------------------------------
# Grid overlay
# ---------------------------------------------------------------------------

func _queue_redraw_grid() -> void:
	if grid_overlay:
		grid_overlay.queue_redraw()

func draw_grid(ci: CanvasItem) -> void:
	if not show_grid:
		return
	var col : Color = Color(1.0, 1.0, 1.0, 0.15)
	var w   : float = float(canvas_width  * pixel_size)
	var h   : float = float(canvas_height * pixel_size)
	var ps  : float = float(pixel_size)
	for x : int in canvas_width + 1:
		ci.draw_line(Vector2(x * ps, 0.0), Vector2(x * ps, h), col)
	for y : int in canvas_height + 1:
		ci.draw_line(Vector2(0.0, y * ps), Vector2(w, y * ps), col)

# ---------------------------------------------------------------------------
# Undo / Redo
# ---------------------------------------------------------------------------

func _push_undo() -> void:
	undo_stack.append(pixel_data.duplicate())
	if undo_stack.size() > MAX_UNDO:
		undo_stack.pop_front()
	redo_stack.clear()

func _undo() -> void:
	if undo_stack.is_empty(): return
	redo_stack.append(pixel_data.duplicate())
	pixel_data = undo_stack.pop_back()
	_refresh_texture()
	_set_status("Undo  (%d left)" % undo_stack.size())

func _redo() -> void:
	if redo_stack.is_empty(): return
	undo_stack.append(pixel_data.duplicate())
	pixel_data = redo_stack.pop_back()
	_refresh_texture()
	_set_status("Redo  (%d left)" % redo_stack.size())

# ---------------------------------------------------------------------------
# Save / Load
# ---------------------------------------------------------------------------

func _save_sprite() -> void:
	var name : String = file_name_input.text.strip_edges() if file_name_input else ""
	if name.is_empty():
		name = "sprite"
	var path : String = SAVE_PATH + name + ".png"
	var err  : int    = canvas_image.save_png(path)
	_set_status("Saved: %s" % path if err == OK else "Save failed (err %d)" % err)

func _load_sprite(path: String) -> void:
	if not FileAccess.file_exists(path):
		_set_status("Not found: " + path)
		return
	var img : Image = Image.load_from_file(path)
	if not img:
		_set_status("Load failed")
		return
	_push_undo()
	_init_canvas(img.get_width(), img.get_height())
	for y : int in canvas_height:
		for x : int in canvas_width:
			_set_pixel(x, y, img.get_pixel(x, y))
	_refresh_texture()
	_set_status("Loaded: " + path)

func _load_latest_sprite() -> void:
	var dir : DirAccess = DirAccess.open(SAVE_PATH)
	if not dir: return
	var files : Array[String] = []
	dir.list_dir_begin()
	var fname : String = dir.get_next()
	while fname != "":
		if fname.ends_with(".png"):
			files.append(SAVE_PATH + fname)
		fname = dir.get_next()
	if files.size() > 0:
		files.sort()
		_load_sprite(files.back())

func _new_canvas() -> void:
	var w : int = int(canvas_size_x.value) if canvas_size_x else 16
	var h : int = int(canvas_size_y.value) if canvas_size_y else 16
	w = clamp(w, 1, 128)
	h = clamp(h, 1, 128)
	_push_undo()
	_init_canvas(w, h)
	_set_status("New %d×%d canvas" % [w, h])

# ---------------------------------------------------------------------------
# Palette UI
# ---------------------------------------------------------------------------

func _build_palette() -> void:
	for c : Color in PALETTE:
		var swatch : ColorRect = ColorRect.new()
		swatch.color               = c
		swatch.custom_minimum_size = Vector2(18.0, 18.0)
		swatch.gui_input.connect(_on_palette_input.bind(c))
		color_palette.add_child(swatch)

func _on_palette_input(event: InputEvent, col: Color) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var mbe : InputEventMouseButton = event
	if mbe.button_index == MOUSE_BUTTON_LEFT:
		primary_color = col
		# Sync palette index.
		palette_idx = PALETTE.find(col)
		if palette_idx == -1:
			palette_idx = 0
	elif mbe.button_index == MOUSE_BUTTON_RIGHT:
		secondary_color = col
	_update_swatches()

func _update_swatches() -> void:
	if primary_swatch:
		primary_swatch.color   = primary_color
	if secondary_swatch:
		secondary_swatch.color = secondary_color

# ---------------------------------------------------------------------------
# Toolbar
# ---------------------------------------------------------------------------

func _build_toolbar() -> void:
	var tool_group : ButtonGroup = ButtonGroup.new()
	var entries : Array = [
		["Pencil(1)",   Tool.PENCIL],   ["Eraser(2)",   Tool.ERASER],
		["Fill(3)",     Tool.FILL],     ["Pick(4)",     Tool.EYEDROP],
		["Line(5)",     Tool.LINE],     ["Rect(6)",     Tool.RECT],
		["RectFill(7)", Tool.RECT_FILL],
	]
	for entry : Array in entries:
		var btn : Button = Button.new()
		btn.text         = str(entry[0])
		btn.toggle_mode  = true
		btn.button_group = tool_group
		var t : Tool = entry[1] as Tool
		btn.pressed.connect(_set_tool.bind(t))
		tool_bar.add_child(btn)

	# Mirror toggles
	for data : Array in [["H-Mirror", func() -> void: mirror_h = not mirror_h; _set_status("Mirror H %s" % ("on" if mirror_h else "off"))],
						  ["V-Mirror", func() -> void: mirror_v = not mirror_v; _set_status("Mirror V %s" % ("on" if mirror_v else "off"))]]:
		var btn : Button = Button.new()
		btn.text        = str(data[0])
		btn.toggle_mode = true
		btn.pressed.connect(data[1] as Callable)
		tool_bar.add_child(btn)

	for data : Array in [["Save(Ctrl+S)", _save_sprite], ["Load(Ctrl+L)", _load_latest_sprite], ["New(Ctrl+N)", _new_canvas]]:
		var btn : Button = Button.new()
		btn.text = str(data[0])
		btn.pressed.connect(data[1] as Callable)
		tool_bar.add_child(btn)

func _set_tool(t: Tool) -> void:
	current_tool = t
	_set_status("Tool: %s" % Tool.keys()[t])

# ---------------------------------------------------------------------------
# Zoom / resize
# ---------------------------------------------------------------------------

func _resize_canvas_display() -> void:
	canvas_display.custom_minimum_size = Vector2(
		float(canvas_width  * pixel_size),
		float(canvas_height * pixel_size)
	)
	_queue_redraw_grid()
	_set_status("Zoom: %dpx/pixel" % pixel_size)

# ---------------------------------------------------------------------------
# Screen → pixel conversion
# ---------------------------------------------------------------------------

func _screen_to_pixel(_screen_pos: Vector2) -> Vector2i:
	if not canvas_display:
		return INVALID_PX
	var local : Vector2 = canvas_display.get_local_mouse_position()
	var px    : int     = int(local.x) / pixel_size
	var py    : int     = int(local.y) / pixel_size
	if px < 0 or px >= canvas_width or py < 0 or py >= canvas_height:
		return INVALID_PX
	return Vector2i(px, py)

func _set_status(msg: String) -> void:
	if status_bar:
		status_bar.text = msg
