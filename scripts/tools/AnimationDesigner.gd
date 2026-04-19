## AnimationDesigner — frame-by-frame pixel animation editor.
##
## Each animation is a named strip of pixel frames (same canvas size).
## Exports a horizontal spritesheet PNG + JSON metadata.
##
## Tools: 1 Pencil  2 Eraser  3 Fill  4 Eyedrop
##
## Keyboard:
##   1-4     Tool select     G  Toggle grid     Tab  Swap colours
##   +/-     Zoom            [/]  Cycle palette
##   Space   Play/Pause preview
##   Ctrl+S  Save            Ctrl+L  Load
##   Ctrl+D  Duplicate frame  Delete  Remove frame
extends Control

const SAVE_PATH : String = "user://animations/"
const MAX_UNDO  : int    = 30
const INVALID_PX: Vector2i = Vector2i(-1, -1)

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

enum DrawTool { PENCIL, ERASER, FILL, EYEDROP }

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var anim_name      : String   = "new_anim"
var canvas_w       : int      = 16
var canvas_h       : int      = 16
var pixel_size     : int      = 16
var fps            : int      = 8
var loop_anim      : bool     = true
var show_grid      : bool     = true
var onion_skin     : bool     = false

var frames         : Array    = []   ## Array of PackedColorArray
var sel_frame      : int      = 0
var undo_stack     : Array    = []
var redo_stack     : Array    = []

var current_tool   : DrawTool = DrawTool.PENCIL
var primary_color  : Color    = Color.WHITE
var secondary_color: Color    = Color.BLACK
var palette_idx    : int      = 1
var is_drawing     : bool     = false

var canvas_image   : Image
var canvas_texture : ImageTexture
var preview_timer  : float    = 0.0
var preview_frame  : int      = 0
var playing        : bool     = false

# ---------------------------------------------------------------------------
# UI refs
# ---------------------------------------------------------------------------
var anim_name_input : LineEdit
var frame_list      : ItemList
var canvas_display  : TextureRect
var preview_display : TextureRect
var primary_swatch  : ColorRect
var secondary_swatch: ColorRect
var color_palette   : GridContainer
var fps_spin        : SpinBox
var loop_check      : CheckBox
var onion_check     : CheckBox
var status_bar      : Label

# ---------------------------------------------------------------------------
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	DirAccess.make_dir_recursive_absolute(SAVE_PATH)
	_build_ui()
	_add_blank_frame()
	_load_frame_into_canvas(0)

func _process(delta: float) -> void:
	if playing and frames.size() > 1:
		preview_timer += delta
		if preview_timer >= 1.0 / float(fps):
			preview_timer = 0.0
			preview_frame = (preview_frame + 1) % frames.size()
			_refresh_preview()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: _set_tool(DrawTool.PENCIL)
			KEY_2: _set_tool(DrawTool.ERASER)
			KEY_3: _set_tool(DrawTool.FILL)
			KEY_4: _set_tool(DrawTool.EYEDROP)
			KEY_G:
				show_grid = not show_grid; _set_status("Grid %s" % ("on" if show_grid else "off"))
			KEY_TAB:
				var tmp := primary_color; primary_color = secondary_color; secondary_color = tmp
				_update_swatches()
			KEY_EQUAL: pixel_size = min(pixel_size + 2, 32); _resize_canvas()
			KEY_MINUS: pixel_size = max(pixel_size - 2, 4);  _resize_canvas()
			KEY_BRACKETRIGHT:
				palette_idx   = (palette_idx + 1) % PALETTE.size()
				primary_color = PALETTE[palette_idx]; _update_swatches()
			KEY_BRACKETLEFT:
				palette_idx   = (palette_idx - 1 + PALETTE.size()) % PALETTE.size()
				primary_color = PALETTE[palette_idx]; _update_swatches()
			KEY_SPACE:
				playing = not playing; preview_frame = sel_frame
				_set_status("Preview %s" % ("playing" if playing else "paused"))
			KEY_DELETE:
				if not event.ctrl_pressed: _delete_frame()
			KEY_S:
				if event.ctrl_pressed: _save_anim()
			KEY_L:
				if event.ctrl_pressed: _load_anim()
			KEY_D:
				if event.ctrl_pressed: _dup_frame()
			KEY_Z:
				if event.ctrl_pressed and event.shift_pressed: _redo()
				elif event.ctrl_pressed: _undo()

# ---------------------------------------------------------------------------
# UI build
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Toolbar
	var tb := HBoxContainer.new(); root.add_child(tb)
	_btn("← Back", func(): SceneManager.go_to("main"), tb)
	tb.add_child(VSeparator.new())
	anim_name_input = LineEdit.new()
	anim_name_input.text = anim_name
	anim_name_input.placeholder_text = "animation_name"
	anim_name_input.custom_minimum_size = Vector2(130, 0)
	anim_name_input.text_changed.connect(func(t: String) -> void: anim_name = t)
	tb.add_child(anim_name_input)
	_btn("Save (Ctrl+S)", _save_anim, tb)
	_btn("Load (Ctrl+L)", _load_anim, tb)
	tb.add_child(VSeparator.new())
	for entry : Array in [["Pencil(1)", DrawTool.PENCIL], ["Eraser(2)", DrawTool.ERASER],
	                       ["Fill(3)",  DrawTool.FILL],   ["Pick(4)",   DrawTool.EYEDROP]]:
		var t := entry[1] as DrawTool
		_btn(str(entry[0]), func() -> void: _set_tool(t), tb)
	tb.add_child(VSeparator.new())
	_btn("▶/❚❚ Space", func() -> void: playing = not playing; preview_frame = sel_frame, tb)

	# Body
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	# Left — frame list + palette
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(150, 0)
	body.add_child(left)
	left.add_child(_lbl("Frames", true))
	frame_list = ItemList.new()
	frame_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame_list.item_selected.connect(_on_frame_selected)
	left.add_child(frame_list)
	var fr := HBoxContainer.new(); left.add_child(fr)
	_btn("+",    _add_blank_frame, fr)
	_btn("Dup",  _dup_frame,       fr)
	_btn("Del",  _delete_frame,    fr)
	_btn("↑",    func() -> void: _move_frame(-1), fr)
	_btn("↓",    func() -> void: _move_frame(1),  fr)

	left.add_child(HSeparator.new())
	left.add_child(_lbl("Swatches:"))
	var sw := HBoxContainer.new(); left.add_child(sw)
	primary_swatch   = ColorRect.new(); primary_swatch.custom_minimum_size   = Vector2(32, 32)
	secondary_swatch = ColorRect.new(); secondary_swatch.custom_minimum_size = Vector2(32, 32)
	primary_swatch.color = primary_color; secondary_swatch.color = secondary_color
	sw.add_child(primary_swatch); sw.add_child(secondary_swatch)

	left.add_child(_lbl("Palette:"))
	color_palette = GridContainer.new(); color_palette.columns = 4
	left.add_child(color_palette)
	_build_palette()

	body.add_child(VSeparator.new())

	# Center — canvas
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	center.add_child(_lbl("Canvas  (+/- zoom  G grid  Tab swap)", false))

	var canvas_scroll := ScrollContainer.new()
	canvas_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	center.add_child(canvas_scroll)

	var canvas_wrap := Control.new()   # wrapper lets us stack display + grid overlay
	canvas_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_wrap.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	canvas_scroll.add_child(canvas_wrap)

	canvas_display = TextureRect.new()
	canvas_display.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	canvas_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	canvas_display.custom_minimum_size = Vector2(canvas_w * pixel_size, canvas_h * pixel_size)
	canvas_wrap.add_child(canvas_display)

	# Intercept input on canvas display
	canvas_display.gui_input.connect(_on_canvas_input)
	canvas_display.mouse_filter = Control.MOUSE_FILTER_STOP

	body.add_child(VSeparator.new())

	# Right — preview + settings
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(150, 0)
	body.add_child(right)
	right.add_child(_lbl("Preview", true))
	preview_display = TextureRect.new()
	preview_display.custom_minimum_size = Vector2(canvas_w * 4, canvas_h * 4)
	preview_display.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	preview_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	right.add_child(preview_display)

	right.add_child(HSeparator.new())
	right.add_child(_lbl("Settings:", true))
	right.add_child(_lbl("FPS:"))
	fps_spin = SpinBox.new(); fps_spin.min_value = 1; fps_spin.max_value = 60; fps_spin.value = fps
	fps_spin.value_changed.connect(func(v: float) -> void: fps = int(v))
	right.add_child(fps_spin)

	loop_check = CheckBox.new(); loop_check.text = "Loop"
	loop_check.button_pressed = loop_anim
	loop_check.toggled.connect(func(v: bool) -> void: loop_anim = v)
	right.add_child(loop_check)

	onion_check = CheckBox.new(); onion_check.text = "Onion Skin"
	onion_check.button_pressed = onion_skin
	onion_check.toggled.connect(func(v: bool) -> void: onion_skin = v; _refresh_canvas())
	right.add_child(onion_check)

	right.add_child(HSeparator.new())
	right.add_child(_lbl("Canvas Size:"))
	var cs_row := HBoxContainer.new(); right.add_child(cs_row)
	var cw_spin := SpinBox.new(); cw_spin.min_value = 8; cw_spin.max_value = 64; cw_spin.value = canvas_w
	var ch_spin := SpinBox.new(); ch_spin.min_value = 8; ch_spin.max_value = 64; ch_spin.value = canvas_h
	cs_row.add_child(cw_spin); cs_row.add_child(_lbl("×")); cs_row.add_child(ch_spin)
	_btn("New Canvas", func() -> void:
		canvas_w = int(cw_spin.value); canvas_h = int(ch_spin.value)
		frames.clear(); _add_blank_frame(); _load_frame_into_canvas(0), right)

	# Status
	status_bar = Label.new()
	status_bar.text = "Animation Designer | 1-4 Tools  Space Play  Ctrl+S Save  G Grid"
	root.add_child(status_bar)

	_init_canvas()

# ---------------------------------------------------------------------------
# Canvas
# ---------------------------------------------------------------------------

func _init_canvas() -> void:
	canvas_image   = Image.create(canvas_w, canvas_h, false, Image.FORMAT_RGBA8)
	canvas_texture = ImageTexture.create_from_image(canvas_image)
	canvas_display.texture  = canvas_texture
	canvas_display.custom_minimum_size = Vector2(canvas_w * pixel_size, canvas_h * pixel_size)
	if preview_display: preview_display.texture = canvas_texture

func _resize_canvas() -> void:
	canvas_display.custom_minimum_size = Vector2(canvas_w * pixel_size, canvas_h * pixel_size)
	_refresh_canvas()

func _refresh_canvas() -> void:
	if frames.is_empty() or sel_frame >= frames.size(): return
	var pixels : PackedColorArray = frames[sel_frame]
	# Onion skin: blend previous frame at 30% alpha
	if onion_skin and sel_frame > 0:
		var prev_px : PackedColorArray = frames[sel_frame - 1]
		for y in canvas_h:
			for x in canvas_w:
				var idx := y * canvas_w + x
				var fg : Color = pixels[idx]
				var bg : Color = prev_px[idx]
				var blended := bg.lerp(fg, 0.7)
				canvas_image.set_pixel(x, y, blended if fg.a < 0.5 else fg)
	else:
		for y in canvas_h:
			for x in canvas_w:
				canvas_image.set_pixel(x, y, pixels[y * canvas_w + x])
	canvas_texture.update(canvas_image)

func _refresh_preview() -> void:
	if not preview_display or frames.is_empty(): return
	var pidx : int = preview_frame % frames.size()
	var px   : PackedColorArray = frames[pidx]
	var img  : Image = Image.create(canvas_w, canvas_h, false, Image.FORMAT_RGBA8)
	for y in canvas_h:
		for x in canvas_w:
			img.set_pixel(x, y, px[y * canvas_w + x])
	preview_display.texture = ImageTexture.create_from_image(img)

# ---------------------------------------------------------------------------
# Canvas input
# ---------------------------------------------------------------------------

func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var px := _local_to_pixel(event.position)
		if event.pressed:
			if px == INVALID_PX: return
			is_drawing = true
			if current_tool != DrawTool.EYEDROP: _push_undo()
			var col := primary_color if event.button_index == MOUSE_BUTTON_LEFT else secondary_color
			_apply_tool(px, col)
		else:
			is_drawing = false

	if event is InputEventMouseMotion and is_drawing:
		var px := _local_to_pixel(event.position)
		if px == INVALID_PX: return
		var col := primary_color if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else secondary_color
		if current_tool in [DrawTool.PENCIL, DrawTool.ERASER]: _apply_tool(px, col)

func _local_to_pixel(local: Vector2) -> Vector2i:
	var px := int(local.x) / pixel_size
	var py := int(local.y) / pixel_size
	if px < 0 or px >= canvas_w or py < 0 or py >= canvas_h: return INVALID_PX
	return Vector2i(px, py)

func _apply_tool(px: Vector2i, col: Color) -> void:
	if frames.is_empty(): return
	var pixels : PackedColorArray = frames[sel_frame]
	match current_tool:
		DrawTool.PENCIL: pixels[px.y * canvas_w + px.x] = col
		DrawTool.ERASER: pixels[px.y * canvas_w + px.x] = Color(0, 0, 0, 0)
		DrawTool.FILL:   _flood_fill(pixels, px, col)
		DrawTool.EYEDROP:
			primary_color = pixels[px.y * canvas_w + px.x]
			_update_swatches(); return
	frames[sel_frame] = pixels
	_refresh_canvas()

func _flood_fill(pixels: PackedColorArray, start: Vector2i, new_col: Color) -> void:
	var target : Color = pixels[start.y * canvas_w + start.x]
	if target == new_col: return
	var queue  : Array[Vector2i] = [start]
	var visited: Dictionary      = {}
	var dirs   : Array[Vector2i] = [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]
	while queue.size() > 0:
		var p   : Vector2i = queue.pop_front()
		var key : String   = "%d,%d" % [p.x, p.y]
		if visited.has(key): continue
		visited[key] = true
		var idx := p.y * canvas_w + p.x
		if pixels[idx] != target: continue
		pixels[idx] = new_col
		for d : Vector2i in dirs:
			var np : Vector2i = p + d
			if np.x >= 0 and np.x < canvas_w and np.y >= 0 and np.y < canvas_h:
				queue.append(np)

# ---------------------------------------------------------------------------
# Frame management
# ---------------------------------------------------------------------------

func _blank_frame() -> PackedColorArray:
	var px := PackedColorArray(); px.resize(canvas_w * canvas_h)
	px.fill(Color(0, 0, 0, 0)); return px

func _add_blank_frame() -> void:
	frames.append(_blank_frame())
	sel_frame = frames.size() - 1
	_rebuild_frame_list()
	_load_frame_into_canvas(sel_frame)

func _dup_frame() -> void:
	if frames.is_empty(): return
	frames.insert(sel_frame + 1, frames[sel_frame].duplicate())
	sel_frame += 1; _rebuild_frame_list(); _load_frame_into_canvas(sel_frame)

func _delete_frame() -> void:
	if frames.size() <= 1: _set_status("Cannot delete the only frame"); return
	frames.remove_at(sel_frame)
	sel_frame = min(sel_frame, frames.size() - 1)
	_rebuild_frame_list(); _load_frame_into_canvas(sel_frame)

func _move_frame(dir: int) -> void:
	var new_idx := sel_frame + dir
	if new_idx < 0 or new_idx >= frames.size(): return
	var tmp := frames[sel_frame]; frames[sel_frame] = frames[new_idx]; frames[new_idx] = tmp
	sel_frame = new_idx; _rebuild_frame_list(); frame_list.select(sel_frame)

func _on_frame_selected(idx: int) -> void:
	sel_frame = idx; _load_frame_into_canvas(idx)
	_set_status("Frame %d / %d" % [idx + 1, frames.size()])

func _rebuild_frame_list() -> void:
	frame_list.clear()
	for i in frames.size(): frame_list.add_item("Frame %d" % (i + 1))
	if sel_frame < frames.size(): frame_list.select(sel_frame)

func _load_frame_into_canvas(idx: int) -> void:
	if idx < 0 or idx >= frames.size(): return
	sel_frame = idx; _refresh_canvas()

# ---------------------------------------------------------------------------
# Undo / Redo
# ---------------------------------------------------------------------------

func _push_undo() -> void:
	var snap : Array = []
	for f in frames: snap.append(f.duplicate())
	undo_stack.append({"frames": snap, "sel": sel_frame})
	if undo_stack.size() > MAX_UNDO: undo_stack.pop_front()
	redo_stack.clear()

func _undo() -> void:
	if undo_stack.is_empty(): return
	var cur : Array = []
	for f in frames: cur.append(f.duplicate())
	redo_stack.append({"frames": cur, "sel": sel_frame})
	var snap : Dictionary = undo_stack.pop_back()
	frames = snap["frames"]; sel_frame = snap["sel"]
	_rebuild_frame_list(); _load_frame_into_canvas(sel_frame)
	_set_status("Undo")

func _redo() -> void:
	if redo_stack.is_empty(): return
	var cur : Array = []
	for f in frames: cur.append(f.duplicate())
	undo_stack.append({"frames": cur, "sel": sel_frame})
	var snap : Dictionary = redo_stack.pop_back()
	frames = snap["frames"]; sel_frame = snap["sel"]
	_rebuild_frame_list(); _load_frame_into_canvas(sel_frame)
	_set_status("Redo")

# ---------------------------------------------------------------------------
# Save / Load (spritesheet PNG + JSON metadata)
# ---------------------------------------------------------------------------

func _save_anim() -> void:
	anim_name = anim_name_input.text.strip_edges()
	if anim_name.is_empty(): anim_name = "anim"
	# Build horizontal spritesheet
	var sheet_w := canvas_w * frames.size()
	var sheet   := Image.create(sheet_w, canvas_h, false, Image.FORMAT_RGBA8)
	for f_idx in frames.size():
		for y in canvas_h:
			for x in canvas_w:
				sheet.set_pixel(f_idx * canvas_w + x, y, frames[f_idx][y * canvas_w + x])
	var png_path := SAVE_PATH + anim_name + ".png"
	var err := sheet.save_png(png_path)
	if err != OK: _set_status("PNG save failed (err %d)" % err); return
	# Metadata JSON
	var meta : Dictionary = {
		"name": anim_name, "frame_count": frames.size(),
		"frame_w": canvas_w, "frame_h": canvas_h,
		"fps": fps, "loop": loop_anim,
		"spritesheet": anim_name + ".png",
	}
	var json_path := SAVE_PATH + anim_name + ".json"
	var jf := FileAccess.open(json_path, FileAccess.WRITE)
	if jf: jf.store_string(JSON.stringify(meta, "\t")); jf.close()
	_set_status("Saved: %s  (%d frames, %dx%d)" % [png_path, frames.size(), canvas_w, canvas_h])

func _load_anim() -> void:
	anim_name = anim_name_input.text.strip_edges()
	if anim_name.is_empty(): anim_name = "anim"
	var json_path := SAVE_PATH + anim_name + ".json"
	if not FileAccess.file_exists(json_path): _set_status("No metadata for: " + anim_name); return
	var jf := FileAccess.open(json_path, FileAccess.READ)
	var meta := JSON.parse_string(jf.get_as_text()); jf.close()
	if not meta is Dictionary: _set_status("Bad metadata"); return
	var m : Dictionary = meta
	canvas_w = int(m.get("frame_w", 16)); canvas_h = int(m.get("frame_h", 16))
	fps = int(m.get("fps", 8)); loop_anim = bool(m.get("loop", true))
	fps_spin.value = fps; loop_check.button_pressed = loop_anim
	var sheet_path := SAVE_PATH + str(m.get("spritesheet", anim_name + ".png"))
	if not FileAccess.file_exists(sheet_path): _set_status("Spritesheet not found: " + sheet_path); return
	var sheet := Image.load_from_file(sheet_path)
	if not sheet: _set_status("Failed to load spritesheet"); return
	var frame_count := int(m.get("frame_count", 1))
	frames.clear()
	for i in frame_count:
		var px := PackedColorArray(); px.resize(canvas_w * canvas_h)
		for y in canvas_h:
			for x in canvas_w:
				px[y * canvas_w + x] = sheet.get_pixel(i * canvas_w + x, y)
		frames.append(px)
	_init_canvas()
	sel_frame = 0; _rebuild_frame_list(); _load_frame_into_canvas(0)
	_set_status("Loaded: %s  (%d frames)" % [anim_name, frames.size()])

# ---------------------------------------------------------------------------
# Palette UI
# ---------------------------------------------------------------------------

func _build_palette() -> void:
	for c : Color in PALETTE:
		var sw := ColorRect.new()
		sw.color = c; sw.custom_minimum_size = Vector2(16, 16)
		sw.gui_input.connect(_on_palette_input.bind(c))
		color_palette.add_child(sw)

func _on_palette_input(event: InputEvent, col: Color) -> void:
	if not (event is InputEventMouseButton and event.pressed): return
	if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		primary_color = col
	else:
		secondary_color = col
	_update_swatches()

func _update_swatches() -> void:
	if primary_swatch:   primary_swatch.color   = primary_color
	if secondary_swatch: secondary_swatch.color = secondary_color

# ---------------------------------------------------------------------------
# Tool helpers
# ---------------------------------------------------------------------------

func _set_tool(t: DrawTool) -> void:
	current_tool = t
	_set_status("Tool: " + DrawTool.keys()[t])

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _lbl(text: String, bold: bool = false) -> Label:
	var l := Label.new(); l.text = text
	if bold: l.add_theme_font_size_override("font_size", 14)
	return l

func _btn(text: String, cb: Callable, parent: Node) -> Button:
	var b := Button.new(); b.text = text; b.pressed.connect(cb)
	parent.add_child(b); return b

func _set_status(msg: String) -> void:
	if status_bar: status_bar.text = msg
