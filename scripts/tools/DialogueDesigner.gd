## DialogueDesigner — visual editor for branching dialogue JSON files.
##
## Three-panel layout: Dialogue IDs | Node list | Node editor form.
## Reads the existing ch1_dialogue.json schema used by DialoguePlayer.gd.
##
## JSON schema per node:
##   speaker, text, next, choices[]={text,next}, set_flag,
##   start_quest, complete_quest, add_member, give_item
##
## Ctrl+S Save   Ctrl+L Load   Ctrl+E Export to res://data/story/
extends Control

const SAVE_PATH : String = "user://dialogue/"
const RES_PATH  : String = "res://data/story/"

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var all_data     : Dictionary = {}   ## { dialogue_id: { nodes: { id: {...} } } }
var file_name    : String     = "ch1_dialogue"
var sel_dialogue : String     = ""
var sel_node     : String     = ""
var _loading     : bool       = false

# ---------------------------------------------------------------------------
# UI refs (built in _ready)
# ---------------------------------------------------------------------------
var file_name_input : LineEdit
var dialogue_list   : ItemList
var node_list       : ItemList
var node_id_edit    : LineEdit
var speaker_edit    : LineEdit
var text_edit       : TextEdit
var next_edit       : LineEdit
var choices_vbox    : VBoxContainer
var fx_flag_edit    : LineEdit
var fx_sq_edit      : LineEdit
var fx_cq_edit      : LineEdit
var fx_member_opt   : OptionButton
var fx_item_edit    : LineEdit
var status_bar      : Label
var form_vbox       : VBoxContainer

# ---------------------------------------------------------------------------
# Lifecycle
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
	tb.add_theme_constant_override("separation", 4)
	root.add_child(tb)
	_btn("← Back",        func(): SceneManager.go_to("main"), tb)
	tb.add_child(VSeparator.new())
	file_name_input = LineEdit.new()
	file_name_input.text              = file_name
	file_name_input.placeholder_text  = "dialogue_file_name"
	file_name_input.custom_minimum_size = Vector2(160, 0)
	file_name_input.text_changed.connect(func(t: String) -> void: file_name = t)
	tb.add_child(file_name_input)
	_btn("Save (Ctrl+S)",   _save_data,      tb)
	_btn("Load (Ctrl+L)",   _load_data,      tb)
	_btn("Export→res://",  _export_to_res,  tb)
	_btn("New File",        _new_file,       tb)

	# Main three-panel area
	var main_h := HBoxContainer.new()
	main_h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_h.add_theme_constant_override("separation", 0)
	root.add_child(main_h)

	# Left: dialogue list
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(160, 0)
	main_h.add_child(left)
	left.add_child(_lbl("Dialogues", true))
	dialogue_list = ItemList.new()
	dialogue_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialogue_list.item_selected.connect(_on_dialogue_selected)
	left.add_child(dialogue_list)
	var dl_row := HBoxContainer.new()
	left.add_child(dl_row)
	_btn("+ New",   _add_dialogue,   dl_row)
	_btn("Delete",  _delete_dialogue, dl_row)

	main_h.add_child(VSeparator.new())

	# Center: node list
	var center := VBoxContainer.new()
	center.custom_minimum_size = Vector2(170, 0)
	main_h.add_child(center)
	center.add_child(_lbl("Nodes", true))
	node_list = ItemList.new()
	node_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	node_list.item_selected.connect(_on_node_selected)
	center.add_child(node_list)
	var nl_row := HBoxContainer.new()
	center.add_child(nl_row)
	_btn("+ Node",  _add_node,    nl_row)
	_btn("Delete",  _delete_node, nl_row)

	main_h.add_child(VSeparator.new())

	# Right: node editor
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	main_h.add_child(scroll)

	form_vbox = VBoxContainer.new()
	form_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(form_vbox)

	form_vbox.add_child(_lbl("Node Editor", true))

	form_vbox.add_child(_lbl("Node ID:"))
	node_id_edit = LineEdit.new(); node_id_edit.placeholder_text = "e.g. start, n1, end"
	form_vbox.add_child(node_id_edit)

	form_vbox.add_child(_lbl("Speaker:"))
	speaker_edit = LineEdit.new(); speaker_edit.placeholder_text = "NPC name, or empty"
	form_vbox.add_child(speaker_edit)

	form_vbox.add_child(_lbl("Text (BBCode supported):"))
	text_edit = TextEdit.new()
	text_edit.custom_minimum_size = Vector2(0, 90)
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	form_vbox.add_child(text_edit)

	form_vbox.add_child(_lbl("Next Node ID:"))
	next_edit = LineEdit.new(); next_edit.placeholder_text = "e.g. n1, end"
	form_vbox.add_child(next_edit)

	form_vbox.add_child(HSeparator.new())
	form_vbox.add_child(_lbl("Choices (if any — overrides Next):"))
	choices_vbox = VBoxContainer.new()
	form_vbox.add_child(choices_vbox)
	_btn("+ Add Choice", _on_add_choice, form_vbox)

	form_vbox.add_child(HSeparator.new())
	form_vbox.add_child(_lbl("Side Effects:"))
	fx_flag_edit = _fx_row("Set Flag:")
	fx_sq_edit   = _fx_row("Start Quest:")
	fx_cq_edit   = _fx_row("Complete Quest:")
	fx_item_edit = _fx_row("Give Item ID:")
	form_vbox.add_child(_lbl("Add Party Member:"))
	fx_member_opt = OptionButton.new()
	for m : String in ["(none)", "hero", "mage", "rogue"]:
		fx_member_opt.add_item(m)
	form_vbox.add_child(fx_member_opt)

	form_vbox.add_child(HSeparator.new())
	_btn("✔ Apply Changes", _apply_form, form_vbox)

	# Status bar
	status_bar = Label.new()
	status_bar.text = "Dialogue Designer | Ctrl+S Save  Ctrl+L Load  Ctrl+E Export"
	root.add_child(status_bar)

func _fx_row(label: String) -> LineEdit:
	form_vbox.add_child(_lbl(label))
	var e := LineEdit.new(); e.placeholder_text = "leave empty to skip"
	form_vbox.add_child(e)
	return e

# ---------------------------------------------------------------------------
# Data I/O
# ---------------------------------------------------------------------------

func _load_data() -> void:
	file_name = file_name_input.text.strip_edges() if file_name_input else file_name
	if file_name.is_empty(): file_name = "ch1_dialogue"
	var user_path := SAVE_PATH + file_name + ".json"
	var res_path  := RES_PATH  + file_name + ".json"
	var path := user_path if FileAccess.file_exists(user_path) else res_path
	if not FileAccess.file_exists(path):
		_set_status("No file '%s' — starting blank" % file_name)
		all_data = {}
		_rebuild_dialogue_list()
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed := JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		_set_status("Parse error: " + path); return
	all_data = parsed
	_rebuild_dialogue_list()
	_set_status("Loaded: " + path)

func _save_data() -> void:
	if all_data.is_empty(): _set_status("Nothing to save"); return
	var path := SAVE_PATH + file_name + ".json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f: _set_status("ERROR: cannot write " + path); return
	f.store_string(JSON.stringify(all_data, "\t"))
	f.close()
	_set_status("Saved: " + path)

func _export_to_res() -> void:
	_save_data()
	var src := SAVE_PATH + file_name + ".json"
	if not FileAccess.file_exists(src): _set_status("Save first"); return
	var text := FileAccess.open(src, FileAccess.READ).get_as_text()
	var dst  := RES_PATH + file_name + ".json"
	var out  := FileAccess.open(dst, FileAccess.WRITE)
	if not out: _set_status("Export failed — cannot write " + dst); return
	out.store_string(text); out.close()
	_set_status("Exported → " + dst)

func _new_file() -> void:
	all_data = {}; file_name = "new_dialogue"
	if file_name_input: file_name_input.text = file_name
	sel_dialogue = ""; sel_node = ""
	_rebuild_dialogue_list(); _clear_node_list(); _clear_form()
	_set_status("New file — edit and Ctrl+S to save")

# ---------------------------------------------------------------------------
# Dialogue list
# ---------------------------------------------------------------------------

func _rebuild_dialogue_list() -> void:
	dialogue_list.clear()
	for k : String in all_data.keys():
		dialogue_list.add_item(k)
	if sel_dialogue != "" and all_data.has(sel_dialogue):
		var idx := all_data.keys().find(sel_dialogue)
		if idx >= 0: dialogue_list.select(idx); _rebuild_node_list()
	else:
		_clear_node_list(); _clear_form()

func _on_dialogue_selected(idx: int) -> void:
	sel_dialogue = dialogue_list.get_item_text(idx)
	sel_node = ""
	_rebuild_node_list(); _clear_form()
	_set_status("Dialogue: " + sel_dialogue)

func _add_dialogue() -> void:
	var id := "dialogue_%d" % (all_data.size() + 1)
	all_data[id] = { "nodes": {
		"start": { "speaker": "", "text": "...", "next": "end" },
		"end":   { "speaker": "", "text": "",    "next": ""   },
	}}
	_rebuild_dialogue_list()
	var idx := all_data.keys().find(id)
	if idx >= 0: dialogue_list.select(idx); _on_dialogue_selected(idx)
	_set_status("Created: " + id)

func _delete_dialogue() -> void:
	if sel_dialogue.is_empty(): return
	all_data.erase(sel_dialogue)
	sel_dialogue = ""; sel_node = ""
	_rebuild_dialogue_list(); _clear_form()
	_set_status("Deleted dialogue")

# ---------------------------------------------------------------------------
# Node list
# ---------------------------------------------------------------------------

func _rebuild_node_list() -> void:
	node_list.clear()
	if sel_dialogue.is_empty() or not all_data.has(sel_dialogue): return
	var nodes : Dictionary = all_data[sel_dialogue].get("nodes", {})
	for k : String in nodes.keys():
		node_list.add_item(k)
	if sel_node != "" and nodes.has(sel_node):
		var idx := nodes.keys().find(sel_node)
		if idx >= 0: node_list.select(idx); _load_node_into_form(sel_node)

func _clear_node_list() -> void:
	node_list.clear()

func _on_node_selected(idx: int) -> void:
	sel_node = node_list.get_item_text(idx)
	_load_node_into_form(sel_node)
	_set_status("Node: %s in %s" % [sel_node, sel_dialogue])

func _add_node() -> void:
	if sel_dialogue.is_empty(): _set_status("Select a dialogue first"); return
	var nodes : Dictionary = all_data[sel_dialogue].get("nodes", {})
	var id := "n%d" % nodes.size()
	nodes[id] = { "speaker": "", "text": "", "next": "end" }
	all_data[sel_dialogue]["nodes"] = nodes
	_rebuild_node_list()
	_set_status("Added node: " + id)

func _delete_node() -> void:
	if sel_node.is_empty() or sel_dialogue.is_empty(): return
	all_data[sel_dialogue].get("nodes", {}).erase(sel_node)
	sel_node = ""; _rebuild_node_list(); _clear_form()
	_set_status("Deleted node")

# ---------------------------------------------------------------------------
# Node editor form
# ---------------------------------------------------------------------------

func _load_node_into_form(node_id: String) -> void:
	if sel_dialogue.is_empty(): return
	var nodes : Dictionary = all_data[sel_dialogue].get("nodes", {})
	if not nodes.has(node_id): return
	var n : Dictionary = nodes[node_id]
	_loading = true
	node_id_edit.text  = node_id
	speaker_edit.text  = str(n.get("speaker", ""))
	text_edit.text     = str(n.get("text",    ""))
	next_edit.text     = str(n.get("next",    ""))
	fx_flag_edit.text  = str(n.get("set_flag",       ""))
	fx_sq_edit.text    = str(n.get("start_quest",    ""))
	fx_cq_edit.text    = str(n.get("complete_quest", ""))
	fx_item_edit.text  = str(n.get("give_item",      ""))
	var member : String = str(n.get("add_member", ""))
	var opts := ["(none)", "hero", "mage", "rogue"]
	fx_member_opt.selected = max(0, opts.find(member) if member != "" else 0)
	_loading = false
	_rebuild_choices_form(n.get("choices", []))

func _clear_form() -> void:
	if not node_id_edit: return
	_loading = true
	node_id_edit.text = ""; speaker_edit.text = ""; text_edit.text = ""
	next_edit.text    = ""; fx_flag_edit.text = ""; fx_sq_edit.text = ""
	fx_cq_edit.text   = ""; fx_item_edit.text = ""; fx_member_opt.selected = 0
	_loading = false
	for c in choices_vbox.get_children(): c.queue_free()

func _rebuild_choices_form(choices: Array) -> void:
	for c in choices_vbox.get_children(): c.queue_free()
	for ch in choices:
		_add_choice_row(str(ch.get("text", "")), str(ch.get("next", "")))

func _on_add_choice() -> void:
	_add_choice_row("Choice text", "end")

func _add_choice_row(ch_text: String, next_id: String) -> void:
	var row := HBoxContainer.new()
	choices_vbox.add_child(row)
	var te := LineEdit.new(); te.placeholder_text = "Choice text"
	te.text = ch_text; te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(te)
	var ne := LineEdit.new(); ne.placeholder_text = "next_id"
	ne.text = next_id; ne.custom_minimum_size = Vector2(80, 0)
	row.add_child(ne)
	var del := Button.new(); del.text = "✕"
	del.pressed.connect(func() -> void: row.queue_free())
	row.add_child(del)

func _apply_form() -> void:
	if sel_dialogue.is_empty() or sel_node.is_empty():
		_set_status("Select a node first"); return
	var new_id := node_id_edit.text.strip_edges()
	if new_id.is_empty(): _set_status("Node ID cannot be empty"); return
	var nodes : Dictionary = all_data[sel_dialogue].get("nodes", {})
	var data  : Dictionary = {
		"speaker": speaker_edit.text,
		"text":    text_edit.text,
		"next":    next_edit.text,
	}
	# Choices
	var choices : Array = []
	for row in choices_vbox.get_children():
		var ch := row.get_children()
		if ch.size() >= 2:
			var ct : String = (ch[0] as LineEdit).text
			var cn : String = (ch[1] as LineEdit).text
			if not ct.is_empty(): choices.append({"text": ct, "next": cn})
	if choices.size() > 0: data["choices"] = choices
	# Side effects
	if fx_flag_edit.text  != "": data["set_flag"]       = fx_flag_edit.text
	if fx_sq_edit.text    != "": data["start_quest"]    = fx_sq_edit.text
	if fx_cq_edit.text    != "": data["complete_quest"] = fx_cq_edit.text
	if fx_item_edit.text  != "": data["give_item"]      = fx_item_edit.text
	var member := fx_member_opt.get_item_text(fx_member_opt.selected)
	if member != "(none)":       data["add_member"]     = member
	# Rename support
	if new_id != sel_node: nodes.erase(sel_node)
	nodes[new_id] = data
	all_data[sel_dialogue]["nodes"] = nodes
	sel_node = new_id
	_rebuild_node_list()
	_set_status("Applied: " + new_id)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _lbl(text: String, bold: bool = false) -> Label:
	var l := Label.new(); l.text = text
	if bold: l.add_theme_font_size_override("font_size", 14)
	return l

func _btn(text: String, cb: Callable, parent: Node) -> Button:
	var b := Button.new(); b.text = text; b.pressed.connect(cb)
	parent.add_child(b); return b

func _set_status(msg: String) -> void:
	if status_bar: status_bar.text = msg
