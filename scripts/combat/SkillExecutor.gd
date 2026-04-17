## SkillExecutor — resolves a single skill use and returns a result Dictionary.
##
## All damage/healing math lives here so CombatController stays readable.
## Call SkillExecutor.execute(skill, user, targets, all_enemies, all_party)
## and it returns a list of CombatEvent Dictionaries.
##
## CombatEvent schema:
##   { type, target_id, target_name, value, crit, miss, status_applied, message }
##   type: "damage" | "heal" | "status" | "steal" | "miss" | "info"
class_name SkillExecutor
extends RefCounted

# ---------------------------------------------------------------------------
# Skill database (loaded once at first use)
# ---------------------------------------------------------------------------
static var _skill_db  : Array[Dictionary] = []
static var _db_loaded : bool              = false

static func _load_db() -> void:
	if _db_loaded:
		return
	var file : FileAccess = FileAccess.open("res://data/skills/skills.json", FileAccess.READ)
	if not file:
		push_error("SkillExecutor: cannot open skills.json")
		return
	var result : Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if result is Array:
		for entry in result:
			_skill_db.append(entry)
	_db_loaded = true

static func get_skill(skill_id: String) -> Dictionary:
	_load_db()
	for s in _skill_db:
		if s.id == skill_id:
			return s
	return {}

static func get_skills_for(character_id: String) -> Array[Dictionary]:
	_load_db()
	var result : Array[Dictionary] = []
	# Look up the party member's skill list from PartyManager.
	var member : Dictionary = PartyManager.get_member(character_id)
	if member.is_empty():
		return result
	for sid in member.get("skills", []):
		var s : Dictionary = get_skill(sid)
		if not s.is_empty():
			result.append(s)
	return result

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

## Execute `skill` used by `user` (a party/enemy Dictionary) against `targets`.
## Returns an Array of CombatEvent Dictionaries.
static func execute(
		skill      : Dictionary,
		user       : Dictionary,
		targets    : Array[Dictionary],
		all_enemies: Array[Dictionary],
		all_party  : Array[Dictionary]
) -> Array[Dictionary]:

	_load_db()
	var events : Array[Dictionary] = []

	var stype : String = str(skill.get("type", "physical"))

	match stype:
		"physical":  events = _do_attack(skill, user, targets)
		"magic":     events = _do_magic(skill, user, targets)
		"healing":   events = _do_heal(skill, user, targets)
		"status":    events = _do_status(skill, user, targets)
		"special":   events = _do_special(skill, user, targets, all_party)
		_:
			events.append(_info_event("Nothing happened."))

	return events

# ---------------------------------------------------------------------------
# Attack helpers
# ---------------------------------------------------------------------------

static func _do_attack(skill: Dictionary, user: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	var events : Array[Dictionary] = []
	var hits   : int               = int(skill.get("hits", 1))

	for target in targets:
		for _h in hits:
			if _miss_check(skill, user, target):
				events.append(_miss_event(target))
				continue
			var crit  : bool = _crit_check(skill, user)
			var dmg   : int  = _calc_physical_dmg(skill, user, target, crit)
			events.append(_damage_event(target, dmg, crit))

	return events

static func _do_magic(skill: Dictionary, user: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	var events : Array[Dictionary] = []

	for target in targets:
		if _miss_check(skill, user, target):
			events.append(_miss_event(target))
			continue
		var dmg   : int  = _calc_magic_dmg(skill, user, target)
		var crit  : bool = false
		events.append(_damage_event(target, dmg, crit))

		# Chance to apply a status effect.
		var eff : String = str(skill.get("status_effect", ""))
		var pct : int    = int(skill.get("status_chance", 0))
		if eff != "" and pct > 0 and randi() % 100 < pct:
			events.append(_status_event(target, eff))

	return events

static func _do_heal(skill: Dictionary, user: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	var events  : Array[Dictionary] = []
	var int_stat: int               = int(user.stats.get("int", 5))
	var power   : int               = int(skill.get("power", 20))
	# Healing scales with INT and has mild random variance (±10 %).
	var amount  : int               = int((power + int_stat * 1.5) * randf_range(0.9, 1.1))

	for target in targets:
		events.append({
			"type"           : "heal",
			"target_id"      : str(target.id),
			"target_name"    : str(target.name),
			"value"          : amount,
			"crit"           : false,
			"miss"           : false,
			"status_applied" : "",
			"message"        : "%s recovers %d HP!" % [target.name, amount],
		})

	return events

static func _do_status(skill: Dictionary, user: Dictionary, targets: Array[Dictionary]) -> Array[Dictionary]:
	var events : Array[Dictionary] = []
	var eff    : String            = str(skill.get("status_effect", ""))

	for target in targets:
		events.append(_status_event(target, eff))
		var msg : String = ""
		match eff:
			"defending": msg = "%s takes a defensive stance!" % str(user.name)
			"atk_up":    msg = "%s's attack rises!" % str(target.name)
			_:           msg = "%s is afflicted with %s!" % [str(target.name), eff]
		events.append(_info_event(msg))

	return events

static func _do_special(skill: Dictionary, user: Dictionary, targets: Array[Dictionary], all_party: Array[Dictionary]) -> Array[Dictionary]:
	var events : Array[Dictionary] = []
	# Only "steal" is currently a special type.
	if str(skill.id) == "steal":
		for target in targets:
			var lck    : int   = int(user.stats.get("lck", 5))
			var chance : float = float(skill.get("hit_rate", 70)) / 100.0 + lck * 0.01
			if randf() < chance:
				var stolen : String = str(target.get("steal_item", ""))
				if stolen != "":
					GameManager.add_item({ "id": stolen, "name": stolen.capitalize(), "qty": 1, "type": "consumable" })
					events.append(_info_event("Slink steals a %s!" % stolen.capitalize()))
				else:
					events.append(_info_event("Nothing to steal!"))
			else:
				events.append(_info_event("Steal failed!"))
	return events

# ---------------------------------------------------------------------------
# Damage formulas
# ---------------------------------------------------------------------------

static func _calc_physical_dmg(skill: Dictionary, user: Dictionary, target: Dictionary, crit: bool) -> int:
	var power   : int   = int(skill.get("power", 10))
	var scaling : String= str(skill.get("stat_scaling", "str"))
	var atk_stat: int   = int(user.stats.get(scaling, int(user.stats.get("str", 5))))
	var def_stat: int   = int(target.stats.get("def", 2))

	# Variance of ±15 % keeps combat from feeling mechanical.
	var base : float = float(power + atk_stat * 2 - def_stat) * randf_range(0.85, 1.15)
	var dmg  : int   = max(1, int(base))

	if crit:
		dmg = int(dmg * 1.5)

	# Status modifiers.
	var uid : String = str(user.get("id", ""))
	if uid != "" and PartyManager.has_status(uid, "atk_up"):
		dmg = int(dmg * 1.3)

	return dmg

static func _calc_magic_dmg(skill: Dictionary, user: Dictionary, target: Dictionary) -> int:
	var power    : int    = int(skill.get("power", 14))
	var int_stat : int    = int(user.stats.get("int", 5))
	var element  : String = str(skill.get("element", "none"))

	var base : float = float(power + int_stat * 2) * randf_range(0.88, 1.12)
	var dmg  : int   = max(1, int(base))

	# Elemental weakness doubles damage; resistance halves it.
	var weaknesses  : Array = target.get("weaknesses",  [])
	var resistances : Array = target.get("resistances", [])
	if element != "none" and element in weaknesses:
		dmg = int(dmg * 2.0)
	elif element != "none" and element in resistances:
		dmg = int(dmg * 0.5)

	return dmg

# ---------------------------------------------------------------------------
# Hit / crit checks
# ---------------------------------------------------------------------------

static func _miss_check(skill: Dictionary, user: Dictionary, _target: Dictionary) -> bool:
	var hit_rate : int = int(skill.get("hit_rate", 90))
	# AGI adds a small bonus to hit rate.
	var agi_bonus: int = int(user.stats.get("agi", 5)) / 5
	return randi() % 100 >= (hit_rate + agi_bonus)

static func _crit_check(skill: Dictionary, _user: Dictionary) -> bool:
	var base_crit : int = 5  ## 5 % base critical hit rate.
	var crit_bonus: int = int(skill.get("crit_bonus", 0))
	return randi() % 100 < (base_crit + crit_bonus)

# ---------------------------------------------------------------------------
# Event constructors
# ---------------------------------------------------------------------------

static func _damage_event(target: Dictionary, value: int, crit: bool) -> Dictionary:
	var suffix : String = " Critical hit!" if crit else "!"
	return {
		"type"           : "damage",
		"target_id"      : str(target.id),
		"target_name"    : str(target.name),
		"value"          : value,
		"crit"           : crit,
		"miss"           : false,
		"status_applied" : "",
		"message"        : "%s takes [color=yellow]%d[/color] damage%s" % [target.name, value, suffix],
	}

static func _heal_event(target: Dictionary, value: int) -> Dictionary:
	return {
		"type"           : "heal",
		"target_id"      : str(target.id),
		"target_name"    : str(target.name),
		"value"          : value,
		"crit"           : false,
		"miss"           : false,
		"status_applied" : "",
		"message"        : "%s recovers [color=lime]%d[/color] HP!" % [target.name, value],
	}

static func _miss_event(target: Dictionary) -> Dictionary:
	return {
		"type"           : "miss",
		"target_id"      : str(target.id),
		"target_name"    : str(target.name),
		"value"          : 0,
		"crit"           : false,
		"miss"           : true,
		"status_applied" : "",
		"message"        : "Missed %s!" % str(target.name),
	}

static func _status_event(target: Dictionary, effect: String) -> Dictionary:
	return {
		"type"           : "status",
		"target_id"      : str(target.id),
		"target_name"    : str(target.name),
		"value"          : 0,
		"crit"           : false,
		"miss"           : false,
		"status_applied" : effect,
		"message"        : "%s is %s!" % [str(target.name), effect],
	}

static func _info_event(msg: String) -> Dictionary:
	return {
		"type"           : "info",
		"target_id"      : "",
		"target_name"    : "",
		"value"          : 0,
		"crit"           : false,
		"miss"           : false,
		"status_applied" : "",
		"message"        : msg,
	}
