## QuestDesigner — GUI editor for quests.json.
## Ctrl+S Save  Ctrl+L Load  Ctrl+E Export to res://data/quests/
extends Control

const SAVE_PATH : String = "user://quests/"
const RES_PATH  : String = "res://data/quests/"
const FILE_NAME : String = "quests.json"

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var quests   : Array = []
var sel_idx  : int   = -1
var _loading : bool  = false

# ---------------------------------------------------------------------------
# UI refs
# ---------------------------------------------------------------------------
var quest_list   : ItemList
var status_bar   : Label
var f_id         : LineEdit
var f_name       : LineEdit
var f_desc       : TextEdit
var f_req_flags  : LineEdit   ## comma-separated
var f_comp_flags : LineEdit   ## comma-separated
var f_chain      : LineEdit
var f_exp        : SpinBox
var f_gold       : SpinBox
var f_items      : LineEdit   ## comma-separated item IDs
var obj_vbox     : VBoxContainer

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

	# Left — quest list
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(200, 0)
	body.add_child(left)
	left.add_child(_lbl("Quests", true))
	quest_list = ItemList.new()
	quest_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	quest_list.item_selected.connect(_on_quest_selected)
	left.add_child(quest_list)
	var lr := HBoxContainer.new(); left.add_child(lr)
	_btn("+ New",     _add_quest,    lr)
	_btn("Delete",    _delete_quest, lr)
	_btn("Duplicate", _dup_quest,    lr)

	body.add_child(VSeparator.new())

	# Right — form
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 4)
	scroll.add_child(form)

	form.add_child(_lbl("Quest Editor", true))
	f_id   = _field(form, "ID:",            "e.g. ch1_dungeon_descent")
	f_name = _field(form, "Display Name:",  "e.g. Descend the Thornwood Dungeon")

	form.add_child(_lbl("Description:"))
	f_desc = TextEdit.new()
	f_desc.custom_minimum_size = Vector2(0, 70)
	f_desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	f_desc.placeholder_text = "Quest description shown in the journal."
	form.add_child(f_desc)

	form.add_child(HSeparator.new())
	form.add_child(_lbl("Objectives:", true))
	obj_vbox = VBoxContainer.new(); form.add_child(obj_vbox)
	_btn("+ Add Objective", _add_objective_row, form)

	form.add_child(HSeparator.new())
	form.add_child(_lbl("Rewards:", true))
	f_exp  = _spin(form, "EXP Reward:",  0, 99999)
	f_gold = _spin(form, "Gold Reward:", 0, 99999)
	f_items = _field(form, "Item Rewards (comma-separated IDs):", "e.g. long_sword,potion")

	form.add_child(HSeparator.new())
	form.add_child(_lbl("Flags:", true))
	f_req_flags  = _field(form, "Required Flags (comma-separated):", "met_rufus,ch1_done")
	f_comp_flags = _field(form, "Set on Completion (comma-separated):", "ch1_dungeon_complete")
	f_chain      = _field(form, "Chain to Quest ID (on complete):", "ch2_main_quest")

	form.add_child(HSeparator.new())
	_btn("✔ Apply Changes", _apply_form, form)

	status_bar = Label.new()
	status_bar.text = "Quest Designer | Ctrl+S Save  Ctrl+L Load  Ctrl+E Export"
	root.add_child(status_bar)

# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------

func _load_data() -> void:
	var user_path := SAVE_PATH + FILE_NAME
	var res_path  := RES_PATH  + FILE_NAME
	var path := user_path if FileAccess.file_exists(user_path) else res_path
	if not FileAccess.file_exists(path):
		quests = []; _rebuild_list()
		_set_status("No quests.json found — starting blank"); return
	var f := FileAccess.open(path, FileAccess.READ)
	var p := JSON.parse_string(f.get_as_text()); f.close()
	quests = p if p is Array else []
	_rebuild_list()
	_set_status("Loaded %d quests" % quests.size())

func _save_data() -> void:
	var path := SAVE_PATH + FILE_NAME
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f: _set_status("ERROR writing " + path); return
	f.store_string(JSON.stringify(quests, "\t")); f.close()
	_set_status("Saved: " + path)

func _export_to_res() -> void:
	_save_data()
	DirAccess.make_dir_recursive_absolute(RES_PATH)
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
	quest_list.clear()
	for q in quests:
		quest_list.add_item(str(q.get("name", q.get("id","?"))))
	if sel_idx >= 0 and sel_idx < quests.size():
		quest_list.select(sel_idx); _load_into_form(sel_idx)

func _on_quest_selected(idx: int) -> void:
	sel_idx = idx; _load_into_form(idx)
	_set_status("Editing: " + str(quests[idx].get("name","?")))

func _add_quest() -> void:
	quests.append({
		"id": "new_quest_%d" % quests.size(),
		"name": "New Quest",
		"description": "",
		"objectives": [],
		"rewards": {"exp": 0, "gold": 0, "items": []},
		"required_flags": [],
		"completion_flags": [],
		"chain_quest": "",
	})
	sel_idx = quests.size() - 1; _rebuild_list()

func _delete_quest() -> void:
	if sel_idx < 0 or sel_idx >= quests.size(): return
	quests.remove_at(sel_idx); sel_idx = min(sel_idx, quests.size() - 1); _rebuild_list()

func _dup_quest() -> void:
	if sel_idx < 0 or sel_idx >= quests.size(): return
	var copy : Dictionary = quests[sel_idx].duplicate(true)
	copy["id"] = copy.get("id","quest") + "_copy"
	quests.append(copy); sel_idx = quests.size() - 1; _rebuild_list()

# ---------------------------------------------------------------------------
# Form
# ---------------------------------------------------------------------------

func _load_into_form(idx: int) -> void:
	if idx < 0 or idx >= quests.size(): return
	var q : Dictionary = quests[idx]
	_loading = true
	f_id.text   = str(q.get("id",   ""))
	f_name.text = str(q.get("name", ""))
	f_desc.text = str(q.get("description", ""))
	var rw : Dictionary = q.get("rewards", {})
	f_exp.value  = float(rw.get("exp",  0))
	f_gold.value = float(rw.get("gold", 0))
	f_items.text = ",".join(rw.get("items", []))
	f_req_flags.text  = ",".join(q.get("required_flags",   []))
	f_comp_flags.text = ",".join(q.get("completion_flags", []))
	f_chain.text      = str(q.get("chain_quest", ""))
	# Objectives
	for c in obj_vbox.get_children(): c.queue_free()
	for obj in q.get("objectives", []):
		_add_objective_row(str(obj.get("id","")), str(obj.get("text","")))
	_loading = false

func _add_objective_row(obj_id: String = "", obj_text: String = "") -> void:
	var row := HBoxContainer.new(); obj_vbox.add_child(row)
	var id_e := LineEdit.new(); id_e.placeholder_text = "objective_id"
	id_e.text = obj_id; id_e.custom_minimum_size = Vector2(120, 0)
	row.add_child(id_e)
	var txt_e := LineEdit.new(); txt_e.placeholder_text = "Objective description"
	txt_e.text = obj_text; txt_e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(txt_e)
	var del := Button.new(); del.text = "✕"
	del.pressed.connect(func() -> void: row.queue_free())
	row.add_child(del)

func _apply_form() -> void:
	if sel_idx < 0: _set_status("Select a quest first"); return
	var objs : Array = []
	for row in obj_vbox.get_children():
		var ch := row.get_children()
		if ch.size() >= 2:
			var oid  : String = (ch[0] as LineEdit).text.strip_edges()
			var otxt : String = (ch[1] as LineEdit).text
			if not oid.is_empty(): objs.append({"id": oid, "text": otxt})
	var req   : Array[String] = _split_csv(f_req_flags.text)
	var comp  : Array[String] = _split_csv(f_comp_flags.text)
	var items : Array[String] = _split_csv(f_items.text)
	quests[sel_idx] = {
		"id":               f_id.text.strip_edges(),
		"name":             f_name.text,
		"description":      f_desc.text,
		"objectives":       objs,
		"rewards":          {"exp": int(f_exp.value), "gold": int(f_gold.value), "items": items},
		"required_flags":   req,
		"completion_flags": comp,
		"chain_quest":      f_chain.text.strip_edges(),
	}
	_rebuild_list()
	_set_status("Applied: " + quests[sel_idx].get("name","?"))

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _split_csv(raw: String) -> Array[String]:
	var result : Array[String] = []
	for s : String in raw.split(","):
		var t := s.strip_edges()
		if t != "": result.append(t)
	return result

func _field(parent: Node, label: String, ph: String) -> LineEdit:
	parent.add_child(_lbl(label))
	var e := LineEdit.new(); e.placeholder_text = ph; parent.add_child(e); return e

func _spin(parent: Node, label: String, lo: float, hi: float) -> SpinBox:
	parent.add_child(_lbl(label))
	var s := SpinBox.new(); s.min_value = lo; s.max_value = hi
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
