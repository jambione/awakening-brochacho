## DungeonRoomDesigner — editor for hand-crafted dungeon room templates.
##
## Paints a fixed-size grid of tile types, sets doors, enemy spawns, and
## chest positions.  Saves to user://rooms/rooms.json.
##
## Tile types:
##   0 Empty  1 Floor  2 Wall  3 Door  4 Enemy Spawn  5 Chest  6 Stairs Down  7 Stairs Up
##
## Ctrl+S Save  Ctrl+L Load  Ctrl+E Export to res://data/rooms/
## Left-click paint  Right-click erase  Scroll zoom
extends Control

const SAVE_PATH  : String = "user://rooms/"
const RES_PATH   : String = "res://data/rooms/"
const FILE_NAME  : String = "rooms.json"
const ROOM_W     : int    = 16
const ROOM_H     : int    = 16
const CELL_SIZE  : int    = 24   ## px per tile in the grid editor
const ROOM_TYPES : Array[String] = ["normal","boss","secret","puzzle","treasure","start"]

const TILE_COLORS : Array[Color] = [
	Color(0.05, 0.05, 0.05),   # 0 Empty
	Color(0.55, 0.50, 0.40),   # 1 Floor
	Color(0.25, 0.22, 0.18),   # 2 Wall
	Color(0.30, 0.55, 1.00),   # 3 Door
	Color(1.00, 0.20, 0.20),   # 4 Enemy Spawn
	Color(1.00, 0.85, 0.10),   # 5 Chest
	Color(0.20, 0.80, 0.40),   # 6 Stairs Down
	Color(0.80, 0.40, 1.00),   # 7 Stairs Up
]
const TILE_NAMES : Array[String] = [
	"Empty","Floor","Wall","Door","Enemy Spawn","Chest","Stairs ↓","Stairs ↑"
]

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var rooms        : Array    = []
var sel_idx      : int      = -1
var grid         : Array    = []   ## Flat Array[int] size ROOM_W * ROOM_H
var current_tile : int      = 1   ## Palette selection
var is_painting  : bool     = false
var zoom         : float    = 1.0

# ---------------------------------------------------------------------------
# UI refs
# ---------------------------------------------------------------------------
var room_list    : ItemList
var status_bar   : Label
var grid_node    : Node2D
var f_name       : LineEdit
var f_type       : OptionButton
var f_desc       : LineEdit
var palette_btns : Array[Button] = []

# ---------------------------------------------------------------------------
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	DirAccess.make_dir_recursive_absolute(SAVE_PATH)
	_init_grid()
	_build_ui()
	_load_data()

func _init_grid() -> void:
	grid.resize(ROOM_W * ROOM_H)
	grid.fill(0)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.ctrl_pressed:
		match event.keycode:
			KEY_S: _save_data()
			KEY_L: _load_data()
			KEY_E: _export_to_res()

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Toolbar
	var tb := HBoxContainer.new(); root.add_child(tb)
	_btn("← Back",        func(): SceneManager.go_to("main"), tb)
	tb.add_child(VSeparator.new())
	_btn("Save (Ctrl+S)", _save_data,     tb)
	_btn("Load (Ctrl+L)", _load_data,     tb)
	_btn("Export→res://", _export_to_res, tb)
	tb.add_child(VSeparator.new())
	_btn("Fill Floor",    _fill_floor,    tb)
	_btn("Clear Room",    _clear_room,    tb)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	# Left — room list
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(180, 0)
	body.add_child(left)
	left.add_child(_lbl("Rooms", true))
	room_list = ItemList.new()
	room_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room_list.item_selected.connect(_on_room_selected)
	left.add_child(room_list)
	var lr := HBoxContainer.new(); left.add_child(lr)
	_btn("+ New",     _add_room,    lr)
	_btn("Delete",    _delete_room, lr)
	_btn("Duplicate", _dup_room,    lr)

	left.add_child(HSeparator.new())
	left.add_child(_lbl("Tile Palette:", true))
	var pal_scroll := ScrollContainer.new()
	pal_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(pal_scroll)
	var pal_vbox := VBoxContainer.new(); pal_scroll.add_child(pal_vbox)
	for i in TILE_NAMES.size():
		var btn := Button.new()
		btn.text = TILE_NAMES[i]
		btn.toggle_mode = true
		btn.button_pressed = (i == 1)   # Floor selected by default
		var idx := i
		btn.pressed.connect(func() -> void: _select_tile(idx))
		pal_vbox.add_child(btn)
		palette_btns.append(btn)

	body.add_child(VSeparator.new())

	# Center — grid editor
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	center.add_child(_lbl("Room Grid  (Left-click paint  Right-click erase  Scroll zoom)", false))

	var grid_scroll := ScrollContainer.new()
	grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	center.add_child(grid_scroll)

	# Dynamic draw node for the grid
	var scr := GDScript.new()
	scr.source_code = "extends Node2D\nvar host: Node\nfunc _draw() -> void:\n\tif host: host._draw_grid(self)"
	if scr.reload() == OK:
		grid_node = Node2D.new()
		grid_node.set_script(scr)
		grid_scroll.add_child(grid_node)
		grid_node.set("host", self)
		grid_node.custom_minimum_size = Vector2(ROOM_W * CELL_SIZE * zoom, ROOM_H * CELL_SIZE * zoom)
		grid_node.gui_input.connect(_on_grid_input)
		grid_node.mouse_filter = Control.MOUSE_FILTER_STOP if grid_node is Control else 0

	body.add_child(VSeparator.new())

	# Right — room properties
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(180, 0)
	body.add_child(right)
	right.add_child(_lbl("Room Properties", true))
	f_name = _field(right, "Name:",        "e.g. Golem Chamber")
	right.add_child(_lbl("Type:"))
	f_type = OptionButton.new()
	for t : String in ROOM_TYPES: f_type.add_item(t)
	right.add_child(f_type)
	f_desc = _field(right, "Description:", "Short designer note")
	right.add_child(HSeparator.new())
	_btn("✔ Apply Properties", _apply_props, right)

	# Status
	status_bar = Label.new()
	status_bar.text = "Dungeon Room Designer | Ctrl+S Save  Ctrl+L Load"
	root.add_child(status_bar)

# ---------------------------------------------------------------------------
# Grid drawing (called from the dynamic Node2D script)
# ---------------------------------------------------------------------------

func _draw_grid(ci: Node2D) -> void:
	var cs : float = CELL_SIZE * zoom
	for y in ROOM_H:
		for x in ROOM_W:
			var tile : int = grid[y * ROOM_W + x]
			var rect := Rect2(x * cs, y * cs, cs, cs)
			ci.draw_rect(rect, TILE_COLORS[tile], true)
			ci.draw_rect(rect, Color(0, 0, 0, 0.35), false, 0.5)
	# Border
	ci.draw_rect(Rect2(0, 0, ROOM_W * cs, ROOM_H * cs), Color(0.8, 0.8, 0.8), false, 1.5)

# ---------------------------------------------------------------------------
# Grid input
# ---------------------------------------------------------------------------

func _on_grid_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = minf(zoom + 0.25, 3.0); _refresh_grid(); return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = maxf(zoom - 0.25, 0.5); _refresh_grid(); return
		is_painting = event.pressed
		if event.pressed:
			_paint_at(event.position, event.button_index == MOUSE_BUTTON_RIGHT)
	if event is InputEventMouseMotion and is_painting:
		var btn := MOUSE_BUTTON_RIGHT if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) else MOUSE_BUTTON_LEFT
		_paint_at(event.position, btn == MOUSE_BUTTON_RIGHT)

func _paint_at(pos: Vector2, erase: bool) -> void:
	var cs   : float = CELL_SIZE * zoom
	var gx   : int   = int(pos.x / cs)
	var gy   : int   = int(pos.y / cs)
	if gx < 0 or gx >= ROOM_W or gy < 0 or gy >= ROOM_H: return
	grid[gy * ROOM_W + gx] = 0 if erase else current_tile
	_refresh_grid()
	_set_status("Painted (%d,%d) → %s" % [gx, gy, TILE_NAMES[current_tile]])

func _refresh_grid() -> void:
	if grid_node:
		grid_node.custom_minimum_size = Vector2(ROOM_W * CELL_SIZE * zoom, ROOM_H * CELL_SIZE * zoom)
		grid_node.queue_redraw()

# ---------------------------------------------------------------------------
# Tile palette
# ---------------------------------------------------------------------------

func _select_tile(idx: int) -> void:
	current_tile = idx
	for i in palette_btns.size():
		palette_btns[i].button_pressed = (i == idx)
	_set_status("Tile: " + TILE_NAMES[idx])

# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

func _fill_floor() -> void:
	for i in grid.size(): if grid[i] == 0: grid[i] = 1
	_refresh_grid()

func _clear_room() -> void:
	grid.fill(0); _refresh_grid()

# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------

func _load_data() -> void:
	var user_path := SAVE_PATH + FILE_NAME
	var res_path  := RES_PATH  + FILE_NAME
	var path := user_path if FileAccess.file_exists(user_path) else res_path
	if not FileAccess.file_exists(path):
		rooms = []; _rebuild_list(); _set_status("No rooms.json — starting blank"); return
	var f := FileAccess.open(path, FileAccess.READ)
	var p := JSON.parse_string(f.get_as_text()); f.close()
	rooms = p if p is Array else []
	_rebuild_list()
	_set_status("Loaded %d rooms" % rooms.size())

func _save_data() -> void:
	# Store current grid into selected room before saving
	if sel_idx >= 0 and sel_idx < rooms.size():
		rooms[sel_idx]["tiles"] = grid.duplicate()
	var path := SAVE_PATH + FILE_NAME
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f: _set_status("ERROR writing " + path); return
	f.store_string(JSON.stringify(rooms, "\t")); f.close()
	_set_status("Saved: " + path)

func _export_to_res() -> void:
	_save_data()
	DirAccess.make_dir_recursive_absolute(RES_PATH)
	var src := SAVE_PATH + FILE_NAME
	if not FileAccess.file_exists(src): _set_status("Save first"); return
	var txt := FileAccess.open(src, FileAccess.READ).get_as_text()
	var out  := FileAccess.open(RES_PATH + FILE_NAME, FileAccess.WRITE)
	if not out: _set_status("Export failed"); return
	out.store_string(txt); out.close()
	_set_status("Exported → " + RES_PATH + FILE_NAME)

# ---------------------------------------------------------------------------
# Room list
# ---------------------------------------------------------------------------

func _rebuild_list() -> void:
	room_list.clear()
	for r in rooms:
		room_list.add_item("[%s] %s" % [r.get("type","?"), r.get("name","?")])
	if sel_idx >= 0 and sel_idx < rooms.size():
		room_list.select(sel_idx); _load_room(sel_idx)

func _on_room_selected(idx: int) -> void:
	# Save current grid back before switching
	if sel_idx >= 0 and sel_idx < rooms.size():
		rooms[sel_idx]["tiles"] = grid.duplicate()
	sel_idx = idx; _load_room(idx)
	_set_status("Editing: " + str(rooms[idx].get("name","?")))

func _add_room() -> void:
	var blank_grid : Array = []
	blank_grid.resize(ROOM_W * ROOM_H); blank_grid.fill(0)
	rooms.append({"name":"New Room","type":"normal","description":"","tiles": blank_grid})
	sel_idx = rooms.size() - 1; _rebuild_list()

func _delete_room() -> void:
	if sel_idx < 0 or sel_idx >= rooms.size(): return
	rooms.remove_at(sel_idx); sel_idx = min(sel_idx, rooms.size() - 1)
	_init_grid(); _refresh_grid(); _rebuild_list()

func _dup_room() -> void:
	if sel_idx < 0 or sel_idx >= rooms.size(): return
	var copy : Dictionary = rooms[sel_idx].duplicate(true)
	copy["name"] = copy.get("name","Room") + " Copy"
	rooms.append(copy); sel_idx = rooms.size() - 1; _rebuild_list()

func _load_room(idx: int) -> void:
	if idx < 0 or idx >= rooms.size(): return
	var r : Dictionary = rooms[idx]
	f_name.text = str(r.get("name",""))
	f_type.selected = max(0, ROOM_TYPES.find(str(r.get("type","normal"))))
	f_desc.text = str(r.get("description",""))
	var tiles : Array = r.get("tiles", [])
	_init_grid()
	for i in min(tiles.size(), grid.size()):
		grid[i] = int(tiles[i])
	_refresh_grid()

func _apply_props() -> void:
	if sel_idx < 0: _set_status("Select a room first"); return
	rooms[sel_idx]["name"]        = f_name.text
	rooms[sel_idx]["type"]        = f_type.get_item_text(f_type.selected)
	rooms[sel_idx]["description"] = f_desc.text
	rooms[sel_idx]["tiles"]       = grid.duplicate()
	_rebuild_list()
	_set_status("Applied: " + f_name.text)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _field(parent: Node, label: String, ph: String) -> LineEdit:
	parent.add_child(_lbl(label))
	var e := LineEdit.new(); e.placeholder_text = ph; parent.add_child(e); return e

func _lbl(text: String, bold: bool = false) -> Label:
	var l := Label.new(); l.text = text
	if bold: l.add_theme_font_size_override("font_size", 14)
	return l

func _btn(text: String, cb: Callable, parent: Node) -> Button:
	var b := Button.new(); b.text = text; b.pressed.connect(cb)
	parent.add_child(b); return b

func _set_status(msg: String) -> void:
	if status_bar: status_bar.text = msg
