## DungeonController — wires the DungeonGenerator output onto live scene nodes.
##
## Attach to the root Node2D of Dungeon.tscn. All @export variables should be
## set in the Inspector so this script stays data-driven and easy to swap.
extends Node2D

# ---------------------------------------------------------------------------
# Inspector-configurable packed scenes (drag & drop in editor)
# ---------------------------------------------------------------------------
## One entry per enemy type key used in DungeonGenerator (e.g. "slime").
@export var enemy_scenes  : Dictionary   = {}
@export var chest_scene   : PackedScene
@export var door_scene    : PackedScene

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var tile_map    : TileMapLayer    = $TileMapLayer
@onready var enemies_root: Node2D          = $Enemies
@onready var objects_root: Node2D          = $Objects
@onready var player      : CharacterBody2D = $Player
@onready var minimap     : Control         = $HUD/Minimap

# ---------------------------------------------------------------------------
# TileSet atlas configuration — update these to match your actual TileSet.
# ---------------------------------------------------------------------------
const ATLAS_SOURCE : int = 0  ## TileSet source index.
## Maps tile ID constants to atlas coordinates in the TileSet sprite sheet.
const ATLAS : Dictionary = {
	DungeonGenerator.TILE_FLOOR  : Vector2i(0, 0),
	DungeonGenerator.TILE_WALL   : Vector2i(1, 0),
	DungeonGenerator.TILE_DOOR   : Vector2i(2, 0),
	DungeonGenerator.TILE_CHEST  : Vector2i(3, 0),
	DungeonGenerator.TILE_STAIRS : Vector2i(4, 0),
}
const TILE_SIZE : int = 16

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var dungeon_data : Dictionary = {}

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Seed may have been set by SceneManager before the scene loaded.
	if GameManager.dungeon_seed == 0:
		GameManager.dungeon_seed = randi()

	var gen : DungeonGenerator = DungeonGenerator.new()
	add_child(gen)
	dungeon_data = gen.generate(GameManager.dungeon_seed)

	_paint_tilemap()
	_spawn_objects()
	_spawn_enemies()
	_place_player()
	_init_minimap()

	AudioManager.play_music("res://assets/audio/music/dungeon_theme.ogg")

# ---------------------------------------------------------------------------
# TileMap painting
# ---------------------------------------------------------------------------

func _paint_tilemap() -> void:
	var grid   : Array = dungeon_data.grid
	var height : int   = dungeon_data.height
	var width  : int   = dungeon_data.width

	for y in height:
		for x in width:
			var tile_id : int = int(grid[y][x])
			if ATLAS.has(tile_id):
				tile_map.set_cell(Vector2i(x, y), ATLAS_SOURCE, ATLAS[tile_id])

# ---------------------------------------------------------------------------
# Object spawning (chests, doors)
# ---------------------------------------------------------------------------

func _spawn_objects() -> void:
	var grid : Array = dungeon_data.grid

	# Doors — read from the grid so placement is always consistent.
	if door_scene:
		for y in dungeon_data.height:
			for x in dungeon_data.width:
				if int(grid[y][x]) == DungeonGenerator.TILE_DOOR:
					var door : Node2D = door_scene.instantiate()
					door.position = Vector2(x, y) * TILE_SIZE
					objects_root.add_child(door)

	# Chests — use the pre-computed list from the generator.
	if chest_scene:
		for pos in dungeon_data.chest_positions:
			var chest : Node2D = chest_scene.instantiate()
			chest.position = Vector2(pos) * TILE_SIZE
			objects_root.add_child(chest)

# ---------------------------------------------------------------------------
# Enemy spawning
# ---------------------------------------------------------------------------

func _spawn_enemies() -> void:
	for spawn in dungeon_data.enemy_spawns:
		var type : String = str(spawn.type)
		if not enemy_scenes.has(type):
			continue
		var enemy : Node2D = enemy_scenes[type].instantiate()
		enemy.position = Vector2(spawn.pos) * TILE_SIZE
		if enemy.has_method("set_level"):
			enemy.set_level(int(spawn.level))
		enemies_root.add_child(enemy)

# ---------------------------------------------------------------------------
# Player placement
# ---------------------------------------------------------------------------

func _place_player() -> void:
	var start : Vector2i = dungeon_data.start_pos
	player.position = Vector2(start) * TILE_SIZE

# ---------------------------------------------------------------------------
# Minimap
# ---------------------------------------------------------------------------

func _init_minimap() -> void:
	if minimap and minimap.has_method("build_from_data"):
		minimap.build_from_data(dungeon_data)

# ---------------------------------------------------------------------------
# Stair callback — triggered by a trigger area near the stairs tile.
# ---------------------------------------------------------------------------

func on_stairs_entered() -> void:
	GameManager.advance_dungeon_floor()
	SceneManager.go_to_dungeon()

# ---------------------------------------------------------------------------
# Debug helpers
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# F5 in debug builds re-rolls the dungeon immediately.
	if OS.is_debug_build() and event.is_action_pressed("ui_cancel"):
		GameManager.dungeon_seed = randi()
		get_tree().reload_current_scene()
