## GameManager — persistent game state, save/load, inventory, and flags.
##
## Autoloaded as "GameManager". All other scripts read/write through here so
## there is one canonical source of truth for every piece of game state.
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal game_saved
signal game_loaded
signal gold_changed(new_amount: int)
signal settings_changed

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const SAVE_DIR      : String = "user://saves/"
const SETTINGS_PATH : String = "user://settings.json"
const SAVE_VERSION  : int    = 1
const TILE_SIZE     : int    = 16    ## World units → pixels multiplier.

# ---------------------------------------------------------------------------
# Persistent world state
# ---------------------------------------------------------------------------
var current_save_slot : int    = 0
var play_time         : float  = 0.0  ## Total seconds in-game.
var current_map       : String = "overworld"
var player_position   : Vector2 = Vector2(10.0, 10.0)  ## In tile coords.
var dungeon_seed      : int    = 0
var dungeon_floor     : int    = 1

# ---------------------------------------------------------------------------
# Economy
# ---------------------------------------------------------------------------
var gold : int = 0 :
	set(v):
		gold = max(0, v)
		emit_signal("gold_changed", gold)

# ---------------------------------------------------------------------------
# Inventory  —  Array of Dictionaries: { id, name, qty, type, stats? }
# ---------------------------------------------------------------------------
var inventory : Array[Dictionary] = []

# ---------------------------------------------------------------------------
# Story / world flags  —  { flag_name: Variant }
# ---------------------------------------------------------------------------
var game_flags : Dictionary = {}

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------
var settings : Dictionary = {
	"sfx_volume"   : 0.8,
	"music_volume" : 0.7,
	"fullscreen"   : false,
	"show_fps"     : false,
}

# ---------------------------------------------------------------------------
# Built-ins
# ---------------------------------------------------------------------------
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_load_settings()

func _process(delta: float) -> void:
	play_time += delta

# ---------------------------------------------------------------------------
# Inventory
# ---------------------------------------------------------------------------

## Add an item, stacking if the same id already exists.
func add_item(item: Dictionary) -> void:
	for existing in inventory:
		if existing.id == item.id:
			existing.qty += item.get("qty", 1)
			return
	var copy : Dictionary = item.duplicate()
	copy["qty"] = item.get("qty", 1)
	inventory.append(copy)

## Remove qty units of item_id. Returns false if not found.
func remove_item(item_id: String, qty: int = 1) -> bool:
	for i in inventory.size():
		if inventory[i].id == item_id:
			inventory[i].qty -= qty
			if inventory[i].qty <= 0:
				inventory.remove_at(i)
			return true
	return false

func has_item(item_id: String) -> bool:
	for item in inventory:
		if item.id == item_id:
			return true
	return false

func get_item_qty(item_id: String) -> int:
	for item in inventory:
		if item.id == item_id:
			return item.qty
	return 0

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------

func set_flag(flag: String, value: Variant = true) -> void:
	game_flags[flag] = value

func get_flag(flag: String, default: Variant = false) -> Variant:
	return game_flags.get(flag, default)

func check_flag(flag: String) -> bool:
	return bool(game_flags.get(flag, false))

# ---------------------------------------------------------------------------
# Save / Load
# ---------------------------------------------------------------------------

func save_game(slot: int = 0) -> bool:
	current_save_slot = slot
	var data : Dictionary = {
		"version"         : SAVE_VERSION,
		"play_time"       : play_time,
		"gold"            : gold,
		"inventory"       : inventory,
		"game_flags"      : game_flags,
		"current_map"     : current_map,
		"player_position" : { "x": player_position.x, "y": player_position.y },
		"dungeon_seed"    : dungeon_seed,
		"dungeon_floor"   : dungeon_floor,
		"party"           : PartyManager.serialize(),
		"story"           : StoryManager.serialize(),
		"era"             : EraManager.serialize(),
	}
	var path : String = SAVE_DIR + "save_%d.json" % slot
	var file : FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("GameManager: save failed — cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	emit_signal("game_saved")
	return true

func load_game(slot: int = 0) -> bool:
	var path : String = SAVE_DIR + "save_%d.json" % slot
	if not FileAccess.file_exists(path):
		return false
	var file : FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	var result : Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not result is Dictionary:
		push_error("GameManager: save file corrupt — %s" % path)
		return false
	var data : Dictionary = result
	play_time       = float(data.get("play_time", 0.0))
	gold            = int(data.get("gold", 0))
	inventory       = data.get("inventory", [])
	game_flags      = data.get("game_flags", {})
	current_map     = str(data.get("current_map", "overworld"))
	dungeon_seed    = int(data.get("dungeon_seed", 0))
	dungeon_floor   = int(data.get("dungeon_floor", 1))
	var pp : Dictionary = data.get("player_position", {"x": 10, "y": 10})
	player_position = Vector2(float(pp.get("x", 10)), float(pp.get("y", 10)))
	PartyManager.deserialize(data.get("party", {}))
	StoryManager.deserialize(data.get("story", {}))
	EraManager.deserialize(data.get("era", {}))
	current_save_slot = slot
	emit_signal("game_loaded")
	return true

func save_exists(slot: int = 0) -> bool:
	return FileAccess.file_exists(SAVE_DIR + "save_%d.json" % slot)

func delete_save(slot: int) -> void:
	var path : String = SAVE_DIR + "save_%d.json" % slot
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file : FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if not file:
		return
	var result : Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if result is Dictionary:
		settings.merge(result, true)
	_apply_settings()

func save_settings() -> void:
	var file : FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(settings, "\t"))
		file.close()
	_apply_settings()
	emit_signal("settings_changed")

func _apply_settings() -> void:
	var mode : DisplayServer.WindowMode = (
		DisplayServer.WINDOW_MODE_FULLSCREEN
		if settings.get("fullscreen", false)
		else DisplayServer.WINDOW_MODE_WINDOWED
	)
	DisplayServer.window_set_mode(mode)

# ---------------------------------------------------------------------------
# New Game
# ---------------------------------------------------------------------------

## Reset all state and start fresh.
func new_game() -> void:
	play_time       = 0.0
	gold            = 0
	inventory       = []
	game_flags      = {}
	current_map     = "overworld"
	player_position = Vector2(10.0, 10.0)
	dungeon_seed    = randi()
	dungeon_floor   = 1
	PartyManager.init_default_party()
	StoryManager.reset()
	EraManager.reset()
	StoryManager.start_chapter("ch1_the_hold")

# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

func format_play_time() -> String:
	var h : int = int(play_time / 3600)
	var m : int = int(fmod(play_time, 3600.0) / 60)
	var s : int = int(fmod(play_time, 60.0))
	return "%02d:%02d:%02d" % [h, m, s]

## Seed the next dungeon floor and increment the floor counter.
func advance_dungeon_floor() -> void:
	dungeon_floor += 1
	dungeon_seed   = randi()
