## ProceduralDungeonGenerator — seeded BSP room placement + corridor carving.
##
## Usage:
##   var gen  := DungeonGenerator.new()
##   var data := gen.generate(seed_value)
##
## `data` is a Dictionary you can serialise to JSON for save/replay:
##   data.seed, data.width, data.height
##   data.grid           — Array of rows; each cell is a TILE_* constant
##   data.rooms          — Array of room Dictionaries
##   data.enemy_spawns   — Array of { pos:Vector2i, type:String, level:int }
##   data.chest_positions — Array of Vector2i
##   data.stairs_pos     — Vector2i  (exit to next floor)
##   data.secret_rooms   — Array of room Dictionaries
##   data.start_pos      — Vector2i  (where the player enters)
class_name DungeonGenerator
extends Node

# ---------------------------------------------------------------------------
# Tile ID constants — must match atlas column indices in your TileSet.
# ---------------------------------------------------------------------------
const TILE_VOID   : int = -1   ## Empty / out-of-bounds.
const TILE_FLOOR  : int =  0   ## Walkable floor.
const TILE_WALL   : int =  1   ## Solid wall.
const TILE_DOOR   : int =  2   ## Openable door chokepoint.
const TILE_CHEST  : int =  3   ## Treasure chest.
const TILE_STAIRS : int =  4   ## Stairs to next floor.

# ---------------------------------------------------------------------------
# Tunables — @export so you can tweak in the Inspector without code changes.
# ---------------------------------------------------------------------------
@export var map_width     : int   = 64
@export var map_height    : int   = 64
@export var min_rooms     : int   = 6
@export var max_rooms     : int   = 14
@export var min_room_size : int   = 4
@export var max_room_size : int   = 10
## Fraction of floor tiles that get an enemy spawn.
@export var enemy_density : float = 0.04
## Probability that any given non-start room contains a chest.
@export var chest_chance  : float = 0.35
## Probability that a room is tagged as secret during placement.
@export var secret_chance : float = 0.12

# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

## Generate and return a complete dungeon Dictionary for `seed_value`.
## The same seed always produces the same dungeon — great for replays.
func generate(seed_value: int) -> Dictionary:
	seed(seed_value)   # deterministic RNG for this dungeon

	var grid  : Array             = _empty_grid()
	var rooms : Array[Dictionary] = []

	_place_rooms(grid, rooms)
	_connect_rooms(grid, rooms)
	_carve_walls(grid)
	_place_doors(grid, rooms)

	var stairs_pos   : Vector2i             = _place_stairs(grid, rooms)
	var enemy_spawns : Array[Dictionary]    = _place_enemies(grid, rooms)
	var chests       : Array[Vector2i]      = _place_chests(grid, rooms)
	var secrets      : Array[Dictionary]    = _collect_secret_rooms(rooms)

	return {
		"seed"            : seed_value,
		"width"           : map_width,
		"height"          : map_height,
		"grid"            : grid,
		"rooms"           : rooms,
		"enemy_spawns"    : enemy_spawns,
		"chest_positions" : chests,
		"stairs_pos"      : stairs_pos,
		"secret_rooms"    : secrets,
		"start_pos"       : _get_start_pos(rooms),
	}

# ---------------------------------------------------------------------------
# Grid helpers
# ---------------------------------------------------------------------------

func _empty_grid() -> Array:
	# We use a plain Array of Arrays (not typed) because the inner rows hold
	# int tile IDs and Godot's typed nested arrays are unwieldy.
	var grid : Array = []
	for _y in map_height:
		var row : Array = []
		row.resize(map_width)
		row.fill(TILE_VOID)
		grid.append(row)
	return grid

func _set(grid: Array, x: int, y: int, tile: int) -> void:
	if x >= 0 and x < map_width and y >= 0 and y < map_height:
		grid[y][x] = tile

func _get(grid: Array, x: int, y: int) -> int:
	if x >= 0 and x < map_width and y >= 0 and y < map_height:
		return int(grid[y][x])
	return TILE_VOID

# ---------------------------------------------------------------------------
# Room placement  (random attempts, reject overlaps + 2-tile buffer)
# ---------------------------------------------------------------------------

func _place_rooms(grid: Array, rooms: Array) -> void:
	var target   : int = randi_range(min_rooms, max_rooms)
	var attempts : int = target * 10   # try hard but don't loop forever

	for _i in attempts:
		if rooms.size() >= target:
			break

		var w    : int    = randi_range(min_room_size, max_room_size)
		var h    : int    = randi_range(min_room_size, max_room_size)
		var x    : int    = randi_range(1, map_width  - w - 1)
		var y    : int    = randi_range(1, map_height - h - 1)
		var rect : Rect2i = Rect2i(x, y, w, h)

		if _room_overlaps(rect, rooms):
			continue

		# Carve the room interior into the grid.
		for ry in h:
			for rx in w:
				_set(grid, x + rx, y + ry, TILE_FLOOR)

		# Tag room type; start and boss are assigned by index, rest are random.
		var room_type : String = "normal"
		if rooms.size() == 0:
			room_type = "start"
		elif rooms.size() == target - 1:
			room_type = "boss"
		elif randf() < secret_chance:
			room_type = "secret"

		rooms.append({
			"rect"      : rect,
			"type"      : room_type,
			"connected" : false,
		})

## Returns true if `rect` (grown by 2 tiles) overlaps any existing room.
func _room_overlaps(rect: Rect2i, rooms: Array) -> bool:
	var padded : Rect2i = rect.grow(2)
	for r in rooms:
		if padded.intersects(r.rect):
			return true
	return false

# ---------------------------------------------------------------------------
# Corridor carving  (MST-style chain + extra random loops)
# ---------------------------------------------------------------------------

func _connect_rooms(grid: Array, rooms: Array) -> void:
	if rooms.size() < 2:
		return

	# Sort rooms left-to-right so corridors travel in a readable direction.
	var sorted : Array = rooms.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.rect.position.x) < int(b.rect.position.x)
	)

	# Chain every adjacent pair — this guarantees full connectivity.
	for i in range(1, sorted.size()):
		_carve_corridor(grid,
			_room_center(sorted[i - 1]),
			_room_center(sorted[i]))
		var r : Dictionary = sorted[i]
		r.connected = true

	# Add a few random extra tunnels to create loops and more interesting maps.
	var extra : int = randi_range(1, max(1, rooms.size() / 3))
	for _e in extra:
		var ia : int = randi() % rooms.size()
		var ib : int = randi() % rooms.size()
		if ia != ib:
			_carve_corridor(grid,
				_room_center(rooms[ia]),
				_room_center(rooms[ib]))

func _room_center(room: Dictionary) -> Vector2i:
	var r : Rect2i = room.rect
	return Vector2i(
		r.position.x + r.size.x / 2,
		r.position.y + r.size.y / 2
	)

## L-shaped corridor: 50% chance to go horizontal-first vs vertical-first.
## This creates the classic dungeon-crawler tunnel variety.
func _carve_corridor(grid: Array, a: Vector2i, b: Vector2i) -> void:
	if randf() > 0.5:
		_carve_h_tunnel(grid, a.x, b.x, a.y)
		_carve_v_tunnel(grid, a.y, b.y, b.x)
	else:
		_carve_v_tunnel(grid, a.y, b.y, a.x)
		_carve_h_tunnel(grid, a.x, b.x, b.y)

func _carve_h_tunnel(grid: Array, x1: int, x2: int, y: int) -> void:
	var lo : int = min(x1, x2)
	var hi : int = max(x1, x2)
	for x in range(lo, hi + 1):
		_set(grid, x, y, TILE_FLOOR)

func _carve_v_tunnel(grid: Array, y1: int, y2: int, x: int) -> void:
	var lo : int = min(y1, y2)
	var hi : int = max(y1, y2)
	for y in range(lo, hi + 1):
		_set(grid, x, y, TILE_FLOOR)

# ---------------------------------------------------------------------------
# Wall pass  (surround every floor tile that touches void)
# ---------------------------------------------------------------------------

func _carve_walls(grid: Array) -> void:
	# Collect positions first so we don't mutate while iterating.
	var to_wall : Array[Vector2i] = []
	for y in map_height:
		for x in map_width:
			if _get(grid, x, y) != TILE_VOID:
				continue
			# If any of the 8 neighbours is a floor tile, this void becomes wall.
			var should_wall : bool = false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if _get(grid, x + dx, y + dy) == TILE_FLOOR:
						should_wall = true
						break
				if should_wall:
					break
			if should_wall:
				to_wall.append(Vector2i(x, y))

	for pos in to_wall:
		_set(grid, pos.x, pos.y, TILE_WALL)

# ---------------------------------------------------------------------------
# Doors  (placed at single-tile chokepoints between room and corridor)
# ---------------------------------------------------------------------------

func _place_doors(grid: Array, rooms: Array) -> void:
	for room in rooms:
		var r : Rect2i = room.rect
		# Check the four cardinal midpoints just outside the room boundary.
		var candidates : Array[Vector2i] = [
			Vector2i(r.position.x - 1,          r.position.y + r.size.y / 2),
			Vector2i(r.position.x + r.size.x,   r.position.y + r.size.y / 2),
			Vector2i(r.position.x + r.size.x / 2, r.position.y - 1),
			Vector2i(r.position.x + r.size.x / 2, r.position.y + r.size.y),
		]
		for pos in candidates:
			_try_place_door(grid, pos.x, pos.y)

## A door is only placed if the tile is a floor AND is flanked by two walls
## on opposite sides — i.e. it truly is a chokepoint.
func _try_place_door(grid: Array, x: int, y: int) -> void:
	if _get(grid, x, y) != TILE_FLOOR:
		return
	var h_wall : bool = (
		_get(grid, x - 1, y) == TILE_WALL and
		_get(grid, x + 1, y) == TILE_WALL
	)
	var v_wall : bool = (
		_get(grid, x, y - 1) == TILE_WALL and
		_get(grid, x, y + 1) == TILE_WALL
	)
	if h_wall or v_wall:
		_set(grid, x, y, TILE_DOOR)

# ---------------------------------------------------------------------------
# Stairs  (placed in the boss/last room)
# ---------------------------------------------------------------------------

func _place_stairs(grid: Array, rooms: Array) -> Vector2i:
	var boss : Dictionary = {}
	for r in rooms:
		if r.type == "boss":
			boss = r
			break
	if boss.is_empty() and rooms.size() > 0:
		boss = rooms.back()
	if boss.is_empty():
		return Vector2i(map_width / 2, map_height / 2)
	var c : Vector2i = _room_center(boss)
	_set(grid, c.x, c.y, TILE_STAIRS)
	return c

# ---------------------------------------------------------------------------
# Enemy spawns
# ---------------------------------------------------------------------------

func _place_enemies(grid: Array, rooms: Array) -> Array[Dictionary]:
	var spawns : Array[Dictionary] = []
	var types  : Array[String]     = ["slime", "bat", "skeleton", "goblin", "ghost"]

	for room in rooms:
		# Never spawn enemies in the start room or secret rooms.
		if room.type == "start" or room.type == "secret":
			continue

		var r     : Rect2i = room.rect
		var area  : int    = r.size.x * r.size.y
		var count : int    = int(float(area) * enemy_density)

		# Boss rooms get extra enemies to make the encounter feel weighty.
		if room.type == "boss":
			count = max(3, count * 2)

		for _i in count:
			var ex : int = randi_range(r.position.x + 1, r.position.x + r.size.x - 2)
			var ey : int = randi_range(r.position.y + 1, r.position.y + r.size.y - 2)
			if _get(grid, ex, ey) == TILE_FLOOR:
				spawns.append({
					"pos"   : Vector2i(ex, ey),
					"type"  : types[randi() % types.size()],
					"level" : 1 + randi() % 3,
				})

	return spawns

# ---------------------------------------------------------------------------
# Chests
# ---------------------------------------------------------------------------

func _place_chests(grid: Array, rooms: Array) -> Array[Vector2i]:
	var chests : Array[Vector2i] = []
	for room in rooms:
		if room.type == "start":
			continue
		if randf() >= chest_chance:
			continue
		var r  : Rect2i = room.rect
		var cx : int = randi_range(r.position.x + 1, r.position.x + r.size.x - 2)
		var cy : int = randi_range(r.position.y + 1, r.position.y + r.size.y - 2)
		if _get(grid, cx, cy) == TILE_FLOOR:
			_set(grid, cx, cy, TILE_CHEST)
			chests.append(Vector2i(cx, cy))
	return chests

# ---------------------------------------------------------------------------
# Secret rooms  (already tagged at placement — just collect them)
# ---------------------------------------------------------------------------

func _collect_secret_rooms(rooms: Array) -> Array[Dictionary]:
	var secrets : Array[Dictionary] = []
	for r in rooms:
		if r.type == "secret":
			secrets.append(r)
	return secrets

# ---------------------------------------------------------------------------
# Start position
# ---------------------------------------------------------------------------

func _get_start_pos(rooms: Array) -> Vector2i:
	for r in rooms:
		if r.type == "start":
			return _room_center(r)
	if rooms.size() > 0:
		return _room_center(rooms[0])
	return Vector2i(map_width / 2, map_height / 2)
