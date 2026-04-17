extends Node

# ── Signals ───────────────────────────────────────────────────────────────────
signal party_changed
signal member_leveled_up(member: Dictionary)
signal member_died(member: Dictionary)

# ── Constants ─────────────────────────────────────────────────────────────────
const MAX_PARTY_SIZE := 4
const BASE_EXP_CURVE := 100  # exp needed for level 2; scales quadratically

# ── State ─────────────────────────────────────────────────────────────────────
var party: Array[Dictionary] = []

# ── Default templates ─────────────────────────────────────────────────────────
const CHARACTER_TEMPLATES := {
	"hero": {
		"id": "hero", "name": "Brochacho", "class": "Warrior",
		"level": 1, "exp": 0,
		"hp": 30, "max_hp": 30, "mp": 10, "max_mp": 10,
		"stats": { "str": 10, "agi": 8, "int": 5, "def": 8, "lck": 6 },
		"skills": ["attack", "defend"],
		"equipment": { "weapon": "", "armor": "", "accessory": "" },
		"status": [],
		"portrait": "res://assets/sprites/player/hero_portrait.png",
		"sprite": "res://assets/sprites/player/hero.png",
	},
	"mage": {
		"id": "mage", "name": "Zara", "class": "Mage",
		"level": 1, "exp": 0,
		"hp": 18, "max_hp": 18, "mp": 30, "max_mp": 30,
		"stats": { "str": 4, "agi": 9, "int": 15, "def": 4, "lck": 8 },
		"skills": ["attack", "fire", "ice"],
		"equipment": { "weapon": "", "armor": "", "accessory": "" },
		"status": [],
		"portrait": "res://assets/sprites/player/mage_portrait.png",
		"sprite": "res://assets/sprites/player/mage.png",
	},
	"rogue": {
		"id": "rogue", "name": "Slink", "class": "Rogue",
		"level": 1, "exp": 0,
		"hp": 22, "max_hp": 22, "mp": 14, "max_mp": 14,
		"stats": { "str": 8, "agi": 14, "int": 6, "def": 5, "lck": 12 },
		"skills": ["attack", "steal", "back_stab"],
		"equipment": { "weapon": "", "armor": "", "accessory": "" },
		"status": [],
		"portrait": "res://assets/sprites/player/rogue_portrait.png",
		"sprite": "res://assets/sprites/player/rogue.png",
	},
}

# ── Init ──────────────────────────────────────────────────────────────────────
func init_default_party() -> void:
	party.clear()
	party.append(CHARACTER_TEMPLATES["hero"].duplicate(true))
	emit_signal("party_changed")

func add_member(character_id: String) -> bool:
	if party.size() >= MAX_PARTY_SIZE:
		return false
	if CHARACTER_TEMPLATES.has(character_id):
		party.append(CHARACTER_TEMPLATES[character_id].duplicate(true))
		emit_signal("party_changed")
		return true
	return false

func remove_member(character_id: String) -> void:
	for i in party.size():
		if party[i].id == character_id:
			party.remove_at(i)
			emit_signal("party_changed")
			return

func get_member(character_id: String) -> Dictionary:
	for m in party:
		if m.id == character_id:
			return m
	return {}

func get_leader() -> Dictionary:
	return party[0] if party.size() > 0 else {}

# ── HP / MP ───────────────────────────────────────────────────────────────────
func heal_member(character_id: String, amount: int) -> void:
	var m := get_member(character_id)
	if m.is_empty():
		return
	m.hp = min(m.hp + amount, m.max_hp)

func damage_member(character_id: String, amount: int) -> void:
	var m := get_member(character_id)
	if m.is_empty():
		return
	m.hp = max(m.hp - amount, 0)
	if m.hp == 0:
		emit_signal("member_died", m)

func restore_mp(character_id: String, amount: int) -> void:
	var m := get_member(character_id)
	if m.is_empty():
		return
	m.mp = min(m.mp + amount, m.max_mp)

func full_heal_all() -> void:
	for m in party:
		m.hp = m.max_hp
		m.mp = m.max_mp
		m.status = []

func is_party_wiped() -> bool:
	for m in party:
		if m.hp > 0:
			return false
	return true

# ── Experience / Level ────────────────────────────────────────────────────────
func give_exp(amount: int) -> void:
	for m in party:
		if m.hp <= 0:
			continue
		m.exp += amount
		while m.exp >= exp_for_next_level(m.level):
			m.exp -= exp_for_next_level(m.level)
			_level_up(m)

func exp_for_next_level(level: int) -> int:
	return int(BASE_EXP_CURVE * pow(level, 1.8))

func _level_up(m: Dictionary) -> void:
	m.level += 1
	m.max_hp  += randi_range(3, 6)
	m.max_mp  += randi_range(1, 4)
	m.hp       = m.max_hp
	m.mp       = m.max_mp
	m.stats.str += randi_range(0, 2)
	m.stats.agi += randi_range(0, 2)
	m.stats.int += randi_range(0, 2)
	m.stats.def += randi_range(0, 2)
	emit_signal("member_leveled_up", m)

# ── Status Effects ────────────────────────────────────────────────────────────
func add_status(character_id: String, status: String) -> void:
	var m := get_member(character_id)
	if not m.is_empty() and status not in m.status:
		m.status.append(status)

func remove_status(character_id: String, status: String) -> void:
	var m := get_member(character_id)
	if not m.is_empty():
		m.status.erase(status)

func has_status(character_id: String, status: String) -> bool:
	var m := get_member(character_id)
	return false if m.is_empty() else status in m.status

# ── Serialization ─────────────────────────────────────────────────────────────
func serialize() -> Dictionary:
	return { "party": party.duplicate(true) }

func deserialize(data: Dictionary) -> void:
	party.clear()
	for m in data.get("party", []):
		party.append(m)
	emit_signal("party_changed")
