extends Node

# ── Signals ──────────────────────────────────────────────────────────────────
signal game_saved
signal game_loaded
signal settings_changed

# ── Constants ────────────────────────────────────────────────────────────────
const SAVE_DIR     := "user://saves/"
const SAVE_VERSION := 1
const TILE_SIZE    := 16

# ── State ────────────────────────────────────────────────────────────────────
var current_save_slot: int = 0
var game_flags: Dictionary = {}          # story/world flags: { flag_name: value }
var inventory: Array[Dictionary] = []    # [{ id, name, qty, type, stats }]
var gold: int = 0
var play_time: float = 0.0
var current_map: String = "overworld"
var player_position: Vector2 = Vector2(10, 10)
var dungeon_seed: int = 0

# ── Settings ─────────────────────────────────────────────────────────────────
var settings: Dictionary = {
	"sfx_volume": 0.8,
	"music_volume": 0.7,
	"fullscreen": false,
	"show_fps": false,
}

# ── Built-ins ────────────────────────────────────────────────────────────────
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_load_settings()

func _process(delta: float) -> void:
	play_time += delta

# ── Inventory ────────────────────────────────────────────────────────────────
func add_item(item: Dictionary) -> void:
	for existing in inventory:
		if existing.id == item.id:
			existing.qty += item.get("qty", 1)
			return
	var copy := item.duplicate()
	copy["qty"] = item.get("qty", 1)
	inventory.append(copy)

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

# ── Flags ─────────────────────────────────────────────────────────────────────
func set_flag(flag: String, value: Variant = true) -> void:
	game_flags[flag] = value

func get_flag(flag: String, default: Variant = false) -> Variant:
	return game_flags.get(flag, default)

func check_flag(flag: String) -> bool:
	return bool(game_flags.get(flag, false))

# ── Save / Load ───────────────────────────────────────────────────────────────
func save_game(slot: int = 0) -> bool:
	current_save_slot = slot
	var data := {
		"version":        SAVE_VERSION,
		"play_time":      play_time,
		"gold":           gold,
		"inventory":      inventory,
		"game_flags":     game_flags,
		"current_map":    current_map,
		"player_position": { "x": player_position.x, "y": player_position.y },
		"dungeon_seed":   dungeon_seed,
		"party":          PartyManager.serialize(),
		"story":          StoryManager.serialize(),
	}
	var path := SAVE_DIR + "save_%d.json" % slot
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Save failed: cannot open %s" % path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	emit_signal("game_saved")
	return true

func load_game(slot: int = 0) -> bool:
	var path := SAVE_DIR + "save_%d.json" % slot
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	var text   := file.get_as_text()
	file.close()
	var result: Variant = JSON.parse_string(text)
	if result == null:
		push_error("Save corrupt: %s" % path)
		return false
	var data: Dictionary = result
	play_time       = data.get("play_time", 0.0)
	gold            = data.get("gold", 0)
	inventory       = data.get("inventory", [])
	game_flags      = data.get("game_flags", {})
	current_map     = data.get("current_map", "overworld")
	dungeon_seed    = data.get("dungeon_seed", 0)
	var pp          = data.get("player_position", {"x": 10, "y": 10})
	player_position = Vector2(pp.x, pp.y)
	PartyManager.deserialize(data.get("party", {}))
	StoryManager.deserialize(data.get("story", {}))
	current_save_slot = slot
	emit_signal("game_loaded")
	return true

func save_exists(slot: int = 0) -> bool:
	return FileAccess.file_exists(SAVE_DIR + "save_%d.json" % slot)

func delete_save(slot: int) -> void:
	var path := SAVE_DIR + "save_%d.json" % slot
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

# ── Settings ──────────────────────────────────────────────────────────────────
func _load_settings() -> void:
	var path := "user://settings.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var result: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if result is Dictionary:
		settings.merge(result, true)
	_apply_settings()

func save_settings() -> void:
	var file := FileAccess.open("user://settings.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(settings, "\t"))
		file.close()
	emit_signal("settings_changed")

func _apply_settings() -> void:
	if settings.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

# ── New Game ──────────────────────────────────────────────────────────────────
func new_game() -> void:
	play_time       = 0.0
	gold            = 0
	inventory       = []
	game_flags      = {}
	current_map     = "overworld"
	player_position = Vector2(10, 10)
	dungeon_seed    = randi()
	PartyManager.init_default_party()
	StoryManager.reset()

# ── Utility ───────────────────────────────────────────────────────────────────
func format_play_time() -> String:
	var h := int(play_time / 3600)
	var m := int(fmod(play_time, 3600) / 60)
	var s := int(fmod(play_time, 60))
	return "%02d:%02d:%02d" % [h, m, s]
