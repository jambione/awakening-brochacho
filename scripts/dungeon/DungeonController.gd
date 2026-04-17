extends Node2D

# ── Node refs ─────────────────────────────────────────────────────────────────
@onready var tile_map:     TileMapLayer  = $TileMapLayer
@onready var player:       CharacterBody2D = $Player
@onready var enemy_root:   Node2D        = $Enemies
@onready var objects_root: Node2D        = $Objects
@onready var camera:       Camera2D      = $Player/Camera2D
@onready var hud:          CanvasLayer   = $HUD
@onready var minimap:      Control       = $HUD/Minimap

# ── Packed scenes ─────────────────────────────────────────────────────────────
@export var enemy_scenes: Dictionary = {}   # { "slime": preload(...), ... }
@export var chest_scene:  PackedScene
@export var door_scene:   PackedScene

# ── Generator ─────────────────────────────────────────────────────────────────
var generator := DungeonGenerator.new()
var dungeon_data: Dictionary = {}

const TILE_SIZE := 16
# TileSet source / atlas coords — adjust to match your actual TileSet
const ATLAS_SOURCE := 0
const ATLAS := {
	"floor":  Vector2i(0, 0),
	"wall":   Vector2i(1, 0),
	"door":   Vector2i(2, 0),
	"chest":  Vector2i(3, 0),
	"stairs": Vector2i(4, 0),
}

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	add_child(generator)
	var use_seed := GameManager.dungeon_seed
	if use_seed == 0:
		use_seed = randi()
		GameManager.dungeon_seed = use_seed

	dungeon_data = generator.generate(use_seed)
	_paint_tilemap()
	_spawn_enemies()
	_spawn_objects()
	_place_player()
	_setup_minimap()

	AudioManager.play_music("res://assets/audio/music/dungeon_theme.ogg")

# ── TileMap painting ──────────────────────────────────────────────────────────
func _paint_tilemap() -> void:
	var grid: Array = dungeon_data.grid
	for y in dungeon_data.height:
		for x in dungeon_data.width:
			var tile: int = grid[y][x]
			var atlas_coord := _tile_to_atlas(tile)
			if atlas_coord != Vector2i(-1, -1):
				tile_map.set_cell(Vector2i(x, y), ATLAS_SOURCE, atlas_coord)

func _tile_to_atlas(tile: int) -> Vector2i:
	match tile:
		DungeonGenerator.TILE_FLOOR:  return ATLAS.floor
		DungeonGenerator.TILE_WALL:   return ATLAS.wall
		DungeonGenerator.TILE_STAIRS: return ATLAS.stairs
		_:                            return Vector2i(-1, -1)  # void = empty

# ── Enemy spawning ────────────────────────────────────────────────────────────
func _spawn_enemies() -> void:
	for spawn in dungeon_data.enemy_spawns:
		var type: String = spawn.type
		if not enemy_scenes.has(type):
			continue
		var enemy: Node2D = enemy_scenes[type].instantiate()
		enemy.position = Vector2(spawn.pos) * TILE_SIZE
		if enemy.has_method("set_level"):
			enemy.set_level(spawn.level)
		enemy_root.add_child(enemy)

# ── Object spawning (chests, doors) ───────────────────────────────────────────
func _spawn_objects() -> void:
	# Doors
	var grid: Array = dungeon_data.grid
	for y in dungeon_data.height:
		for x in dungeon_data.width:
			if grid[y][x] == DungeonGenerator.TILE_DOOR and door_scene:
				var door := door_scene.instantiate()
				door.position = Vector2(x, y) * TILE_SIZE
				objects_root.add_child(door)

	# Chests
	for pos in dungeon_data.chest_positions:
		if not chest_scene:
			break
		var chest := chest_scene.instantiate()
		chest.position = Vector2(pos) * TILE_SIZE
		objects_root.add_child(chest)

	# Stairs
	var stair_pos: Vector2i = dungeon_data.stairs_pos
	tile_map.set_cell(stair_pos, ATLAS_SOURCE, ATLAS.stairs)

# ── Player placement ──────────────────────────────────────────────────────────
func _place_player() -> void:
	var start: Vector2i = dungeon_data.start_pos
	player.position = Vector2(start) * TILE_SIZE

# ── Minimap ───────────────────────────────────────────────────────────────────
func _setup_minimap() -> void:
	if minimap and minimap.has_method("build_from_data"):
		minimap.build_from_data(dungeon_data)

# ── Stair transition ──────────────────────────────────────────────────────────
func _on_stairs_entered() -> void:
	SceneManager.go_to_dungeon()  # New seed = new dungeon floor

# ── Debug: regenerate on F5 ───────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event.is_action_pressed("ui_cancel"):
		get_tree().reload_current_scene()
