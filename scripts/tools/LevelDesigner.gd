## LevelDesigner — in-game tile-painting tool with save/load.
##
## Keyboard shortcuts:
##   F1  Paint    F2  Erase    F3  Fill    F4  Select
##   Ctrl+S  Save map    Ctrl+L  Load latest map
##   Ctrl+Z  Undo         Ctrl+Shift+Z  Redo
##   Scroll wheel  Zoom in/out
##   Right-click  Erase single tile
extends Control

# ---------------------------------------------------------------------------
# Node references — paths must match LevelDesigner.tscn
# ---------------------------------------------------------------------------
@onready var tile_map      : TileMapLayer  = $UI/Center/Viewport/SubViewport/TileMap
@onready var sub_viewport  : SubViewport   = $UI/Center/Viewport/SubViewport
@onready var tile_palette  : GridContainer = $UI/Left/Palette
@onready var toolbar       : HBoxContainer = $UI/Center/Top/Toolbar
@onready var status_bar    : Label         = $UI/Center/Bottom/StatusBar
@onready var object_palette: ItemList      = $UI/Left/ObjectPalette
@onready var props_panel   : VBoxContainer = $UI/Right/Properties
@onready var map_name_input: LineEdit      = $UI/Center/Top/MapNameInput

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

## Invalid sentinel — returned when the mouse is outside the viewport.
const INVALID_POS : Vector2 = Vector2(-1.0, -1.0)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var current_tool   : Tool      = Tool.PAINT
var selected_atlas : Vector2i  = Vector2i(0, 0)
var is_painting    : bool      = false
var map_name       : String    = "new_map"
var zoom_level     : float     = 2.0
var undo_stack     : Array[Dictionary] = []
var redo_stack     : Array[Dictionary] = []

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_PATH)
	sub_viewport.size = Vector2i(320, 240)
	_build_palette()
	_build_toolbar()
	_set_status("LevelDesigner ready | F1 Paint  F2 Erase  F3 Fill  F4 Select | Ctrl+S Save  Ctrl+Z Undo")

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# ── Keyboard shortcuts ──────────────────────────────────────────────────
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1: _set_tool(Tool.PAINT)
			KEY_F2: _set_tool(Tool.ERASE)
			KEY_F3: _set_tool(Tool.FILL)
			KEY_F4: _set_tool(Tool.SELECT)
			KEY_S:
				if event.ctrl_pressed: _save_map()
			KEY_L:
				if event.ctrl_pressed: _load_latest_map()
			KEY_Z:
				if event.ctrl_pressed and event.shift_pressed: _redo()
				elif event.ctrl_pressed: _undo()

	# ── Mouse ────────────────────────────────────────────────────────────────
	if event is InputEventMouseButton:
		var world : Vector2 = _viewport_mouse_pos(event.position)
		if world == INVALID_POS:
			return

		if event.button_index == MOUSE_BUTTON_LEFT:
			is_painting = event.pressed
			if is_painting:
				_push_undo()
				_apply_tool(world)

		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_push_undo()
			tile_map.erase_cell(tile_map.local_to_map(world))

		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_level = clampf(zoom_level + 0.25, 0.5, 8.0)
			_apply_zoom()

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_level = clampf(zoom_level - 0.25, 0.5, 8.0)
			_apply_zoom()

	if event is InputEventMouseMotion and is_painting:
		var world : Vector2 = _viewport_mouse_pos(event.position)
		if world != INVALID_POS:
			_apply_tool(world)

# ---------------------------------------------------------------------------
# Tool dispatch
# ---------------------------------------------------------------------------

func _apply_tool(world_pos: Vector2) -> void:
	var cell : Vector2i = tile_map.local_to_map(world_pos)
	match current_tool:
		Tool.PAINT:  tile_map.set_cell(cell, 0, selected_atlas)
		Tool.ERASE:  tile_map.erase_cell(cell)
		Tool.FILL:   _flood_fill(cell, selected_atlas)
		_: pass  # SELECT / OBJECT handled elsewhere

# ---------------------------------------------------------------------------
# Flood fill  (BFS — won't overflow on large maps like recursion would)
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
	_set_status("Undo")

func _redo() -> void:
	if redo_stack.is_empty():
		return
	undo_stack.append(_snapshot())
	_restore(redo_stack.pop_back())
	_set_status("Redo")

## Capture the current tilemap state as a serialisable Dictionary.
func _snapshot() -> Dictionary:
	var cells : Dictionary = {}
	for cell in tile_map.get_used_cells():
		var ac : Vector2i = tile_map.get_cell_atlas_coords(cell)
		cells["%d,%d" % [cell.x, cell.y]] = {
			"x": cell.x, "y": cell.y,
			"ax": ac.x,  "ay": ac.y,
		}
	return cells

func _restore(snapshot: Dictionary) -> void:
	tile_map.clear()
	for key in snapshot:
		var d    : Dictionary = snapshot[key]
		var pos  : Vector2i   = Vector2i(int(d.x), int(d.y))
		var atlas: Vector2i   = Vector2i(int(d.ax), int(d.ay))
		tile_map.set_cell(pos, 0, atlas)

# ---------------------------------------------------------------------------
# Save / Load
# ---------------------------------------------------------------------------

func _save_map() -> void:
	map_name = map_name_input.text.strip_edges()
	if map_name.is_empty():
		map_name = "untitled"

	var cells : Array = []
	for cell in tile_map.get_used_cells():
		var ac : Vector2i = tile_map.get_cell_atlas_coords(cell)
		cells.append({ "x": cell.x, "y": cell.y, "ax": ac.x, "ay": ac.y })

	var data : Dictionary = { "name": map_name, "cells": cells }
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
	for cd in data.get("cells", []):
		var d    : Dictionary = cd
		var pos  : Vector2i   = Vector2i(int(d.x), int(d.y))
		var atlas: Vector2i   = Vector2i(int(d.ax), int(d.ay))
		tile_map.set_cell(pos, 0, atlas)
	map_name_input.text = str(data.get("name", "untitled"))
	_set_status("Loaded: " + path)

func _load_latest_map() -> void:
	var dir : DirAccess = DirAccess.open(SAVE_PATH)
	if not dir:
		return
	var files : Array[String] = []
	dir.list_dir_begin()
	var fname : String = dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			files.append(SAVE_PATH + fname)
		fname = dir.get_next()
	if files.size() > 0:
		files.sort()
		_load_map(files.back())

# ---------------------------------------------------------------------------
# Palette  (programmatic — replace with real tile buttons once TileSet exists)
# ---------------------------------------------------------------------------

func _build_palette() -> void:
	for i in 8:
		var btn : Button = Button.new()
		btn.text = "T%d" % i
		btn.custom_minimum_size = Vector2(32.0, 32.0)
		btn.pressed.connect(_on_tile_selected.bind(Vector2i(i, 0)))
		tile_palette.add_child(btn)

func _on_tile_selected(atlas: Vector2i) -> void:
	selected_atlas = atlas
	current_tool   = Tool.PAINT
	_set_status("Selected tile atlas %s" % atlas)

# ---------------------------------------------------------------------------
# Toolbar
# ---------------------------------------------------------------------------

func _build_toolbar() -> void:
	for entry in [["Paint(F1)", Tool.PAINT], ["Erase(F2)", Tool.ERASE],
				  ["Fill(F3)",  Tool.FILL],  ["Select(F4)", Tool.SELECT]]:
		var btn : Button = Button.new()
		btn.text = str(entry[0])
		var t : Tool = entry[1] as Tool
		btn.pressed.connect(_set_tool.bind(t))
		toolbar.add_child(btn)

	var save_btn : Button = Button.new()
	save_btn.text = "Save (Ctrl+S)"
	save_btn.pressed.connect(_save_map)
	toolbar.add_child(save_btn)

	var load_btn : Button = Button.new()
	load_btn.text = "Load (Ctrl+L)"
	load_btn.pressed.connect(_load_latest_map)
	toolbar.add_child(load_btn)

func _set_tool(t: Tool) -> void:
	current_tool = t
	_set_status("Tool → " + Tool.keys()[t])

# ---------------------------------------------------------------------------
# Zoom
# ---------------------------------------------------------------------------

func _apply_zoom() -> void:
	sub_viewport.canvas_transform = Transform2D.IDENTITY.scaled(Vector2.ONE * zoom_level)
	_set_status("Zoom %.1fx" % zoom_level)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Convert a screen-space position to world-space inside the SubViewport.
## Returns INVALID_POS if the cursor is outside the viewport container.
func _viewport_mouse_pos(screen_pos: Vector2) -> Vector2:
	var vp_rect : Rect2 = sub_viewport.get_visible_rect()
	if not vp_rect.has_point(screen_pos):
		return INVALID_POS
	return (screen_pos - vp_rect.position) / zoom_level

func _set_status(msg: String) -> void:
	if status_bar:
		status_bar.text = msg
