extends Control

# ── Node refs ─────────────────────────────────────────────────────────────────
@onready var tile_map:        TileMapLayer  = $UI/Center/Viewport/SubViewport/TileMap
@onready var sub_viewport:    SubViewport   = $UI/Center/Viewport/SubViewport
@onready var tile_palette:    GridContainer = $UI/Left/Palette
@onready var toolbar:         HBoxContainer = $UI/Center/Top/Toolbar
@onready var status_bar:      Label         = $UI/Center/Bottom/StatusBar
@onready var object_palette:  ItemList      = $UI/Left/ObjectPalette
@onready var properties_panel: VBoxContainer = $UI/Right/Properties
@onready var map_name_input:  LineEdit      = $UI/Center/Top/MapNameInput

# ── State ─────────────────────────────────────────────────────────────────────
enum Tool { PAINT, ERASE, FILL, SELECT, OBJECT }
var current_tool:   Tool   = Tool.PAINT
var selected_tile:  int    = 0
var selected_atlas: Vector2i = Vector2i(0, 0)
var is_painting:    bool   = false
var map_name:       String = "new_map"
var camera_offset:  Vector2 = Vector2.ZERO
var zoom_level:     float = 2.0
var undo_stack:     Array[Dictionary] = []
var redo_stack:     Array[Dictionary] = []
const MAX_UNDO := 50
const TILE_SIZE := 16
const SAVE_PATH := "user://maps/"

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_PATH)
	_build_palette()
	_setup_toolbar()
	sub_viewport.size = Vector2i(320, 240)
	_set_status("Level Designer ready. F1=Paint F2=Erase F3=Fill F4=Select | Ctrl+S=Save Ctrl+Z=Undo")

# ── Input ─────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	# Keyboard shortcuts
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1: _set_tool(Tool.PAINT)
			KEY_F2: _set_tool(Tool.ERASE)
			KEY_F3: _set_tool(Tool.FILL)
			KEY_F4: _set_tool(Tool.SELECT)
			KEY_S:
				if event.ctrl_pressed: _save_map()
			KEY_L:
				if event.ctrl_pressed: _load_map_dialog()
			KEY_Z:
				if event.ctrl_pressed and event.shift_pressed: _redo()
				elif event.ctrl_pressed: _undo()

	# Mouse on viewport
	if event is InputEventMouseButton:
		var local: Vector2 = _viewport_mouse_pos(event.position)
		if local == INVALID_POS:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			is_painting = event.pressed
			if is_painting:
				_push_undo()
				_apply_tool(local)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_erase_at(local)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_level = clamp(zoom_level + 0.25, 0.5, 8.0)
			_update_zoom()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_level = clamp(zoom_level - 0.25, 0.5, 8.0)
			_update_zoom()

	if event is InputEventMouseMotion and is_painting:
		var local: Vector2 = _viewport_mouse_pos(event.position)
		if local != INVALID_POS:
			_apply_tool(local)

# ── Tool application ──────────────────────────────────────────────────────────
func _apply_tool(world_pos: Vector2) -> void:
	var cell := tile_map.local_to_map(world_pos)
	match current_tool:
		Tool.PAINT:  _paint_at(cell)
		Tool.ERASE:  tile_map.erase_cell(cell)
		Tool.FILL:   _flood_fill(cell, selected_atlas)
		Tool.OBJECT: pass  # handled separately

func _paint_at(cell: Vector2i) -> void:
	tile_map.set_cell(cell, 0, selected_atlas)

func _erase_at(world_pos: Vector2) -> void:
	var cell := tile_map.local_to_map(world_pos)
	tile_map.erase_cell(cell)

# ── Flood fill (BFS) ──────────────────────────────────────────────────────────
func _flood_fill(start: Vector2i, new_atlas: Vector2i) -> void:
	var source_atlas := tile_map.get_cell_atlas_coords(start)
	if source_atlas == new_atlas:
		return
	var queue:   Array[Vector2i] = [start]
	var visited: Dictionary      = {}
	var dirs: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	while queue.size() > 0:
		var cell: Vector2i = queue.pop_front()
		var key: String = "%d,%d" % [cell.x, cell.y]
		if visited.has(key):
			continue
		visited[key] = true
		if tile_map.get_cell_atlas_coords(cell) != source_atlas:
			continue
		tile_map.set_cell(cell, 0, new_atlas)
		for d: Vector2i in dirs:
			queue.append(cell + d)

# ── Undo / Redo ───────────────────────────────────────────────────────────────
func _push_undo() -> void:
	var snapshot := _snapshot_tilemap()
	undo_stack.append(snapshot)
	if undo_stack.size() > MAX_UNDO:
		undo_stack.pop_front()
	redo_stack.clear()

func _undo() -> void:
	if undo_stack.is_empty():
		return
	redo_stack.append(_snapshot_tilemap())
	_restore_snapshot(undo_stack.pop_back())
	_set_status("Undo")

func _redo() -> void:
	if redo_stack.is_empty():
		return
	undo_stack.append(_snapshot_tilemap())
	_restore_snapshot(redo_stack.pop_back())
	_set_status("Redo")

func _snapshot_tilemap() -> Dictionary:
	var cells: Dictionary = {}
	for cell in tile_map.get_used_cells():
		cells["%d,%d" % [cell.x, cell.y]] = {
			"pos":   { "x": cell.x, "y": cell.y },
			"atlas": tile_map.get_cell_atlas_coords(cell),
		}
	return cells

func _restore_snapshot(snapshot: Dictionary) -> void:
	tile_map.clear()
	for key in snapshot:
		var d: Dictionary = snapshot[key]
		var pos := Vector2i(d.pos.x, d.pos.y)
		tile_map.set_cell(pos, 0, d.atlas)

# ── Save / Load ───────────────────────────────────────────────────────────────
func _save_map() -> void:
	map_name = map_name_input.text.strip_edges()
	if map_name == "":
		map_name = "untitled"
	var data := { "name": map_name, "cells": [] }
	for cell in tile_map.get_used_cells():
		data.cells.append({
			"x": cell.x, "y": cell.y,
			"atlas_x": tile_map.get_cell_atlas_coords(cell).x,
			"atlas_y": tile_map.get_cell_atlas_coords(cell).y,
		})
	var path := SAVE_PATH + map_name + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		_set_status("Saved: %s" % path)
	else:
		_set_status("ERROR: Could not save to %s" % path)

func _load_map(path: String) -> void:
	if not FileAccess.file_exists(path):
		_set_status("File not found: %s" % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var result: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not result is Dictionary:
		_set_status("Parse error")
		return
	var data: Dictionary = result
	tile_map.clear()
	for cell_data in data.get("cells", []):
		var pos   := Vector2i(cell_data.x, cell_data.y)
		var atlas := Vector2i(cell_data.atlas_x, cell_data.atlas_y)
		tile_map.set_cell(pos, 0, atlas)
	map_name_input.text = data.get("name", "untitled")
	_set_status("Loaded: %s" % path)

func _load_map_dialog() -> void:
	# Simple: load most recently modified map
	var dir := DirAccess.open(SAVE_PATH)
	if not dir:
		return
	dir.list_dir_begin()
	var files: Array[String] = []
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			files.append(SAVE_PATH + fname)
		fname = dir.get_next()
	if files.size() > 0:
		files.sort()
		_load_map(files.back())

# ── Palette ───────────────────────────────────────────────────────────────────
func _build_palette() -> void:
	# Placeholder — you'll add real tile buttons when you have a TileSet loaded
	for i in 8:
		var btn := Button.new()
		btn.text   = "T%d" % i
		btn.custom_minimum_size = Vector2(32, 32)
		btn.pressed.connect(_on_tile_selected.bind(i, Vector2i(i, 0)))
		tile_palette.add_child(btn)

func _on_tile_selected(tile_id: int, atlas: Vector2i) -> void:
	selected_tile  = tile_id
	selected_atlas = atlas
	current_tool   = Tool.PAINT
	_set_status("Tile %d selected" % tile_id)

# ── Toolbar ───────────────────────────────────────────────────────────────────
func _setup_toolbar() -> void:
	var tool_names := ["Paint(F1)", "Erase(F2)", "Fill(F3)", "Select(F4)"]
	for i in tool_names.size():
		var btn := Button.new()
		btn.text = tool_names[i]
		btn.pressed.connect(_set_tool.bind(i as Tool))
		toolbar.add_child(btn)

	var save_btn := Button.new()
	save_btn.text = "Save (Ctrl+S)"
	save_btn.pressed.connect(_save_map)
	toolbar.add_child(save_btn)

	var load_btn := Button.new()
	load_btn.text = "Load (Ctrl+L)"
	load_btn.pressed.connect(_load_map_dialog)
	toolbar.add_child(load_btn)

func _set_tool(tool: Tool) -> void:
	current_tool = tool
	_set_status("Tool: %s" % Tool.keys()[tool])

# ── Zoom ──────────────────────────────────────────────────────────────────────
func _update_zoom() -> void:
	sub_viewport.canvas_transform = Transform2D.IDENTITY.scaled(Vector2.ONE * zoom_level)
	_set_status("Zoom: %.1fx" % zoom_level)

# ── Helpers ───────────────────────────────────────────────────────────────────
const INVALID_POS := Vector2(-1.0, -1.0)

func _viewport_mouse_pos(screen_pos: Vector2) -> Vector2:
	var vp_rect := sub_viewport.get_visible_rect()
	if not vp_rect.has_point(screen_pos):
		return INVALID_POS
	return (screen_pos - vp_rect.position) / zoom_level

func _set_status(msg: String) -> void:
	if status_bar:
		status_bar.text = msg
