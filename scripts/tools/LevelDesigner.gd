## LevelDesigner — in-game tile-painting tool with save/load.
##
## Keyboard shortcuts:
##   F1  Paint    F2  Erase    F3  Fill    F4  Select   F5  Object
##   Ctrl+S  Save map      Ctrl+N  New map
##   Ctrl+L  Load latest   Ctrl+Shift+L  Cycle saved maps
##   Ctrl+Z  Undo          Ctrl+Shift+Z  Redo
##   Ctrl+A  Select all    Ctrl+C  Copy   Ctrl+V  Paste
##   Delete  Delete selection   Escape  Deselect
##   G       Toggle grid overlay
##   +/-     Zoom in/out   Scroll wheel  Zoom
##   Right-click drag  Erase
extends Control

# ---------------------------------------------------------------------------
# Node references — paths must match LevelDesigner.tscn
# ---------------------------------------------------------------------------
@onready var tile_map      : TileMapLayer        = $UI/Center/Viewport/SubViewport/TileMap
@onready var sub_viewport  : SubViewport         = $UI/Center/Viewport/SubViewport
@onready var vp_container  : SubViewportContainer = $UI/Center/Viewport
@onready var tile_palette  : GridContainer       = $UI/Left/Palette
@onready var toolbar       : HBoxContainer       = $UI/Center/Top/Toolbar
@onready var status_bar    : Label               = $UI/Center/Bottom/StatusBar
@onready var object_palette: ItemList            = $UI/Left/ObjectPalette
@onready var props_panel   : VBoxContainer       = $UI/Right/Properties
@onready var map_name_input: LineEdit            = $UI/Center/Top/MapNameInput

# ---------------------------------------------------------------------------
# Tool enum
# ---------------------------------------------------------------------------
enum Tool { PAINT, ERASE, FILL, SELECT, OBJECT }

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const SAVE_PATH : String = "user://maps/"
const MAX_UNDO  : int    = 50
const TILE_SIZE : int    = 16

const INVALID_POS : Vector2  = Vector2(-1.0, -1.0)
const INVALID_CELL: Vector2i = Vector2i(-9999, -9999)

const OBJECT_TYPES : Array[String] = [
	"Player Start", "Enemy Spawn", "Item Pickup",
	"Chest", "Door", "Trigger Zone", "Warp Point",
]

const OBJECT_COLORS : Dictionary = {
	"Player Start": Color(0.0,  1.0,  0.2,  0.9),
	"Enemy Spawn":  Color(1.0,  0.15, 0.15, 0.9),
	"Item Pickup":  Color(1.0,  1.0,  0.0,  0.9),
	"Chest":        Color(0.85, 0.55, 0.05, 0.9),
	"Door":         Color(0.5,  0.3,  0.1,  0.9),
	"Trigger Zone": Color(0.5,  0.0,  1.0,  0.6),
	"Warp Point":   Color(0.0,  0.8,  1.0,  0.9),
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var current_tool    : Tool      = Tool.PAINT
var selected_atlas  : Vector2i  = Vector2i(0, 0)
var is_painting     : bool      = false
var is_erasing      : bool      = false
var map_name        : String    = "new_map"
var zoom_level      : float     = 2.0
var undo_stack      : Array[Dictionary] = []
var redo_stack      : Array[Dictionary] = []
var last_world_pos  : Vector2   = Vector2.ZERO

# Selection
var sel_start       : Vector2i  = INVALID_CELL
var sel_end         : Vector2i  = INVALID_CELL
var sel_active      : bool      = false
var clipboard       : Dictionary = {}   ## Vector2i offset → Vector2i atlas.
var clipboard_objs  : Dictionary = {}   ## Vector2i offset → String type.

# Objects placed on the map
var placed_objects  : Dictionary = {}   ## Vector2i cell → String type.

# Hover / grid overlay
var hover_cell      : Vector2i  = INVALID_CELL
var show_grid       : bool      = true
var overlay_node    : Node2D    = null  ## Dynamic draw node inside SubViewport.

# Map cycling
var map_file_list   : Array[String] = []
var map_file_idx    : int           = -1

# UI refs built at runtime
var tool_buttons    : Array[Button] = []
var palette_buttons : Array[Button] = []
var props_label     : Label         = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_PATH)
	sub_viewport.size = Vector2i(320, 240)
	_build_palette()
	_build_toolbar()
	_build_props_panel()
	_build_object_palette()
	_build_overlay()
	_set_status("LevelDesigner | F1-F5 Tools | G Grid | +/- Zoom | Ctrl+S Save | Ctrl+Z Undo")

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# ── Keyboard ─────────────────────────────────────────────────────────────
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1: _set_tool(Tool.PAINT)
			KEY_F2: _set_tool(Tool.ERASE)
			KEY_F3: _set_tool(Tool.FILL)
			KEY_F4: _set_tool(Tool.SELECT)
			KEY_F5: _set_tool(Tool.OBJECT)
			KEY_G:
				show_grid = not show_grid
				_redraw_overlay()
				_set_status("Grid %s" % ("on" if show_grid else "off"))
			KEY_EQUAL:   # + zoom in
				zoom_level = clampf(zoom_level + 0.25, 0.5, 8.0)
				_apply_zoom()
			KEY_MINUS:   # - zoom out
				zoom_level = clampf(zoom_level - 0.25, 0.5, 8.0)
				_apply_zoom()
			KEY_ESCAPE:
				_deselect()
			KEY_DELETE:
				if sel_active:
					_delete_selection()
			KEY_N:
				if event.ctrl_pressed: _new_map()
			KEY_S:
				if event.ctrl_pressed: _save_map()
			KEY_L:
				if event.ctrl_pressed and event.shift_pressed: _cycle_map(1)
				elif event.ctrl_pressed: _load_latest_map()
			KEY_A:
				if event.ctrl_pressed: _select_all()
			KEY_C:
				if event.ctrl_pressed: _copy_selection()
			KEY_V:
				if event.ctrl_pressed: _paste_selection()
			KEY_Z:
				if event.ctrl_pressed and event.shift_pressed: _redo()
				elif event.ctrl_pressed: _undo()

	# ── Mouse buttons ─────────────────────────────────────────────────────────
	if event is InputEventMouseButton:
		var world : Vector2 = _viewport_mouse_pos(event.position)
		if world == INVALID_POS:
			is_painting = false
			if not event.pressed:
				is_erasing = false
			return

		var cell : Vector2i = tile_map.local_to_map(world)

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_painting = true
				last_world_pos = world
				if current_tool == Tool.SELECT:
					sel_start  = cell
					sel_end    = cell
					sel_active = true
					_redraw_overlay()
				else:
					_push_undo()
					_apply_tool(world)
			else:
				is_painting = false

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if not is_erasing:
					_push_undo()
					is_erasing = true
				tile_map.erase_cell(cell)
				placed_objects.erase(cell)
				_redraw_overlay()
			else:
				is_erasing = false

		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_level = clampf(zoom_level + 0.25, 0.5, 8.0)
			_apply_zoom()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_level = clampf(zoom_level - 0.25, 0.5, 8.0)
			_apply_zoom()

	# ── Mouse motion ──────────────────────────────────────────────────────────
	if event is InputEventMouseMotion:
		var world : Vector2 = _viewport_mouse_pos(event.position)
		if world != INVALID_POS:
			last_world_pos = world
			var cell : Vector2i = tile_map.local_to_map(world)
			hover_cell = cell
			_update_props(cell)
			_set_status("Cell (%d,%d) | %s | Zoom %.1fx | G Grid" % [
				cell.x, cell.y, Tool.keys()[current_tool], zoom_level
			])
			_redraw_overlay()

			if is_painting:
				if current_tool == Tool.SELECT:
					sel_end = cell
				else:
					_apply_tool(world)

			if is_erasing:
				tile_map.erase_cell(cell)
				placed_objects.erase(cell)

# ---------------------------------------------------------------------------
# Tool dispatch
# ---------------------------------------------------------------------------

func _apply_tool(world_pos: Vector2) -> void:
	var cell : Vector2i = tile_map.local_to_map(world_pos)
	match current_tool:
		Tool.PAINT:
			tile_map.set_cell(cell, 0, selected_atlas)
		Tool.ERASE:
			tile_map.erase_cell(cell)
			placed_objects.erase(cell)
		Tool.FILL:
			_flood_fill(cell, selected_atlas)
		Tool.SELECT:
			sel_end = cell
		Tool.OBJECT:
			var sel : PackedInt32Array = object_palette.get_selected_items()
			if sel.is_empty():
				_set_status("Select an object type in the Object palette first")
				return
			var obj_type : String = OBJECT_TYPES[sel[0]]
			placed_objects[cell] = obj_type
			_redraw_overlay()
			_set_status("Placed: %s at (%d,%d)" % [obj_type, cell.x, cell.y])

# ---------------------------------------------------------------------------
# Flood fill (BFS)
# ---------------------------------------------------------------------------

func _flood_fill(start: Vector2i, new_atlas: Vector2i) -> void:
	var source : Vector2i = tile_map.get_cell_atlas_coords(start)
	if source == new_atlas:
		return
	var queue   : Array[Vector2i] = [start]
	var visited : Dictionary      = {}
	var dirs    : Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	while queue.size() > 0:
		var cell : Vector2i = queue.pop_front()
		var key  : String   = "%d,%d" % [cell.x, cell.y]
		if visited.has(key):
			continue
		visited[key] = true
		if tile_map.get_cell_atlas_coords(cell) != source:
			continue
		tile_map.set_cell(cell, 0, new_atlas)
		for d : Vector2i in dirs:
			queue.append(cell + d)

# ---------------------------------------------------------------------------
# Selection helpers
# ---------------------------------------------------------------------------

func _deselect() -> void:
	sel_active = false
	sel_start  = INVALID_CELL
	sel_end    = INVALID_CELL
	_redraw_overlay()
	_set_status("Selection cleared")

func _select_all() -> void:
	var cells : Array[Vector2i] = tile_map.get_used_cells()
	if cells.is_empty():
		_set_status("Map is empty — nothing to select")
		return
	var min_x : int = cells[0].x
	var max_x : int = cells[0].x
	var min_y : int = cells[0].y
	var max_y : int = cells[0].y
	for c : Vector2i in cells:
		min_x = min(min_x, c.x); max_x = max(max_x, c.x)
		min_y = min(min_y, c.y); max_y = max(max_y, c.y)
	sel_start  = Vector2i(min_x, min_y)
	sel_end    = Vector2i(max_x, max_y)
	sel_active = true
	_redraw_overlay()
	_set_status("Selected all (%d tiles)" % cells.size())

func _copy_selection() -> void:
	if not sel_active or sel_start == INVALID_CELL:
		_set_status("Nothing selected to copy")
		return
	clipboard.clear()
	clipboard_objs.clear()
	var x0 : int = min(sel_start.x, sel_end.x)
	var y0 : int = min(sel_start.y, sel_end.y)
	var x1 : int = max(sel_start.x, sel_end.x)
	var y1 : int = max(sel_start.y, sel_end.y)
	var count : int = 0
	for y : int in range(y0, y1 + 1):
		for x : int in range(x0, x1 + 1):
			var ac : Vector2i = tile_map.get_cell_atlas_coords(Vector2i(x, y))
			if ac != Vector2i(-1, -1):
				clipboard[Vector2i(x - x0, y - y0)] = ac
				count += 1
			if placed_objects.has(Vector2i(x, y)):
				clipboard_objs[Vector2i(x - x0, y - y0)] = placed_objects[Vector2i(x, y)]
	_set_status("Copied %d tiles" % count)

func _paste_selection() -> void:
	if clipboard.is_empty() and clipboard_objs.is_empty():
		_set_status("Clipboard is empty")
		return
	_push_undo()
	var anchor : Vector2i = tile_map.local_to_map(last_world_pos)
	for offset : Vector2i in clipboard:
		tile_map.set_cell(anchor + offset, 0, clipboard[offset])
	for offset : Vector2i in clipboard_objs:
		placed_objects[anchor + offset] = clipboard_objs[offset]
	_redraw_overlay()
	_set_status("Pasted %d tiles at (%d,%d)" % [clipboard.size(), anchor.x, anchor.y])

func _delete_selection() -> void:
	if not sel_active or sel_start == INVALID_CELL:
		return
	_push_undo()
	var x0 : int = min(sel_start.x, sel_end.x)
	var y0 : int = min(sel_start.y, sel_end.y)
	var x1 : int = max(sel_start.x, sel_end.x)
	var y1 : int = max(sel_start.y, sel_end.y)
	for y : int in range(y0, y1 + 1):
		for x : int in range(x0, x1 + 1):
			tile_map.erase_cell(Vector2i(x, y))
			placed_objects.erase(Vector2i(x, y))
	_deselect()
	_set_status("Deleted selection")

# ---------------------------------------------------------------------------
# Undo / Redo
# ---------------------------------------------------------------------------

func _push_undo() -> void:
	undo_stack.append(_snapshot())
	if undo_stack.size() > MAX_UNDO:
		undo_stack.pop_front()
	redo_stack.clear()

func _undo() -> void:
	if undo_stack.is_empty():
		return
	redo_stack.append(_snapshot())
	_restore(undo_stack.pop_back())
	_set_status("Undo  (%d left)" % undo_stack.size())

func _redo() -> void:
	if redo_stack.is_empty():
		return
	undo_stack.append(_snapshot())
	_restore(redo_stack.pop_back())
	_set_status("Redo  (%d left)" % redo_stack.size())

func _snapshot() -> Dictionary:
	var cells : Dictionary = {}
	for cell : Vector2i in tile_map.get_used_cells():
		var ac : Vector2i = tile_map.get_cell_atlas_coords(cell)
		cells["%d,%d" % [cell.x, cell.y]] = { "x": cell.x, "y": cell.y, "ax": ac.x, "ay": ac.y }
	var objs : Dictionary = {}
	for cell : Vector2i in placed_objects:
		objs["%d,%d" % [cell.x, cell.y]] = { "x": cell.x, "y": cell.y, "type": placed_objects[cell] }
	return { "cells": cells, "objects": objs }

func _restore(snap: Dictionary) -> void:
	tile_map.clear()
	placed_objects.clear()
	var cells_data : Dictionary = snap.get("cells", snap)
	for key : String in cells_data:
		var d : Dictionary = cells_data[key]
		if not (d.has("ax") and d.has("ay")):
			continue
		tile_map.set_cell(Vector2i(int(d.x), int(d.y)), 0, Vector2i(int(d.ax), int(d.ay)))
	for obj_d : Dictionary in snap.get("objects", {}).values():
		placed_objects[Vector2i(int(obj_d.x), int(obj_d.y))] = str(obj_d.get("type", ""))
	_redraw_overlay()

# ---------------------------------------------------------------------------
# Save / Load
# ---------------------------------------------------------------------------

func _new_map() -> void:
	_push_undo()
	tile_map.clear()
	placed_objects.clear()
	map_name_input.text = "new_map"
	_deselect()
	_set_status("New map — Ctrl+S to save")

func _save_map() -> void:
	map_name = map_name_input.text.strip_edges()
	if map_name.is_empty():
		map_name = "untitled"

	var cells : Array = []
	for cell : Vector2i in tile_map.get_used_cells():
		var ac : Vector2i = tile_map.get_cell_atlas_coords(cell)
		cells.append({ "x": cell.x, "y": cell.y, "ax": ac.x, "ay": ac.y })

	var objects : Array = []
	for cell : Vector2i in placed_objects:
		objects.append({ "x": cell.x, "y": cell.y, "type": placed_objects[cell] })

	var data : Dictionary = { "name": map_name, "cells": cells, "objects": objects }
	var path : String     = SAVE_PATH + map_name + ".json"
	var file : FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		_set_status("Saved: " + path)
	else:
		_set_status("ERROR: could not save to " + path)

func _load_map(path: String) -> void:
	if not FileAccess.file_exists(path):
		_set_status("File not found: " + path)
		return
	var file   : FileAccess = FileAccess.open(path, FileAccess.READ)
	var result : Variant    = JSON.parse_string(file.get_as_text())
	file.close()
	if not result is Dictionary:
		_set_status("Parse error: " + path)
		return
	var data : Dictionary = result
	_push_undo()
	tile_map.clear()
	placed_objects.clear()
	for cd : Dictionary in data.get("cells", []):
		tile_map.set_cell(Vector2i(int(cd.x), int(cd.y)), 0, Vector2i(int(cd.ax), int(cd.ay)))
	for od : Dictionary in data.get("objects", []):
		placed_objects[Vector2i(int(od.x), int(od.y))] = str(od.get("type", ""))
	map_name_input.text = str(data.get("name", "untitled"))
	_deselect()
	_set_status("Loaded: " + path)

func _load_latest_map() -> void:
	_refresh_map_list()
	if map_file_list.is_empty():
		_set_status("No saved maps found in " + SAVE_PATH)
		return
	map_file_idx = map_file_list.size() - 1
	_load_map(map_file_list[map_file_idx])

func _cycle_map(direction: int) -> void:
	_refresh_map_list()
	if map_file_list.is_empty():
		_set_status("No saved maps found")
		return
	map_file_idx = (map_file_idx + direction + map_file_list.size()) % map_file_list.size()
	_load_map(map_file_list[map_file_idx])
	_set_status("Map %d/%d: %s" % [map_file_idx + 1, map_file_list.size(), map_file_list[map_file_idx]])

func _refresh_map_list() -> void:
	var dir : DirAccess = DirAccess.open(SAVE_PATH)
	if not dir:
		return
	map_file_list.clear()
	dir.list_dir_begin()
	var fname : String = dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			map_file_list.append(SAVE_PATH + fname)
		fname = dir.get_next()
	map_file_list.sort()

# ---------------------------------------------------------------------------
# Overlay — grid, hover highlight, selection rect, object markers
# (Built as a Node2D child of TileMap with a runtime-compiled script.)
# ---------------------------------------------------------------------------

func _build_overlay() -> void:
	var scr : GDScript = GDScript.new()
	scr.source_code = "extends Node2D\nvar host: Node\nfunc _draw() -> void:\n\tif host: host._draw_overlays(self)"
	if scr.reload() != OK:
		push_warning("LevelDesigner: overlay script failed to compile")
		return
	var node : Node2D = Node2D.new()
	node.set_script(scr)
	tile_map.add_child(node)
	node.set("host", self)
	overlay_node = node

func _redraw_overlay() -> void:
	if overlay_node:
		overlay_node.queue_redraw()

func _draw_overlays(ci: Node2D) -> void:
	_draw_grid_layer(ci)
	_draw_hover_layer(ci)
	_draw_selection_layer(ci)
	_draw_objects_layer(ci)

func _draw_grid_layer(ci: Node2D) -> void:
	if not show_grid:
		return
	var col  : Color = Color(1.0, 1.0, 1.0, 0.18)
	var cols : int   = int(sub_viewport.size.x / TILE_SIZE) + 2
	var rows : int   = int(sub_viewport.size.y / TILE_SIZE) + 2
	for x : int in cols + 1:
		ci.draw_line(Vector2(x * TILE_SIZE, 0), Vector2(x * TILE_SIZE, rows * TILE_SIZE), col, 0.5)
	for y : int in rows + 1:
		ci.draw_line(Vector2(0, y * TILE_SIZE), Vector2(cols * TILE_SIZE, y * TILE_SIZE), col, 0.5)

func _draw_hover_layer(ci: Node2D) -> void:
	if hover_cell == INVALID_CELL:
		return
	var rect : Rect2 = Rect2(
		Vector2(hover_cell.x * TILE_SIZE, hover_cell.y * TILE_SIZE),
		Vector2(TILE_SIZE, TILE_SIZE)
	)
	ci.draw_rect(rect, Color(1.0, 1.0, 0.0, 0.25), true)
	ci.draw_rect(rect, Color(1.0, 1.0, 0.0, 0.8), false, 0.8)

func _draw_selection_layer(ci: Node2D) -> void:
	if not sel_active or sel_start == INVALID_CELL:
		return
	var x0 : int = min(sel_start.x, sel_end.x)
	var y0 : int = min(sel_start.y, sel_end.y)
	var x1 : int = max(sel_start.x, sel_end.x)
	var y1 : int = max(sel_start.y, sel_end.y)
	var rect : Rect2 = Rect2(
		Vector2(x0 * TILE_SIZE, y0 * TILE_SIZE),
		Vector2((x1 - x0 + 1) * TILE_SIZE, (y1 - y0 + 1) * TILE_SIZE)
	)
	ci.draw_rect(rect, Color(0.2, 0.6, 1.0, 0.22), true)
	ci.draw_rect(rect, Color(0.2, 0.6, 1.0, 1.0), false, 1.0)

func _draw_objects_layer(ci: Node2D) -> void:
	for cell : Vector2i in placed_objects:
		var obj_type : String = placed_objects[cell]
		var col : Color = OBJECT_COLORS.get(obj_type, Color(1.0, 1.0, 1.0, 0.8))
		var pos  : Vector2 = Vector2(cell.x * TILE_SIZE + 2, cell.y * TILE_SIZE + 2)
		var size : Vector2 = Vector2(TILE_SIZE - 4, TILE_SIZE - 4)
		ci.draw_rect(Rect2(pos, size), col, true)
		ci.draw_rect(Rect2(pos, size), Color(0.0, 0.0, 0.0, 0.8), false, 0.8)

# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------

func _build_palette() -> void:
	var group : ButtonGroup = ButtonGroup.new()
	for i : int in 8:
		var btn : Button = Button.new()
		btn.text               = "T%d" % i
		btn.custom_minimum_size = Vector2(32.0, 32.0)
		btn.toggle_mode        = true
		btn.button_group       = group
		btn.pressed.connect(_on_tile_selected.bind(Vector2i(i, 0)))
		tile_palette.add_child(btn)
		palette_buttons.append(btn)
	if palette_buttons.size() > 0:
		palette_buttons[0].button_pressed = true

func _on_tile_selected(atlas: Vector2i) -> void:
	selected_atlas = atlas
	_set_tool(Tool.PAINT)
	_set_status("Tile atlas %s selected" % atlas)

# ---------------------------------------------------------------------------
# Object palette
# ---------------------------------------------------------------------------

func _build_object_palette() -> void:
	if not object_palette:
		return
	for obj_type : String in OBJECT_TYPES:
		object_palette.add_item(obj_type)

# ---------------------------------------------------------------------------
# Toolbar
# ---------------------------------------------------------------------------

func _build_toolbar() -> void:
	var tool_group : ButtonGroup = ButtonGroup.new()
	var tool_entries : Array = [
		["Paint(F1)", Tool.PAINT], ["Erase(F2)", Tool.ERASE],
		["Fill(F3)",  Tool.FILL],  ["Select(F4)", Tool.SELECT],
		["Object(F5)", Tool.OBJECT],
	]
	for entry : Array in tool_entries:
		var btn : Button = Button.new()
		btn.text         = str(entry[0])
		btn.toggle_mode  = true
		btn.button_group = tool_group
		var t : Tool = entry[1] as Tool
		btn.pressed.connect(_set_tool.bind(t))
		toolbar.add_child(btn)
		tool_buttons.append(btn)

	# Grid toggle
	var grid_btn : Button = Button.new()
	grid_btn.text           = "Grid(G)"
	grid_btn.toggle_mode    = true
	grid_btn.button_pressed = show_grid
	grid_btn.toggled.connect(func(on: bool) -> void:
		show_grid = on
		_redraw_overlay()
		_set_status("Grid %s" % ("on" if on else "off"))
	)
	toolbar.add_child(grid_btn)

	# New / Save / Load
	for data : Array in [["New(Ctrl+N)", _new_map], ["Save(Ctrl+S)", _save_map], ["Load(Ctrl+L)", _load_latest_map]]:
		var btn : Button = Button.new()
		btn.text = str(data[0])
		btn.pressed.connect(data[1] as Callable)
		toolbar.add_child(btn)

	_update_tool_buttons()

func _set_tool(t: Tool) -> void:
	current_tool = t
	_update_tool_buttons()
	_set_status("Tool → %s" % Tool.keys()[t])

func _update_tool_buttons() -> void:
	for i : int in tool_buttons.size():
		tool_buttons[i].button_pressed = (i == int(current_tool))

# ---------------------------------------------------------------------------
# Properties panel
# ---------------------------------------------------------------------------

func _build_props_panel() -> void:
	if not props_panel:
		return
	props_label = Label.new()
	props_label.text         = "Hover over the map"
	props_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	props_panel.add_child(props_label)

func _update_props(cell: Vector2i) -> void:
	if not props_label:
		return
	var ac  : Vector2i = tile_map.get_cell_atlas_coords(cell)
	var obj : String   = placed_objects.get(cell, "")
	var txt : String   = "Cell: (%d, %d)\nAtlas: %s\nTool: %s" % [
		cell.x, cell.y,
		str(ac) if ac != Vector2i(-1, -1) else "empty",
		Tool.keys()[current_tool],
	]
	if obj != "":
		txt += "\nObject: " + obj
	if sel_active and sel_start != INVALID_CELL:
		var w : int = abs(sel_end.x - sel_start.x) + 1
		var h : int = abs(sel_end.y - sel_start.y) + 1
		txt += "\nSelection: %d×%d" % [w, h]
	props_label.text = txt

# ---------------------------------------------------------------------------
# Zoom
# ---------------------------------------------------------------------------

func _apply_zoom() -> void:
	sub_viewport.canvas_transform = Transform2D.IDENTITY.scaled(Vector2.ONE * zoom_level)
	_redraw_overlay()
	_set_status("Zoom %.1fx" % zoom_level)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _viewport_mouse_pos(screen_pos: Vector2) -> Vector2:
	if vp_container:
		var rect : Rect2 = vp_container.get_global_rect()
		if not rect.has_point(screen_pos):
			return INVALID_POS
		return (screen_pos - rect.position) / zoom_level
	# Fallback for non-standard scene layouts
	var vp_rect : Rect2 = sub_viewport.get_visible_rect()
	if not vp_rect.has_point(screen_pos):
		return INVALID_POS
	return (screen_pos - vp_rect.position) / zoom_level

func _set_status(msg: String) -> void:
	if status_bar:
		status_bar.text = msg
