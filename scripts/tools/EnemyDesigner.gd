## EnemyDesigner — GUI editor for enemies.json.
## Two-panel: enemy list on the left, full stat form on the right.
## Ctrl+S Save  Ctrl+L Load  Ctrl+E Export to res://data/enemies/
extends Control

const SAVE_PATH : String = "user://enemies/"
const RES_PATH  : String = "res://data/enemies/"
const FILE_NAME : String = "enemies.json"
const ELEMENTS  : Array[String] = ["fire","ice","thunder","earth","wind","light","dark"]
const AI_TYPES  : Array[String] = ["basic_attack","defend_when_low","magic_preferred","boss_golem"]

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var enemies     : Array    = []   ## Array of Dicts, mirrors enemies.json
var sel_idx     : int      = -1
var _loading    : bool     = false

# ---------------------------------------------------------------------------
# UI refs
# ---------------------------------------------------------------------------
var enemy_list  : ItemList
var status_bar  : Label
# Stat fields
var f_id        : LineEdit
var f_name      : LineEdit
var f_level     : SpinBox
var f_hp        : SpinBox
var f_mp        : SpinBox
var f_str       : SpinBox
var f_agi       : SpinBox
var f_int       : SpinBox
var f_def       : SpinBox
var f_lck       : SpinBox
var f_skills    : LineEdit   ## comma-separated
var f_weak      : Array[CheckBox] = []
var f_resist    : Array[CheckBox] = []
var f_exp       : SpinBox
var f_gold      : SpinBox
var f_steal_item: LineEdit
var f_steal_rate: SpinBox
var f_drop_item : LineEdit
var f_drop_rate : SpinBox
var f_ai        : OptionButton
var f_boss      : CheckBox

# ---------------------------------------------------------------------------
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	DirAccess.make_dir_recursive_absolute(SAVE_PATH)
	_build_ui()
	_load_data()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.ctrl_pressed:
		match event.keycode:
			KEY_S: _save_data()
			KEY_L: _load_data()
			KEY_E: _export_to_res()

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Toolbar
	var tb := HBoxContainer.new()
	root.add_child(tb)
	_btn("← Back",        func(): SceneManager.go_to("main"), tb)
	tb.add_child(VSeparator.new())
	_btn("Save (Ctrl+S)", _save_data,    tb)
	_btn("Load (Ctrl+L)", _load_data,    tb)
	_btn("Export→res://", _export_to_res, tb)

	# Body
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	# Left: enemy list
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(180, 0)
	body.add_child(left)
	left.add_child(_lbl("Enemies", true))
	enemy_list = ItemList.new()
	enemy_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	enemy_list.item_selected.connect(_on_enemy_selected)
	left.add_child(enemy_list)
	var lr := HBoxContainer.new(); left.add_child(lr)
	_btn("+ New",   _add_enemy,    lr)
	_btn("Delete",  _delete_enemy, lr)
	_btn("Duplicate", _dup_enemy,  lr)

	body.add_child(VSeparator.new())

	# Right: form
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 4)
	scroll.add_child(form)

	form.add_child(_lbl("Enemy Editor", true))

	f_id   = _field(form, "ID:",   "e.g. goblin")
	f_name = _field(form, "Name:", "e.g. Goblin")

	var stats_h := HBoxContainer.new(); form.add_child(stats_h)
	var left_stats := VBoxContainer.new()
	left_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_h.add_child(left_stats)
	var right_stats := VBoxContainer.new()
	right_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_h.add_child(right_stats)

	f_level = _spin(left_stats,  "Level:",  1,  99)
	f_hp    = _spin(left_stats,  "HP:",     1, 9999)
	f_mp    = _spin(left_stats,  "MP:",     0, 999)
	f_str   = _spin(left_stats,  "STR:",    1,  99)
	f_agi   = _spin(left_stats,  "AGI:",    1,  99)
	f_int   = _spin(right_stats, "INT:",    1,  99)
	f_def   = _spin(right_stats, "DEF:",    1,  99)
	f_lck   = _spin(right_stats, "LCK:",    1,  99)
	f_exp   = _spin(right_stats, "EXP Reward:", 0, 9999)
	f_gold  = _spin(right_stats, "Gold Reward:", 0, 9999)

	form.add_child(_lbl("Skills (comma-separated IDs):"))
	f_skills = LineEdit.new(); f_skills.placeholder_text = "attack,fire,cure"
	form.add_child(f_skills)

	form.add_child(HSeparator.new())
	form.add_child(_lbl("Weaknesses:"))
	var weak_h := HBoxContainer.new(); form.add_child(weak_h)
	for el : String in ELEMENTS:
		var cb := CheckBox.new(); cb.text = el; weak_h.add_child(cb); f_weak.append(cb)

	form.add_child(_lbl("Resistances:"))
	var res_h := HBoxContainer.new(); form.add_child(res_h)
	for el : String in ELEMENTS:
		var cb := CheckBox.new(); cb.text = el; res_h.add_child(cb); f_resist.append(cb)

	form.add_child(HSeparator.new())
	f_steal_item = _field(form, "Steal Item ID:", "e.g. potion")
	f_steal_rate = _spin(form, "Steal Rate (0–1):", 0, 1, 0.05)
	f_drop_item  = _field(form, "Drop Item ID:", "e.g. short_sword")
	f_drop_rate  = _spin(form, "Drop Rate (0–1):", 0, 1, 0.05)

	form.add_child(_lbl("AI Type:"))
	f_ai = OptionButton.new()
	for a : String in AI_TYPES: f_ai.add_item(a)
	form.add_child(f_ai)

	f_boss = CheckBox.new(); f_boss.text = "Is Boss"
	form.add_child(f_boss)

	form.add_child(HSeparator.new())
	_btn("✔ Apply Changes", _apply_form, form)

	# Status
	status_bar = Label.new()
	status_bar.text = "Enemy Designer | Ctrl+S Save  Ctrl+L Load  Ctrl+E Export"
	root.add_child(status_bar)

# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------

func _load_data() -> void:
	var user_path := SAVE_PATH + FILE_NAME
	var res_path  := RES_PATH  + FILE_NAME
	var path := user_path if FileAccess.file_exists(user_path) else res_path
	if not FileAccess.file_exists(path):
		_set_status("No enemies.json found — starting blank"); enemies = []
		_rebuild_list(); return
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed := JSON.parse_string(f.get_as_text()); f.close()
	enemies = parsed if parsed is Array else []
	_rebuild_list()
	_set_status("Loaded %d enemies from %s" % [enemies.size(), path])

func _save_data() -> void:
	var path := SAVE_PATH + FILE_NAME
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f: _set_status("ERROR writing " + path); return
	f.store_string(JSON.stringify(enemies, "\t")); f.close()
	_set_status("Saved: " + path)

func _export_to_res() -> void:
	_save_data()
	var src := SAVE_PATH + FILE_NAME
	if not FileAccess.file_exists(src): _set_status("Save first"); return
	var txt := FileAccess.open(src, FileAccess.READ).get_as_text()
	var out  := FileAccess.open(RES_PATH + FILE_NAME, FileAccess.WRITE)
	if not out: _set_status("Export failed"); return
	out.store_string(txt); out.close()
	_set_status("Exported → " + RES_PATH + FILE_NAME)

# ---------------------------------------------------------------------------
# List
# ---------------------------------------------------------------------------

func _rebuild_list() -> void:
	enemy_list.clear()
	for e in enemies:
		enemy_list.add_item("%s  (Lv%d)" % [e.get("name","?"), int(e.get("level", 1))])
	if sel_idx >= 0 and sel_idx < enemies.size():
		enemy_list.select(sel_idx); _load_into_form(sel_idx)

func _on_enemy_selected(idx: int) -> void:
	sel_idx = idx; _load_into_form(idx)
	_set_status("Editing: " + str(enemies[idx].get("name","?")))

func _add_enemy() -> void:
	enemies.append({
		"id":"new_enemy","name":"New Enemy","level":1,"hp":20,"mp":0,
		"stats":{"str":5,"agi":5,"int":5,"def":5,"lck":5},
		"skills":["attack"],"weaknesses":[],"resistances":[],
		"exp_reward":10,"gold_reward":5,"steal_item":"","steal_rate":0.0,
		"drop_item":"","drop_rate":0.0,"ai":"basic_attack"
	})
	sel_idx = enemies.size() - 1
	_rebuild_list()

func _delete_enemy() -> void:
	if sel_idx < 0 or sel_idx >= enemies.size(): return
	enemies.remove_at(sel_idx)
	sel_idx = min(sel_idx, enemies.size() - 1)
	_rebuild_list()

func _dup_enemy() -> void:
	if sel_idx < 0 or sel_idx >= enemies.size(): return
	var copy : Dictionary = enemies[sel_idx].duplicate(true)
	copy["id"] = copy.get("id","enemy") + "_copy"
	enemies.append(copy); sel_idx = enemies.size() - 1
	_rebuild_list()

# ---------------------------------------------------------------------------
# Form
# ---------------------------------------------------------------------------

func _load_into_form(idx: int) -> void:
	if idx < 0 or idx >= enemies.size(): return
	var e : Dictionary = enemies[idx]
	var stats : Dictionary = e.get("stats", {})
	_loading = true
	f_id.text    = str(e.get("id",    ""))
	f_name.text  = str(e.get("name",  ""))
	f_level.value = float(e.get("level", 1))
	f_hp.value   = float(e.get("hp",  20))
	f_mp.value   = float(e.get("mp",   0))
	f_str.value  = float(stats.get("str", 5))
	f_agi.value  = float(stats.get("agi", 5))
	f_int.value  = float(stats.get("int", 5))
	f_def.value  = float(stats.get("def", 5))
	f_lck.value  = float(stats.get("lck", 5))
	f_exp.value  = float(e.get("exp_reward",  10))
	f_gold.value = float(e.get("gold_reward",  5))
	f_skills.text     = ",".join(e.get("skills", []))
	f_steal_item.text = str(e.get("steal_item", ""))
	f_steal_rate.value = float(e.get("steal_rate", 0.0))
	f_drop_item.text  = str(e.get("drop_item", ""))
	f_drop_rate.value = float(e.get("drop_rate", 0.0))
	f_ai.selected = max(0, AI_TYPES.find(str(e.get("ai","basic_attack"))))
	f_boss.button_pressed = bool(e.get("is_boss", false))
	var weak    : Array = e.get("weaknesses",  [])
	var resist  : Array = e.get("resistances", [])
	for i in ELEMENTS.size():
		f_weak[i].button_pressed   = ELEMENTS[i] in weak
		f_resist[i].button_pressed = ELEMENTS[i] in resist
	_loading = false

func _apply_form() -> void:
	if sel_idx < 0: _set_status("Select an enemy first"); return
	var weak   : Array[String] = []
	var resist : Array[String] = []
	for i in ELEMENTS.size():
		if f_weak[i].button_pressed:   weak.append(ELEMENTS[i])
		if f_resist[i].button_pressed: resist.append(ELEMENTS[i])
	var skills : Array = []
	for s : String in f_skills.text.split(","):
		var t := s.strip_edges()
		if t != "": skills.append(t)
	enemies[sel_idx] = {
		"id":          f_id.text.strip_edges(),
		"name":        f_name.text,
		"level":       int(f_level.value),
		"hp":          int(f_hp.value),
		"mp":          int(f_mp.value),
		"stats":       {"str": int(f_str.value),"agi": int(f_agi.value),
		                "int": int(f_int.value),"def": int(f_def.value),"lck": int(f_lck.value)},
		"skills":      skills,
		"weaknesses":  weak,
		"resistances": resist,
		"exp_reward":  int(f_exp.value),
		"gold_reward": int(f_gold.value),
		"steal_item":  f_steal_item.text,
		"steal_rate":  f_steal_rate.value,
		"drop_item":   f_drop_item.text,
		"drop_rate":   f_drop_rate.value,
		"ai":          f_ai.get_item_text(f_ai.selected),
		"is_boss":     f_boss.button_pressed,
	}
	_rebuild_list()
	_set_status("Applied: " + enemies[sel_idx].get("name", "?"))

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _field(parent: Node, label: String, ph: String) -> LineEdit:
	parent.add_child(_lbl(label))
	var e := LineEdit.new(); e.placeholder_text = ph; parent.add_child(e); return e

func _spin(parent: Node, label: String, lo: float, hi: float, step: float = 1.0) -> SpinBox:
	parent.add_child(_lbl(label))
	var s := SpinBox.new(); s.min_value = lo; s.max_value = hi; s.step = step
	parent.add_child(s); return s

func _lbl(text: String, bold: bool = false) -> Label:
	var l := Label.new(); l.text = text
	if bold: l.add_theme_font_size_override("font_size", 14)
	return l

func _btn(text: String, cb: Callable, parent: Node) -> Button:
	var b := Button.new(); b.text = text; b.pressed.connect(cb)
	parent.add_child(b); return b

func _set_status(msg: String) -> void:
	if status_bar: status_bar.text = msg
