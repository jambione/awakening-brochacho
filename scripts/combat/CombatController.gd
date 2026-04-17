## CombatController — turn-based party combat with full skill system.
##
## Flow per round:
##   1. PLAYER_INPUT  — player queues an action for each alive member.
##   2. RESOLVE       — player actions execute in party order.
##   3. ENEMY_TURN    — each living enemy picks and executes a skill.
##   4. STATUS_TICK   — status effects tick (poison damage, buff expiry, etc.)
##   5. CHECK_END     — victory / defeat / repeat.
##
## Enemy groups are passed via SceneManager.go_to_combat(enemy_group).
## If none are present a test Slime encounter is used for development.
extends Node2D

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal combat_ended(result: String)   ## "victory" | "defeat" | "fled"

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var action_menu  : VBoxContainer  = $UI/ActionMenu
@onready var skill_menu   : VBoxContainer  = $UI/SkillMenu
@onready var item_menu    : VBoxContainer  = $UI/ItemMenu
@onready var target_menu  : VBoxContainer  = $UI/TargetMenu
@onready var battle_log   : RichTextLabel  = $UI/BattleLog
@onready var enemy_row    : HBoxContainer  = $EnemyRow
@onready var party_row    : HBoxContainer  = $PartyRow
@onready var member_label : Label          = $UI/MemberLabel

# ---------------------------------------------------------------------------
# Combat state
# ---------------------------------------------------------------------------
enum Phase { PLAYER_INPUT, RESOLVE, ENEMY_TURN, STATUS_TICK, RESULT }

var phase             : Phase             = Phase.PLAYER_INPUT
var enemies           : Array[Dictionary] = []
var active_idx        : int               = 0   ## Index into PartyManager.party
var selected_enemy    : int               = 0
var selected_ally     : int               = 0
var queued_actions    : Array[Dictionary] = []   ## { member_id, skill_id, targets }

# Enemy stat Dictionaries loaded from enemies.json for this encounter.
var enemy_db          : Dictionary        = {}   ## id → Dictionary

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_load_enemy_db()

	# Receive enemy group from SceneManager, or fall back to a test encounter.
	if get_tree().has_meta("combat_enemies"):
		var raw : Variant = get_tree().get_meta("combat_enemies")
		if raw is Array:
			for e in raw:
				enemies.append(e)
	if enemies.is_empty():
		enemies.append(_make_encounter("slime"))

	_build_enemy_ui()
	_build_party_ui()
	_wire_buttons()
	_start_round()
	AudioManager.play_music("res://assets/audio/music/battle_theme.ogg")

# ---------------------------------------------------------------------------
# Enemy database
# ---------------------------------------------------------------------------

func _load_enemy_db() -> void:
	var file : FileAccess = FileAccess.open("res://data/enemies/enemies.json", FileAccess.READ)
	if not file:
		return
	var result : Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if result is Array:
		for entry in result:
			enemy_db[str(entry.id)] = entry

## Create a fresh enemy instance from the DB, scaled to `level`.
func _make_encounter(enemy_id: String, level: int = 1) -> Dictionary:
	var template : Dictionary = enemy_db.get(enemy_id, {})
	if template.is_empty():
		return {
			"id": enemy_id, "name": enemy_id.capitalize(), "level": level,
			"hp": 12, "max_hp": 12, "mp": 0, "max_mp": 0,
			"stats": {"str":4,"agi":3,"int":1,"def":2,"lck":3},
			"skills": ["attack"], "weaknesses": [], "resistances": [],
			"exp_reward": 10, "gold_reward": 5, "status": [],
			"steal_item": "", "drop_item": "", "drop_rate": 0.0,
			"ai": "basic_attack",
		}
	var e : Dictionary = template.duplicate(true)
	# Scale HP and stats up by 15 % per level above the base level.
	var scale : float = 1.0 + 0.15 * max(0, level - int(e.get("level", 1)))
	e.hp     = int(int(e.hp)     * scale)
	e.max_hp = e.hp
	e.level  = level
	e["status"] = []
	if not e.has("max_mp"):
		e["max_mp"] = e.get("mp", 0)
	return e

# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_enemy_ui() -> void:
	for child in enemy_row.get_children():
		child.queue_free()
	for i in enemies.size():
		var e   : Dictionary = enemies[i]
		var lbl : Label      = Label.new()
		lbl.text         = "%s\nHP %d/%d" % [e.name, e.hp, e.max_hp]
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		lbl.gui_input.connect(_on_enemy_clicked.bind(i))
		enemy_row.add_child(lbl)

func _build_party_ui() -> void:
	for child in party_row.get_children():
		child.queue_free()
	for m in PartyManager.party:
		var lbl : Label = Label.new()
		lbl.text = "%s  HP %d/%d  MP %d/%d" % [m.name, m.hp, m.max_hp, m.mp, m.max_mp]
		if m.hp <= 0:
			lbl.modulate = Color(0.5, 0.5, 0.5)
		party_row.add_child(lbl)

func _wire_buttons() -> void:
	$UI/ActionMenu/Attack.pressed.connect(_pick_attack)
	$UI/ActionMenu/Magic.pressed.connect(_open_skill_menu)
	$UI/ActionMenu/Item.pressed.connect(_open_item_menu)
	$UI/ActionMenu/Defend.pressed.connect(_pick_defend)
	$UI/ActionMenu/Flee.pressed.connect(_pick_flee)

func _update_member_label() -> void:
	if active_idx < PartyManager.party.size():
		var m : Dictionary = PartyManager.party[active_idx]
		if member_label:
			member_label.text = "→ %s" % str(m.name)

# ---------------------------------------------------------------------------
# Round entry
# ---------------------------------------------------------------------------

func _start_round() -> void:
	queued_actions.clear()
	active_idx = 0
	_advance_to_next_living_member()

func _advance_to_next_living_member() -> void:
	while active_idx < PartyManager.party.size():
		if int(PartyManager.party[active_idx].hp) > 0:
			_show_action_menu()
			return
		active_idx += 1
	# All members have acted — execute queued actions then enemy turn.
	_execute_queued_actions()

func _show_action_menu() -> void:
	phase = Phase.PLAYER_INPUT
	_hide_all_submenus()
	action_menu.visible = true
	_update_member_label()
	var m : Dictionary = PartyManager.party[active_idx]
	_log("[color=cyan]%s — choose an action.[/color]" % str(m.name))

func _hide_all_submenus() -> void:
	action_menu.visible = false
	if skill_menu:  skill_menu.visible  = false
	if item_menu:   item_menu.visible   = false
	if target_menu: target_menu.visible = false

# ---------------------------------------------------------------------------
# Action selection
# ---------------------------------------------------------------------------

func _pick_attack() -> void:
	if phase != Phase.PLAYER_INPUT: return
	_queue_action("attack", _single_enemy_targets())
	_next_member()

func _pick_defend() -> void:
	if phase != Phase.PLAYER_INPUT: return
	_queue_action("defend", _self_target())
	_next_member()

func _pick_flee() -> void:
	if phase != Phase.PLAYER_INPUT: return
	var m      : Dictionary = PartyManager.party[active_idx]
	var chance : float      = 0.35 + float(int(m.stats.agi)) * 0.02
	if randf() < chance:
		_log("[color=gray]The party fled![/color]")
		_end_combat("fled")
	else:
		_log("Couldn't escape!")
		_next_member()

func _open_skill_menu() -> void:
	if phase != Phase.PLAYER_INPUT: return
	_hide_all_submenus()
	if not skill_menu: return
	for child in skill_menu.get_children():
		child.queue_free()
	var m      : Dictionary          = PartyManager.party[active_idx]
	var skills : Array[Dictionary]   = SkillExecutor.get_skills_for(str(m.id))
	for s in skills:
		if str(s.get("type","")) == "physical" and str(s.id) == "attack":
			continue   # Attack is on the main menu; skip duplicates.
		var mp_cost : int    = int(s.get("mp_cost", 0))
		var btn     : Button = Button.new()
		btn.text     = "%s  (MP:%d)" % [str(s.name), mp_cost]
		btn.disabled = int(m.mp) < mp_cost
		btn.pressed.connect(_pick_skill.bind(str(s.id)))
		skill_menu.add_child(btn)
	skill_menu.visible = true

func _pick_skill(skill_id: String) -> void:
	if phase != Phase.PLAYER_INPUT: return
	var skill : Dictionary = SkillExecutor.get_skill(skill_id)
	var ttype : String     = str(skill.get("target", "one_enemy"))
	var targets : Array[Dictionary] = _resolve_targets(ttype)
	_queue_action(skill_id, targets)
	_next_member()

func _open_item_menu() -> void:
	if phase != Phase.PLAYER_INPUT: return
	_hide_all_submenus()
	if not item_menu: return
	for child in item_menu.get_children():
		child.queue_free()
	if GameManager.inventory.is_empty():
		_log("No items.")
		return
	for item in GameManager.inventory:
		var btn : Button = Button.new()
		btn.text = "%s ×%d" % [str(item.name), int(item.qty)]
		btn.pressed.connect(_use_item.bind(str(item.id)))
		item_menu.add_child(btn)
	item_menu.visible = true

func _use_item(item_id: String) -> void:
	if phase != Phase.PLAYER_INPUT: return
	var m : Dictionary = PartyManager.party[active_idx]
	match item_id:
		"potion":
			PartyManager.heal_member(str(m.id), 30)
			GameManager.remove_item(item_id)
			_log("%s uses a Potion → +30 HP!" % str(m.name))
		"hi_potion":
			PartyManager.heal_member(str(m.id), 80)
			GameManager.remove_item(item_id)
			_log("%s uses a Hi-Potion → +80 HP!" % str(m.name))
		"ether":
			PartyManager.restore_mp(str(m.id), 20)
			GameManager.remove_item(item_id)
			_log("%s uses an Ether → +20 MP!" % str(m.name))
		"antidote":
			PartyManager.remove_status(str(m.id), "poison")
			GameManager.remove_item(item_id)
			_log("%s uses an Antidote — poison cured!" % str(m.name))
		_:
			_log("Can't use %s here." % item_id.capitalize())
			return
	_build_party_ui()
	_next_member()

func _queue_action(skill_id: String, targets: Array[Dictionary]) -> void:
	var m : Dictionary = PartyManager.party[active_idx]
	queued_actions.append({
		"member_id" : str(m.id),
		"skill_id"  : skill_id,
		"targets"   : targets,
	})

func _next_member() -> void:
	_hide_all_submenus()
	active_idx += 1
	_advance_to_next_living_member()

# ---------------------------------------------------------------------------
# Target resolution helpers
# ---------------------------------------------------------------------------

func _single_enemy_targets() -> Array[Dictionary]:
	var t : Array[Dictionary] = []
	if enemies.size() > selected_enemy:
		t.append(enemies[selected_enemy])
	elif enemies.size() > 0:
		t.append(enemies[0])
	return t

func _self_target() -> Array[Dictionary]:
	var t : Array[Dictionary] = []
	t.append(PartyManager.party[active_idx])
	return t

func _resolve_targets(target_type: String) -> Array[Dictionary]:
	var t : Array[Dictionary] = []
	match target_type:
		"one_enemy":  return _single_enemy_targets()
		"all_enemies":
			for e in enemies: t.append(e)
			return t
		"one_ally":   return _self_target()  ## TODO: let player pick ally
		"all_allies":
			for m in PartyManager.party:
				if int(m.hp) > 0: t.append(m)
			return t
		"self":       return _self_target()
	return t

func _on_enemy_clicked(idx: int) -> void:
	selected_enemy = idx
	_log("Targeting: %s" % str(enemies[idx].name))

# ---------------------------------------------------------------------------
# Execute queued player actions
# ---------------------------------------------------------------------------

func _execute_queued_actions() -> void:
	phase = Phase.RESOLVE
	_hide_all_submenus()

	for action in queued_actions:
		var member : Dictionary = PartyManager.get_member(str(action.member_id))
		if member.is_empty() or int(member.hp) <= 0:
			continue

		var skill : Dictionary = SkillExecutor.get_skill(str(action.skill_id))
		if skill.is_empty():
			continue

		# Deduct MP.
		var mp_cost : int = int(skill.get("mp_cost", 0))
		if mp_cost > 0:
			member.mp = max(0, int(member.mp) - mp_cost)

		_log("[b]%s[/b] uses [color=aqua]%s[/color]!" % [str(member.name), str(skill.name)])

		var targets : Array[Dictionary] = action.targets
		var events  : Array[Dictionary] = SkillExecutor.execute(
			skill, member, targets, enemies, PartyManager.party
		)
		_apply_events(events)

		if enemies.is_empty():
			_victory()
			return

	_build_party_ui()
	_build_enemy_ui()

	await get_tree().create_timer(0.3).timeout
	_enemy_turn()

# ---------------------------------------------------------------------------
# Apply a list of CombatEvents to game state
# ---------------------------------------------------------------------------

func _apply_events(events: Array[Dictionary]) -> void:
	for ev in events:
		var etype : String = str(ev.type)
		_log(str(ev.message))

		match etype:
			"damage":
				var tid : String = str(ev.target_id)
				# Damage can hit enemies or party members.
				var hit_enemy : bool = false
				for e in enemies:
					if str(e.id) == tid:
						e.hp = max(0, int(e.hp) - int(ev.value))
						if int(e.hp) <= 0:
							_log("[color=red]%s is defeated![/color]" % str(e.name))
						hit_enemy = true
						break
				if not hit_enemy:
					PartyManager.damage_member(tid, int(ev.value))

			"heal":
				PartyManager.heal_member(str(ev.target_id), int(ev.value))

			"status":
				var eff : String = str(ev.status_applied)
				var tid : String = str(ev.target_id)
				# Status can apply to enemies or party.
				var found_enemy : bool = false
				for e in enemies:
					if str(e.id) == tid:
						if eff not in e.status:
							e.status.append(eff)
						found_enemy = true
						break
				if not found_enemy:
					PartyManager.add_status(tid, eff)

		AudioManager.play_sfx("res://assets/audio/sfx/hit.ogg")

	# Remove dead enemies.
	enemies = enemies.filter(func(e: Dictionary) -> bool: return int(e.hp) > 0)

# ---------------------------------------------------------------------------
# Enemy turn
# ---------------------------------------------------------------------------

func _enemy_turn() -> void:
	phase = Phase.ENEMY_TURN
	var alive_party : Array = PartyManager.party.filter(func(m: Dictionary) -> bool: return int(m.hp) > 0)

	for enemy in enemies:
		if alive_party.is_empty():
			break
		if "stun" in enemy.get("status", []):
			_log("[color=gray]%s is stunned and cannot act![/color]" % str(enemy.name))
			continue

		var skill_id : String     = _enemy_choose_skill(enemy)
		var skill    : Dictionary = SkillExecutor.get_skill(skill_id)
		if skill.is_empty():
			continue

		var ttype   : String             = str(skill.get("target", "one_enemy"))
		var targets : Array[Dictionary]  = _enemy_resolve_targets(ttype, alive_party)
		if targets.is_empty():
			continue

		# Deduct enemy MP.
		var mp_cost : int = int(skill.get("mp_cost", 0))
		if mp_cost > 0:
			enemy.mp = max(0, int(enemy.get("mp", 0)) - mp_cost)

		_log("[color=orange][b]%s[/b][/color] uses [color=aqua]%s[/color]!" % [str(enemy.name), str(skill.name)])

		var events : Array[Dictionary] = SkillExecutor.execute(
			skill, enemy, targets, enemies, PartyManager.party
		)
		_apply_events(events)

		if PartyManager.is_party_wiped():
			_defeat()
			return

	_status_tick()

func _enemy_choose_skill(enemy: Dictionary) -> String:
	var ai       : String         = str(enemy.get("ai", "basic_attack"))
	var hp_pct   : float          = float(int(enemy.hp)) / float(int(enemy.max_hp))
	var skills   : Array          = enemy.get("skills", ["attack"])
	var mp       : int            = int(enemy.get("mp", 0))

	match ai:
		"defend_when_low":
			if hp_pct < 0.35 and "defend" in skills:
				return "defend"
		"magic_preferred":
			# Prefer magic skills when MP is available.
			for sid in skills:
				var s : Dictionary = SkillExecutor.get_skill(str(sid))
				if not s.is_empty() and str(s.get("type","")) == "magic" and mp >= int(s.get("mp_cost",0)):
					return str(sid)
		"boss_golem":
			# Boss alternates: shield_bash every 3rd turn, otherwise attack.
			if randi() % 3 == 0 and "shield_bash" in skills:
				return "shield_bash"

	# Default: pick a random usable skill.
	var usable : Array[String] = []
	for sid in skills:
		var s : Dictionary = SkillExecutor.get_skill(str(sid))
		if not s.is_empty() and mp >= int(s.get("mp_cost",0)):
			usable.append(str(sid))
	if usable.is_empty():
		return "attack"
	return usable[randi() % usable.size()]

func _enemy_resolve_targets(ttype: String, alive_party: Array) -> Array[Dictionary]:
	var t : Array[Dictionary] = []
	match ttype:
		"one_enemy":
			# Enemy targets a random alive party member.
			if alive_party.size() > 0:
				var pick : Dictionary = alive_party[randi() % alive_party.size()]
				t.append(pick)
		"all_enemies":
			# From the enemy's perspective "all enemies" = the whole party.
			for m in alive_party:
				t.append(m)
		_:
			if alive_party.size() > 0:
				t.append(alive_party[randi() % alive_party.size()])
	return t

# ---------------------------------------------------------------------------
# Status tick — runs once per round after enemy turn
# ---------------------------------------------------------------------------

func _status_tick() -> void:
	phase = Phase.STATUS_TICK

	# Tick party status effects.
	for m in PartyManager.party:
		if int(m.hp) <= 0:
			continue
		if "poison" in m.status:
			var dot : int = max(1, int(m.max_hp) / 10)
			PartyManager.damage_member(str(m.id), dot)
			_log("[color=purple]%s is poisoned! -%d HP[/color]" % [str(m.name), dot])
		if "burn" in m.status:
			var dot : int = max(1, int(m.max_hp) / 12)
			PartyManager.damage_member(str(m.id), dot)
			_log("[color=orange]%s is burning! -%d HP[/color]" % [str(m.name), dot])
		# Clear single-turn statuses.
		PartyManager.remove_status(str(m.id), "defending")
		PartyManager.remove_status(str(m.id), "stun")

	# Tick enemy status effects.
	for e in enemies:
		if "poison" in e.get("status", []):
			var dot : int = max(1, int(e.max_hp) / 10)
			e.hp = max(0, int(e.hp) - dot)
			_log("[color=purple]%s is poisoned! -%d HP[/color]" % [str(e.name), dot])
		e.status.erase("stun")

	enemies = enemies.filter(func(e: Dictionary) -> bool: return int(e.hp) > 0)

	if enemies.is_empty():
		_victory()
		return
	if PartyManager.is_party_wiped():
		_defeat()
		return

	_build_party_ui()
	_build_enemy_ui()
	await get_tree().create_timer(0.5).timeout
	_start_round()

# ---------------------------------------------------------------------------
# Outcomes
# ---------------------------------------------------------------------------

func _victory() -> void:
	phase = Phase.RESULT
	_hide_all_submenus()

	var total_exp  : int = 0
	var total_gold : int = 0
	for e in enemies:
		total_exp  += int(e.get("exp_reward",  10))
		total_gold += int(e.get("gold_reward",   5))
		# Check for item drop.
		var drop_item : String = str(e.get("drop_item", ""))
		var drop_rate : float  = float(e.get("drop_rate", 0.0))
		if drop_item != "" and randf() < drop_rate:
			GameManager.add_item({ "id": drop_item, "name": drop_item.capitalize(), "qty": 1, "type": "consumable" })
			_log("[color=lime]%s dropped a %s![/color]" % [str(e.name), drop_item.capitalize()])

	PartyManager.give_exp(total_exp)
	GameManager.gold += total_gold
	_log("\n[color=green][b]Victory![/b]  +%d EXP   +%d Gold[/color]" % [total_exp, total_gold])
	AudioManager.play_sfx("res://assets/audio/sfx/victory.ogg")
	await get_tree().create_timer(2.5).timeout
	_end_combat("victory")

func _defeat() -> void:
	phase = Phase.RESULT
	_hide_all_submenus()
	_log("\n[color=red][b]The party has fallen...[/b][/color]")
	AudioManager.play_sfx("res://assets/audio/sfx/defeat.ogg")
	await get_tree().create_timer(2.5).timeout
	PartyManager.full_heal_all()   ## Soft reset — no permadeath.
	_end_combat("defeat")

func _end_combat(result: String) -> void:
	emit_signal("combat_ended", result)
	var dest : String = "main" if result == "defeat" else GameManager.current_map
	SceneManager.go_to(dest)

# ---------------------------------------------------------------------------
# Log helper
# ---------------------------------------------------------------------------

func _log(msg: String) -> void:
	if battle_log:
		battle_log.append_text(msg + "\n")
