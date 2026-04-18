## ItemDesigner — GUI editor for items.json.
## Handles consumables, weapons, armor, and key items.
## Ctrl+S Save  Ctrl+L Load  Ctrl+E Export to res://data/items/
extends Control

const SAVE_PATH  : String        = "user://items/"
const RES_PATH   : String        = "res://data/items/"
const FILE_NAME  : String        = "items.json"
const ITEM_TYPES : Array[String] = ["consumable","weapon","armor","key_item"]
const EFFECTS    : Array[String] = ["heal_hp","heal_mp","cure_poison","revive","full_heal","none"]

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var items    : Array = []
var sel_idx  : int   = -1
var _loading : bool  = false

# ---------------------------------------------------------------------------
# UI refs
# ---------------------------------------------------------------------------
var item_list     : ItemList
var status_bar    : Label
var f_id          : LineEdit
var f_name        : LineEdit
var f_type        : OptionButton
var f_price       : SpinBox
# consumable
var consumable_box : VBoxContainer
var f_effect       : OptionButton
var f_value        : SpinBox
# weapon
var weapon_box     : VBoxContainer
var f_w_str        : SpinBox
var f_w_agi        : SpinBox
var f_w_lck        : SpinBox
# armor
var armor_box      : VBoxContainer
var f_a_def        : SpinBox
var f_a_agi        : SpinBox
# key item
var key_box        : VBoxContainer
var f_key_desc     : LineEdit

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
	left.add_child(_lbl("Items", true))
	item_list = ItemList.new()
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.item_selected.connect(_on_item_selected)
	left.add_child(item_list)
	var lr := HBoxContainer.new(); left.add_child(lr)
	_btn("+ New",     _add_item,    lr)
	_btn("Delete",    _delete_item, lr)
	_btn("Duplicate", _dup_item,    lr)

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

	form.add_child(_lbl("Item Editor", true))
	f_id    = _field(form, "ID:",    "e.g. potion")
	f_name  = _field(form, "Name:", "e.g. Potion")

	form.add_child(_lbl("Type:"))
	f_type = OptionButton.new()
	for t : String in ITEM_TYPES: f_type.add_item(t)
	f_type.item_selected.connect(_on_type_changed)
	form.add_child(f_type)

	f_price = _spin(form, "Price (gold):", 0, 99999)

	form.add_child(HSeparator.new())

	# Consumable panel
	consumable_box = VBoxContainer.new(); form.add_child(consumable_box)
	consumable_box.add_child(_lbl("Effect:"))
	f_effect = OptionButton.new()
	for e : String in EFFECTS: f_effect.add_item(e)
	consumable_box.add_child(f_effect)
	f_value = _spin(consumable_box, "Effect Value (HP/MP restored):", 0, 9999)

	# Weapon panel
	weapon_box = VBoxContainer.new(); form.add_child(weapon_box)
	weapon_box.add_child(_lbl("Weapon Stat Bonuses:"))
	f_w_str = _spin(weapon_box, "STR Bonus:", 0, 99)
	f_w_agi = _spin(weapon_box, "AGI Bonus:", 0, 99)
	f_w_lck = _spin(weapon_box, "LCK Bonus:", 0, 99)

	# Armor panel
	armor_box = VBoxContainer.new(); form.add_child(armor_box)
	armor_box.add_child(_lbl("Armor Stat Bonuses:"))
	f_a_def = _spin(armor_box, "DEF Bonus:", 0, 99)
	f_a_agi = _spin(armor_box, "AGI Bonus:", 0, 99)

	# Key item panel
	key_box = VBoxContainer.new(); form.add_child(key_box)
	f_key_desc = _field(key_box, "Description:", "Quest item description")

	form.add_child(HSeparator.new())
	_btn("✔ Apply Changes", _apply_form, form)

	status_bar = Label.new()
	status_bar.text = "Item Designer | Ctrl+S Save  Ctrl+L Load  Ctrl+E Export"
	root.add_child(status_bar)

	_on_type_changed(0)

# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------

func _load_data() -> void:
	var user_path := SAVE_PATH + FILE_NAME
	var res_path  := RES_PATH  + FILE_NAME
	var path := user_path if FileAccess.file_exists(user_path) else res_path
	if not FileAccess.file_exists(path):
		items = []; _rebuild_list()
		_set_status("No items.json found — starting blank"); return
	var f := FileAccess.open(path, FileAccess.READ)
	var p := JSON.parse_string(f.get_as_text()); f.close()
	items = p if p is Array else []
	_rebuild_list()
	_set_status("Loaded %d items" % items.size())

func _save_data() -> void:
	var path := SAVE_PATH + FILE_NAME
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f: _set_status("ERROR writing " + path); return
	f.store_string(JSON.stringify(items, "\t")); f.close()
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
	item_list.clear()
	for it in items:
		item_list.add_item("[%s] %s" % [it.get("type","?"), it.get("name","?")])
	if sel_idx >= 0 and sel_idx < items.size():
		item_list.select(sel_idx); _load_into_form(sel_idx)

func _on_item_selected(idx: int) -> void:
	sel_idx = idx; _load_into_form(idx)

func _add_item() -> void:
	items.append({"id":"new_item","name":"New Item","type":"consumable","effect":"heal_hp","value":20,"price":30})
	sel_idx = items.size() - 1; _rebuild_list()

func _delete_item() -> void:
	if sel_idx < 0 or sel_idx >= items.size(): return
	items.remove_at(sel_idx); sel_idx = min(sel_idx, items.size() - 1); _rebuild_list()

func _dup_item() -> void:
	if sel_idx < 0 or sel_idx >= items.size(): return
	var copy : Dictionary = items[sel_idx].duplicate(true)
	copy["id"] = copy.get("id","item") + "_copy"; items.append(copy)
	sel_idx = items.size() - 1; _rebuild_list()

# ---------------------------------------------------------------------------
# Form
# ---------------------------------------------------------------------------

func _on_type_changed(_idx: int) -> void:
	var t := f_type.get_item_text(f_type.selected)
	consumable_box.visible = (t == "consumable")
	weapon_box.visible     = (t == "weapon")
	armor_box.visible      = (t == "armor")
	key_box.visible        = (t == "key_item")

func _load_into_form(idx: int) -> void:
	if idx < 0 or idx >= items.size(): return
	var it : Dictionary = items[idx]
	_loading = true
	f_id.text    = str(it.get("id",   ""))
	f_name.text  = str(it.get("name", ""))
	var type_idx := ITEM_TYPES.find(str(it.get("type","consumable")))
	f_type.selected = max(0, type_idx)
	f_price.value   = float(it.get("price", 0))
	# Consumable
	var eff_idx := EFFECTS.find(str(it.get("effect","heal_hp")))
	if f_effect: f_effect.selected = max(0, eff_idx)
	if f_value:  f_value.value = float(it.get("value", 0))
	# Weapon
	var ws : Dictionary = it.get("stats", {})
	if f_w_str: f_w_str.value = float(ws.get("str", 0))
	if f_w_agi: f_w_agi.value = float(ws.get("agi", 0))
	if f_w_lck: f_w_lck.value = float(ws.get("lck", 0))
	# Armor
	if f_a_def: f_a_def.value = float(ws.get("def", 0))
	if f_a_agi: f_a_agi.value = float(ws.get("agi", 0))
	# Key
	if f_key_desc: f_key_desc.text = str(it.get("description",""))
	_loading = false
	_on_type_changed(f_type.selected)

func _apply_form() -> void:
	if sel_idx < 0: _set_status("Select an item first"); return
	var type := f_type.get_item_text(f_type.selected)
	var data : Dictionary = {
		"id":    f_id.text.strip_edges(),
		"name":  f_name.text,
		"type":  type,
		"price": int(f_price.value),
	}
	match type:
		"consumable":
			data["effect"] = f_effect.get_item_text(f_effect.selected)
			data["value"]  = int(f_value.value)
		"weapon":
			var st : Dictionary = {}
			if f_w_str.value > 0: st["str"] = int(f_w_str.value)
			if f_w_agi.value > 0: st["agi"] = int(f_w_agi.value)
			if f_w_lck.value > 0: st["lck"] = int(f_w_lck.value)
			data["stats"] = st
		"armor":
			var st : Dictionary = {}
			if f_a_def.value > 0: st["def"] = int(f_a_def.value)
			if f_a_agi.value > 0: st["agi"] = int(f_a_agi.value)
			data["stats"] = st
		"key_item":
			data["description"] = f_key_desc.text
	items[sel_idx] = data
	_rebuild_list()
	_set_status("Applied: " + data["name"])

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
