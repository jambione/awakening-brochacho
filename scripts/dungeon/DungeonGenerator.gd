extends Node
class_name DungeonGenerator

# ── Tile IDs (match your TileSet) ─────────────────────────────────────────────
const TILE_FLOOR   := 0
const TILE_WALL    := 1
const TILE_DOOR    := 2
const TILE_CHEST   := 3
const TILE_STAIRS  := 4
const TILE_VOID    := -1

# ── Generation params ─────────────────────────────────────────────────────────
@export var map_width:      int   = 60
@export var map_height:     int   = 60
@export var min_rooms:      int   = 6
@export var max_rooms:      int   = 14
@export var min_room_size:  int   = 4
@export var max_room_size:  int   = 10
@export var enemy_density:  float = 0.04   # fraction of floor tiles that spawn enemies
@export var chest_chance:   float = 0.3    # per room
@export var secret_chance:  float = 0.15   # per room

# ── Data classes (using Dictionaries for easy serialization) ──────────────────
# Room: { rect: Rect2i, connected: bool, type: String }
# DungeonData: { grid, rooms, corridors, enemy_spawns, chest_positions, stairs_pos, secret_rooms }

# ── Public entry point ────────────────────────────────────────────────────────
func generate(seed_value: int) -> Dictionary:
	seed(seed_value)

	var grid := _empty_grid()
	var rooms: Array[Dictionary] = []

	_place_rooms(grid, rooms)
	_connect_rooms(grid, rooms)
	_carve_walls(grid)
	_place_doors(grid, rooms)

	var stairs_pos  := _place_stairs(grid, rooms)
	var enemy_spawns := _place_enemies(grid, rooms)
	var chests       := _place_chests(grid, rooms)
	var secrets      := _find_secret_rooms(rooms)

	return {
		"seed":          seed_value,
		"width":         map_width,
		"height":        map_height,
		"grid":          grid,
		"rooms":         rooms,
		"enemy_spawns":  enemy_spawns,
		"chest_positions": chests,
		"stairs_pos":    stairs_pos,
		"secret_rooms":  secrets,
		"start_pos":     _get_start_pos(rooms),
	}

# ── Grid init ─────────────────────────────────────────────────────────────────
func _empty_grid() -> Array:
	var grid := []
	for y in map_height:
		var row := []
		for x in map_width:
			row.append(TILE_VOID)
		grid.append(row)
	return grid

func _set(grid: Array, x: int, y: int, tile: int) -> void:
	if x >= 0 and x < map_width and y >= 0 and y < map_height:
		grid[y][x] = tile

func _get(grid: Array, x: int, y: int) -> int:
	if x >= 0 and x < map_width and y >= 0 and y < map_height:
		return grid[y][x]
	return TILE_VOID

# ── Room placement (BSP-lite: random attempts, reject overlaps) ───────────────
func _place_rooms(grid: Array, rooms: Array) -> void:
	var attempts := max_rooms * 8
	var target   := randi_range(min_rooms, max_rooms)

	for _i in attempts:
		if rooms.size() >= target:
			break

		var w     := randi_range(min_room_size, max_room_size)
		var h     := randi_range(min_room_size, max_room_size)
		var x     := randi_range(1, map_width  - w - 1)
		var y     := randi_range(1, map_height - h - 1)
		var rect  := Rect2i(x, y, w, h)

		if _room_overlaps(rect, rooms):
			continue

		# Carve floor
		for ry in h:
			for rx in w:
				_set(grid, x + rx, y + ry, TILE_FLOOR)

		var room_type := "normal"
		if rooms.size() == 0:
			room_type = "start"
		elif randf() < secret_chance:
			room_type = "secret"
		elif rooms.size() == target - 1:
			room_type = "boss"

		rooms.append({ "rect": rect, "type": room_type, "connected": false })

func _room_overlaps(rect: Rect2i, rooms: Array) -> bool:
	var expanded := rect.grow(2)  # 2-tile buffer between rooms
	for r in rooms:
		if expanded.intersects(r.rect):
			return true
	return false

# ── Corridor carving (L-shaped tunnels, MST-like connection) ──────────────────
func _connect_rooms(grid: Array, rooms: Array) -> void:
	if rooms.size() < 2:
		return

	# Sort by x so tunnels are somewhat ordered
	var sorted := rooms.duplicate()
	sorted.sort_custom(func(a, b): return a.rect.position.x < b.rect.position.x)

	for i in range(1, sorted.size()):
		var a_center := _room_center(sorted[i - 1])
		var b_center := _room_center(sorted[i])
		_carve_corridor(grid, a_center, b_center)
		sorted[i].connected = true

	# Extra random connections for loops (more interesting exploration)
	var extra := randi_range(1, max(1, rooms.size() / 3))
	for _e in extra:
		var ia := randi() % rooms.size()
		var ib := randi() % rooms.size()
		if ia != ib:
			_carve_corridor(grid, _room_center(rooms[ia]), _room_center(rooms[ib]))

func _room_center(room: Dictionary) -> Vector2i:
	var r: Rect2i = room.rect
	return Vector2i(r.position.x + r.size.x / 2, r.position.y + r.size.y / 2)

func _carve_corridor(grid: Array, a: Vector2i, b: Vector2i) -> void:
	# Always L-shaped: horizontal then vertical (or vice versa, 50/50)
	var mid_x: int
	var mid_y: int

	if randf() > 0.5:
		# Horizontal first
		mid_x = b.x
		mid_y = a.y
	else:
		# Vertical first
		mid_x = a.x
		mid_y = b.y

	_carve_h_tunnel(grid, a.x, mid_x, a.y)
	_carve_v_tunnel(grid, a.y, mid_y, a.x)
	_carve_h_tunnel(grid, mid_x, b.x, mid_y)
	_carve_v_tunnel(grid, mid_y, b.y, b.x)

func _carve_h_tunnel(grid: Array, x1: int, x2: int, y: int) -> void:
	var lo := min(x1, x2)
	var hi := max(x1, x2)
	for x in range(lo, hi + 1):
		_set(grid, x, y, TILE_FLOOR)

func _carve_v_tunnel(grid: Array, y1: int, y2: int, x: int) -> void:
	var lo := min(y1, y2)
	var hi := max(y1, y2)
	for y in range(lo, hi + 1):
		_set(grid, x, y, TILE_FLOOR)

# ── Wall pass: surround every floor tile adjacent to void ─────────────────────
func _carve_walls(grid: Array) -> void:
	var to_wall: Array[Vector2i] = []
	for y in map_height:
		for x in map_width:
			if _get(grid, x, y) == TILE_VOID:
				# Check 8 neighbors
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if _get(grid, x + dx, y + dy) == TILE_FLOOR:
							to_wall.append(Vector2i(x, y))
							break
	for pos in to_wall:
		_set(grid, pos.x, pos.y, TILE_WALL)

# ── Doors: place at room entrances (adjacent floor/wall transitions) ───────────
func _place_doors(grid: Array, rooms: Array) -> void:
	# Simple heuristic: walk the perimeter of each room, find narrow passages
	for room in rooms:
		var r: Rect2i = room.rect
		_check_door_at(grid, r.position.x - 1,          r.position.y + r.size.y / 2)
		_check_door_at(grid, r.position.x + r.size.x,   r.position.y + r.size.y / 2)
		_check_door_at(grid, r.position.x + r.size.x / 2, r.position.y - 1)
		_check_door_at(grid, r.position.x + r.size.x / 2, r.position.y + r.size.y)

func _check_door_at(grid: Array, x: int, y: int) -> void:
	if _get(grid, x, y) == TILE_FLOOR:
		# Only place door if it's a chokepoint (wall on two opposite sides)
		var h_wall := _get(grid, x - 1, y) == TILE_WALL and _get(grid, x + 1, y) == TILE_WALL
		var v_wall := _get(grid, x, y - 1) == TILE_WALL and _get(grid, x, y + 1) == TILE_WALL
		if h_wall or v_wall:
			_set(grid, x, y, TILE_DOOR)

# ── Stairs: placed in boss room (last room) ────────────────────────────────────
func _place_stairs(grid: Array, rooms: Array) -> Vector2i:
	var boss: Dictionary = {}
	for r in rooms:
		if r.type == "boss":
			boss = r
			break
	if boss.is_empty() and rooms.size() > 0:
		boss = rooms.back()
	if boss.is_empty():
		return Vector2i(map_width / 2, map_height / 2)

	var c := _room_center(boss)
	_set(grid, c.x, c.y, TILE_STAIRS)
	return c

# ── Enemy spawns ──────────────────────────────────────────────────────────────
func _place_enemies(grid: Array, rooms: Array) -> Array[Dictionary]:
	var spawns: Array[Dictionary] = []
	var enemy_types := ["slime", "bat", "skeleton", "goblin", "ghost"]

	for room in rooms:
		if room.type in ["start", "secret"]:
			continue
		var r: Rect2i = room.rect
		var area := r.size.x * r.size.y
		var count := int(area * enemy_density)
		if room.type == "boss":
			count = max(3, count * 2)

		for _i in count:
			var ex := randi_range(r.position.x + 1, r.position.x + r.size.x - 2)
			var ey := randi_range(r.position.y + 1, r.position.y + r.size.y - 2)
			if _get(grid, ex, ey) == TILE_FLOOR:
				spawns.append({
					"pos":   Vector2i(ex, ey),
					"type":  enemy_types[randi() % enemy_types.size()],
					"level": 1 + int(randf() * 3),
				})
	return spawns

# ── Chests ────────────────────────────────────────────────────────────────────
func _place_chests(grid: Array, rooms: Array) -> Array[Vector2i]:
	var chests: Array[Vector2i] = []
	for room in rooms:
		if room.type == "start":
			continue
		if randf() < chest_chance:
			var r: Rect2i = room.rect
			var cx := randi_range(r.position.x + 1, r.position.x + r.size.x - 2)
			var cy := randi_range(r.position.y + 1, r.position.y + r.size.y - 2)
			_set(grid, cx, cy, TILE_CHEST)
			chests.append(Vector2i(cx, cy))
	return chests

# ── Secret rooms (already tagged at placement) ─────────────────────────────────
func _find_secret_rooms(rooms: Array) -> Array[Dictionary]:
	var secrets: Array[Dictionary] = []
	for r in rooms:
		if r.type == "secret":
			secrets.append(r)
	return secrets

# ── Start position ────────────────────────────────────────────────────────────
func _get_start_pos(rooms: Array) -> Vector2i:
	for r in rooms:
		if r.type == "start":
			return _room_center(r)
	if rooms.size() > 0:
		return _room_center(rooms[0])
	return Vector2i(map_width / 2, map_height / 2)
