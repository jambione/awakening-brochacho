extends Node2D

# ── Signals ───────────────────────────────────────────────────────────────────
signal combat_ended(result: String)  # "victory", "defeat", "fled"

# ── Node refs ─────────────────────────────────────────────────────────────────
@onready var action_menu: VBoxContainer  = $UI/ActionMenu
@onready var battle_log:  RichTextLabel  = $UI/BattleLog
@onready var enemy_row:   HBoxContainer  = $EnemyRow
@onready var party_row:   HBoxContainer  = $PartyRow

# ── State ─────────────────────────────────────────────────────────────────────
enum Phase { PLAYER_TURN, ENEMY_TURN, ANIMATING, RESULT }
var phase:         Phase   = Phase.PLAYER_TURN
var enemies:       Array[Dictionary] = []
var active_member_idx: int = 0
var selected_enemy_idx: int = 0
var turn_order:    Array[Dictionary] = []

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Pick up enemy group set by SceneManager
	if get_tree().has_meta("combat_enemies"):
		enemies = get_tree().get_meta("combat_enemies")
	else:
		enemies = [_make_test_enemy()]

	_build_enemy_ui()
	_build_party_ui()
	_wire_action_buttons()
	_start_player_turn()
	AudioManager.play_music("res://assets/audio/music/battle_theme.ogg")

# ── Enemy factory (placeholder) ───────────────────────────────────────────────
func _make_test_enemy() -> Dictionary:
	return {
		"id": "slime", "name": "Slime", "level": 1,
		"hp": 12, "max_hp": 12, "mp": 0,
		"stats": { "str": 4, "agi": 3, "def": 2 },
		"exp_reward": 10, "gold_reward": 5,
		"skills": ["attack"],
	}

# ── UI build ──────────────────────────────────────────────────────────────────
func _build_enemy_ui() -> void:
	for child in enemy_row.get_children():
		child.queue_free()
	for i in enemies.size():
		var lbl := Label.new()
		lbl.text = "%s\nHP:%d" % [enemies[i].name, enemies[i].hp]
		lbl.set_meta("enemy_idx", i)
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		lbl.gui_input.connect(_on_enemy_clicked.bind(i))
		enemy_row.add_child(lbl)

func _build_party_ui() -> void:
	for child in party_row.get_children():
		child.queue_free()
	for m in PartyManager.party:
		var lbl := Label.new()
		lbl.text = "%s\nHP:%d/%d" % [m.name, m.hp, m.max_hp]
		party_row.add_child(lbl)

func _wire_action_buttons() -> void:
	$UI/ActionMenu/Attack.pressed.connect(_action_attack)
	$UI/ActionMenu/Magic.pressed.connect(_action_magic)
	$UI/ActionMenu/Item.pressed.connect(_action_item)
	$UI/ActionMenu/Defend.pressed.connect(_action_defend)
	$UI/ActionMenu/Flee.pressed.connect(_action_flee)

# ── Turn flow ─────────────────────────────────────────────────────────────────
func _start_player_turn() -> void:
	phase = Phase.PLAYER_TURN
	# Find next alive party member
	while active_member_idx < PartyManager.party.size():
		if PartyManager.party[active_member_idx].hp > 0:
			break
		active_member_idx += 1

	if active_member_idx >= PartyManager.party.size():
		_enemy_turn()
		return

	var m: Dictionary = PartyManager.party[active_member_idx]
	_log("[color=cyan]%s's turn.[/color]" % m.name)
	action_menu.visible = true

func _end_player_action() -> void:
	active_member_idx += 1
	action_menu.visible = false

	if active_member_idx >= PartyManager.party.size():
		active_member_idx = 0
		_enemy_turn()
	else:
		_start_player_turn()

# ── Player actions ────────────────────────────────────────────────────────────
func _action_attack() -> void:
	if enemies.is_empty() or phase != Phase.PLAYER_TURN:
		return
	var attacker: Dictionary = PartyManager.party[active_member_idx]
	var target: Dictionary   = enemies[selected_enemy_idx]
	var dmg: int = max(1, attacker.stats.str - target.stats.def + randi_range(-2, 3))
	target.hp = max(0, target.hp - dmg)
	_log("%s attacks %s for [color=yellow]%d[/color] damage!" % [attacker.name, target.name, dmg])
	AudioManager.play_sfx("res://assets/audio/sfx/hit.ogg")

	if target.hp <= 0:
		_log("[color=red]%s is defeated![/color]" % target.name)
		enemies.remove_at(selected_enemy_idx)
		selected_enemy_idx = 0
		if enemies.is_empty():
			_victory()
			return

	_build_enemy_ui()
	_end_player_action()

func _action_magic() -> void:
	# Placeholder — expand with skill system later
	_log("No magic known yet.")

func _action_item() -> void:
	if GameManager.has_item("potion"):
		var m: Dictionary = PartyManager.party[active_member_idx]
		PartyManager.heal_member(m.id, 20)
		GameManager.remove_item("potion")
		_log("%s uses a Potion! Restored 20 HP." % m.name)
		_build_party_ui()
		_end_player_action()
	else:
		_log("No items available.")

func _action_defend() -> void:
	var m: Dictionary = PartyManager.party[active_member_idx]
	PartyManager.add_status(m.id, "defending")
	_log("%s takes a defensive stance." % m.name)
	_end_player_action()

func _action_flee() -> void:
	var chance := 0.4 + PartyManager.party[active_member_idx].stats.agi * 0.02
	if randf() < chance:
		_log("The party fled!")
		await get_tree().create_timer(1.0).timeout
		emit_signal("combat_ended", "fled")
		SceneManager.go_to(GameManager.current_map)
	else:
		_log("Couldn't escape!")
		_end_player_action()

func _on_enemy_clicked(idx: int) -> void:
	selected_enemy_idx = idx
	_log("Targeting: %s" % enemies[idx].name)

# ── Enemy turn ────────────────────────────────────────────────────────────────
func _enemy_turn() -> void:
	phase = Phase.ENEMY_TURN
	for enemy in enemies:
		if PartyManager.is_party_wiped():
			break
		var targets: Array = PartyManager.party.filter(func(m): return m.hp > 0)
		if targets.is_empty():
			break
		var target: Dictionary = targets[randi() % targets.size()]
		var dmg: int = max(1, enemy.stats.str - target.stats.def + randi_range(-1, 2))
		# Halve damage if target is defending
		if PartyManager.has_status(target.id, "defending"):
			dmg = max(1, dmg / 2)
		PartyManager.damage_member(target.id, dmg)
		_log("[color=orange]%s[/color] attacks %s for [color=yellow]%d[/color] damage!" % [enemy.name, target.name, dmg])
		AudioManager.play_sfx("res://assets/audio/sfx/hit.ogg")

	# Clear defend status
	for m in PartyManager.party:
		PartyManager.remove_status(m.id, "defending")

	_build_party_ui()

	if PartyManager.is_party_wiped():
		_defeat()
		return

	active_member_idx = 0
	await get_tree().create_timer(0.8).timeout
	_start_player_turn()

# ── Outcomes ──────────────────────────────────────────────────────────────────
func _victory() -> void:
	phase = Phase.RESULT
	action_menu.visible = false
	var total_exp  := 0
	var total_gold := 0
	for e in enemies:
		total_exp  += e.get("exp_reward",  10)
		total_gold += e.get("gold_reward",  5)
	PartyManager.give_exp(total_exp)
	GameManager.gold += total_gold
	_log("[color=green]Victory! +%d EXP, +%d Gold[/color]" % [total_exp, total_gold])
	AudioManager.play_sfx("res://assets/audio/sfx/victory.ogg")
	await get_tree().create_timer(2.0).timeout
	emit_signal("combat_ended", "victory")
	SceneManager.go_to(GameManager.current_map)

func _defeat() -> void:
	phase = Phase.RESULT
	action_menu.visible = false
	_log("[color=red]The party was defeated...[/color]")
	AudioManager.play_sfx("res://assets/audio/sfx/defeat.ogg")
	await get_tree().create_timer(2.5).timeout
	emit_signal("combat_ended", "defeat")
	PartyManager.full_heal_all()
	SceneManager.go_to("main")

# ── Log helper ────────────────────────────────────────────────────────────────
func _log(msg: String) -> void:
	battle_log.append_text(msg + "\n")
