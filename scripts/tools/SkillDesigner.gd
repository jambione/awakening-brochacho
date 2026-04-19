## SkillDesigner — GUI editor for skills.json.
## Ctrl+S Save  Ctrl+L Load  Ctrl+E Export to res://data/skills/
extends Control

const SAVE_PATH   : String        = "user://skills/"
const RES_PATH    : String        = "res://data/skills/"
const FILE_NAME   : String        = "skills.json"
const SKILL_TYPES : Array[String] = ["physical","magic","healing","status","special"]
const ELEMENTS    : Array[String] = ["none","fire","ice","thunder","earth","wind","light","dark"]
const TARGETS     : Array[String] = ["one_enemy","all_enemies","one_ally","all_allies","self"]
const SCALINGS    : Array[String] = ["","str","agi","int","def","lck"]
const CLASSES     : Array[String] = ["hero","mage","rogue"]
const STATUS_FX   : Array[String] = ["","burn","slow","paralyze","stun","poison","atk_up",
                                      "def_up","defending","blind","silence"]

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var skills   : Array = []
var sel_idx  : int   = -1
var _loading : bool  = false

# ---------------------------------------------------------------------------
# UI refs
# ---------------------------------------------------------------------------
var skill_list   : ItemList
var status_bar   : Label
var f_id         : LineEdit
var f_name       : LineEdit
var f_desc       : TextEdit
var f_type       : OptionButton
var f_element    : OptionButton
var f_target     : OptionButton
var f_mp         : SpinBox
var f_power      : SpinBox
var f_hit        : SpinBox
var f_scaling    : OptionButton
var f_sfx        : OptionButton
var f_sfx_chance : SpinBox
var f_crit       : SpinBox
var f_hits       : SpinBox
var f_duration   : SpinBox
var f_classes    : Array[CheckBox] = []

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

	var tb := HBoxContainer.new(); root.add_child(tb)
	_btn("← Back",        func(): SceneManager.go_to("main"), tb)
	tb.add_child(VSeparator.new())
	_btn("Save (Ctrl+S)", _save_data,     tb)
	_btn("Load (Ctrl+L)", _load_data,     tb)
	_btn("Export→res://", _export_to_res, tb)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	# Left
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(180, 0)
	body.add_child(left)
	left.add_child(_lbl("Skills", true))
	skill_list = ItemList.new()
	skill_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skill_list.item_selected.connect(_on_skill_selected)
	left.add_child(skill_list)
	var lr := HBoxContainer.new(); left.add_child(lr)
	_btn("+ New",     _add_skill,    lr)
	_btn("Delete",    _delete_skill, lr)
	_btn("Duplicate", _dup_skill,    lr)

	body.add_child(VSeparator.new())

	# Right form
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 4)
	scroll.add_child(form)

	form.add_child(_lbl("Skill Editor", true))
	f_id   = _field(form, "ID:",          "e.g. fire")
	f_name = _field(form, "Name:",        "e.g. Fire")

	form.add_child(_lbl("Description:"))
	f_desc = TextEdit.new(); f_desc.custom_minimum_size = Vector2(0, 50)
	f_desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	form.add_child(f_desc)

	# Two-column layout for dropdowns + numeric fields
	var cols := HBoxContainer.new(); form.add_child(cols)
	var col1 := VBoxContainer.new()
	col1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(col1)
	var col2 := VBoxContainer.new()
	col2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(col2)

	f_type    = _opt(col1, "Type:",     SKILL_TYPES)
	f_element = _opt(col1, "Element:",  ELEMENTS)
	f_target  = _opt(col1, "Target:",   TARGETS)
	f_scaling = _opt(col1, "Stat Scaling:", SCALINGS)
	f_sfx     = _opt(col1, "Status Effect:", STATUS_FX)

	f_mp       = _spin(col2, "MP Cost:",       0,  99)
	f_power    = _spin(col2, "Power:",         0, 999)
	f_hit      = _spin(col2, "Hit Rate (%):",  0, 100)
	f_sfx_chance = _spin(col2, "Status Chance (%):", 0, 100)
	f_crit     = _spin(col2, "Crit Bonus (%):", 0, 100)
	f_hits     = _spin(col2, "Hits:",           1,   9)
	f_duration = _spin(col2, "Duration (turns):", 0, 10)

	form.add_child(HSeparator.new())
	form.add_child(_lbl("Learnable By:"))
	var cls_row := HBoxContainer.new(); form.add_child(cls_row)
	for c : String in CLASSES:
		var cb := CheckBox.new(); cb.text = c
		cls_row.add_child(cb); f_classes.append(cb)

	form.add_child(HSeparator.new())
	_btn("✔ Apply Changes", _apply_form, form)

	status_bar = Label.new()
	status_bar.text = "Skill Designer | Ctrl+S Save  Ctrl+L Load  Ctrl+E Export"
	root.add_child(status_bar)

# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------

func _load_data() -> void:
	var user_path := SAVE_PATH + FILE_NAME
	var res_path  := RES_PATH  + FILE_NAME
	var path := user_path if FileAccess.file_exists(user_path) else res_path
	if not FileAccess.file_exists(path):
		skills = []; _rebuild_list(); _set_status("No skills.json — starting blank"); return
	var f := FileAccess.open(path, FileAccess.READ)
	var p := JSON.parse_string(f.get_as_text()); f.close()
	skills = p if p is Array else []
	_rebuild_list(); _set_status("Loaded %d skills" % skills.size())

func _save_data() -> void:
	var path := SAVE_PATH + FILE_NAME
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f: _set_status("ERROR writing " + path); return
	f.store_string(JSON.stringify(skills, "\t")); f.close()
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
	skill_list.clear()
	for sk in skills:
		skill_list.add_item("[%s] %s" % [sk.get("type","?"), sk.get("name","?")])
	if sel_idx >= 0 and sel_idx < skills.size():
		skill_list.select(sel_idx); _load_into_form(sel_idx)

func _on_skill_selected(idx: int) -> void:
	sel_idx = idx; _load_into_form(idx)

func _add_skill() -> void:
	skills.append({"id":"new_skill","name":"New Skill","description":"","type":"physical",
		"element":"none","target":"one_enemy","mp_cost":0,"power":10,"hit_rate":90,
		"stat_scaling":"str","status_effect":"","status_chance":0,"learnable_by":["hero"]})
	sel_idx = skills.size() - 1; _rebuild_list()

func _delete_skill() -> void:
	if sel_idx < 0 or sel_idx >= skills.size(): return
	skills.remove_at(sel_idx); sel_idx = min(sel_idx, skills.size() - 1); _rebuild_list()

func _dup_skill() -> void:
	if sel_idx < 0 or sel_idx >= skills.size(): return
	var copy : Dictionary = skills[sel_idx].duplicate(true)
	copy["id"] = copy.get("id","skill") + "_2"
	skills.append(copy); sel_idx = skills.size() - 1; _rebuild_list()

# ---------------------------------------------------------------------------
# Form
# ---------------------------------------------------------------------------

func _load_into_form(idx: int) -> void:
	if idx < 0 or idx >= skills.size(): return
	var sk : Dictionary = skills[idx]
	_loading = true
	f_id.text     = str(sk.get("id",   ""))
	f_name.text   = str(sk.get("name", ""))
	f_desc.text   = str(sk.get("description", ""))
	f_type.selected    = max(0, SKILL_TYPES.find(str(sk.get("type",    "physical"))))
	f_element.selected = max(0, ELEMENTS.find(str(sk.get("element","none"))))
	f_target.selected  = max(0, TARGETS.find(str(sk.get("target","one_enemy"))))
	f_scaling.selected = max(0, SCALINGS.find(str(sk.get("stat_scaling",""))))
	f_sfx.selected     = max(0, STATUS_FX.find(str(sk.get("status_effect",""))))
	f_mp.value         = float(sk.get("mp_cost",      0))
	f_power.value      = float(sk.get("power",        10))
	f_hit.value        = float(sk.get("hit_rate",     90))
	f_sfx_chance.value = float(sk.get("status_chance", 0))
	f_crit.value       = float(sk.get("crit_bonus",    0))
	f_hits.value       = float(sk.get("hits",           1))
	f_duration.value   = float(sk.get("duration",       0))
	var lb : Array = sk.get("learnable_by", [])
	for i in CLASSES.size(): f_classes[i].button_pressed = CLASSES[i] in lb
	_loading = false

func _apply_form() -> void:
	if sel_idx < 0: _set_status("Select a skill first"); return
	var lb : Array[String] = []
	for i in CLASSES.size():
		if f_classes[i].button_pressed: lb.append(CLASSES[i])
	var data : Dictionary = {
		"id":            f_id.text.strip_edges(),
		"name":          f_name.text,
		"description":   f_desc.text,
		"type":          f_type.get_item_text(f_type.selected),
		"element":       f_element.get_item_text(f_element.selected),
		"target":        f_target.get_item_text(f_target.selected),
		"mp_cost":       int(f_mp.value),
		"power":         int(f_power.value),
		"hit_rate":      int(f_hit.value),
		"stat_scaling":  f_scaling.get_item_text(f_scaling.selected),
		"status_effect": f_sfx.get_item_text(f_sfx.selected),
		"status_chance": int(f_sfx_chance.value),
		"crit_bonus":    int(f_crit.value),
		"hits":          int(f_hits.value),
		"duration":      int(f_duration.value),
		"learnable_by":  lb,
	}
	skills[sel_idx] = data; _rebuild_list()
	_set_status("Applied: " + data["name"])

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _opt(parent: Node, label: String, items_arr: Array) -> OptionButton:
	parent.add_child(_lbl(label))
	var o := OptionButton.new()
	for item : String in items_arr: o.add_item(item)
	parent.add_child(o); return o

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
