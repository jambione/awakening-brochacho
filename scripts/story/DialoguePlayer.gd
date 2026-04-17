## DialoguePlayer — drives a branching dialogue tree from JSON data.
##
## Attach to a DialogueBox Control node.  Call play(dialogue_id) to start.
## The player advances lines with the Interact button; choices appear as
## clickable buttons when a "choices" key is present on a node.
##
## JSON node schema:
##   speaker        : String   (displayed name)
##   text           : String   (the line to display; supports BBCode)
##   next           : String   (node id to go to automatically)
##   choices        : Array    (optional — each entry has "text" + "next")
##   set_flag       : String   (optional — sets a GameManager flag to true)
##   start_quest    : String   (optional — calls StoryManager.start_quest)
##   complete_quest : String   (optional — calls StoryManager.complete_quest)
##   add_member     : String   (optional — adds a party member by template id)
##   give_item      : String   (optional — adds one item to inventory)
extends Control
class_name DialoguePlayer

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal dialogue_finished

# ---------------------------------------------------------------------------
# Node references — must match DialogueBox.tscn layout.
# ---------------------------------------------------------------------------
@onready var speaker_label  : Label         = $Panel/VBox/SpeakerLabel
@onready var text_label     : RichTextLabel = $Panel/VBox/TextLabel
@onready var choices_root   : VBoxContainer = $Panel/VBox/ChoicesRoot
@onready var advance_hint   : Label         = $Panel/VBox/AdvanceHint

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _tree     : Dictionary = {}   ## The full node dictionary for this dialogue.
var _cur_id   : String     = ""   ## Currently displayed node id.
var _active   : bool       = false

func _ready() -> void:
	# Accept touch/mouse so _gui_input fires for tap-to-advance.
	mouse_filter = Control.MOUSE_FILTER_STOP

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Load and begin a dialogue. `dialogue_id` is a top-level key in the JSON.
func play(dialogue_id: String) -> void:
	var tree : Dictionary = _load_dialogue_file(dialogue_id)
	if tree.is_empty():
		push_error("DialoguePlayer: no dialogue '%s'" % dialogue_id)
		return
	_tree   = tree
	_active = true
	visible = true
	StoryManager.start_dialogue(dialogue_id)
	_show_node("start")

func stop() -> void:
	_active = false
	visible = false
	for child in choices_root.get_children():
		child.queue_free()
	StoryManager.end_dialogue()
	emit_signal("dialogue_finished")

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	# Keyboard / gamepad advance.
	if event.is_action_pressed("interact"):
		if choices_root.get_child_count() == 0:
			_advance()
			get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	# Tap anywhere on the dialogue panel to advance (mobile tap-to-advance).
	if not _active:
		return
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		if choices_root.get_child_count() == 0:
			_advance()
			accept_event()

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _load_dialogue_file(dialogue_id: String) -> Dictionary:
	var path : String = "res://data/story/ch1_dialogue.json"
	# Future chapters: look up path from StoryManager.current_chapter or a registry.
	if not FileAccess.file_exists(path):
		push_error("DialoguePlayer: dialogue file not found at %s" % path)
		return {}
	var file   : FileAccess = FileAccess.open(path, FileAccess.READ)
	var result : Variant    = JSON.parse_string(file.get_as_text())
	file.close()
	if not result is Dictionary:
		return {}
	var root : Dictionary = result
	if not root.has(dialogue_id):
		return {}
	var entry : Dictionary = root[dialogue_id]
	return entry.get("nodes", {})

func _show_node(node_id: String) -> void:
	_cur_id = node_id
	if not _tree.has(node_id):
		stop()
		return

	var node : Dictionary = _tree[node_id]

	# Empty node = end of dialogue.
	var speaker : String = str(node.get("speaker", ""))
	var text    : String = str(node.get("text",    ""))
	if text.is_empty() and speaker.is_empty():
		_apply_side_effects(node)
		stop()
		return

	# Update UI.
	if speaker_label:
		speaker_label.text    = speaker
		speaker_label.visible = speaker != ""
	if text_label:
		text_label.text = text

	# Clear old choices.
	for child in choices_root.get_children():
		child.queue_free()

	var choices : Variant = node.get("choices", null)
	if choices is Array and (choices as Array).size() > 0:
		# Show choice buttons — player must click one.
		if advance_hint:
			advance_hint.visible = false
		for c in (choices as Array):
			var btn : Button = Button.new()
			btn.text = str(c.get("text", "..."))
			btn.custom_minimum_size   = Vector2(0, 56)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var next_id : String = str(c.get("next", "end"))
			btn.pressed.connect(_on_choice_pressed.bind(next_id))
			choices_root.add_child(btn)
	else:
		# Auto-advance: show the "Press Z" hint.
		if advance_hint:
			advance_hint.visible = true

	_apply_side_effects(node)

func _advance() -> void:
	if not _tree.has(_cur_id):
		stop()
		return
	var node    : Dictionary = _tree[_cur_id]
	var next_id : String     = str(node.get("next", ""))
	if next_id == "" or next_id == "end":
		stop()
	else:
		_show_node(next_id)

func _on_choice_pressed(next_id: String) -> void:
	for child in choices_root.get_children():
		child.queue_free()
	if next_id == "" or next_id == "end":
		stop()
	else:
		_show_node(next_id)

## Process non-display side-effects declared on a dialogue node.
func _apply_side_effects(node: Dictionary) -> void:
	var set_flag       : String = str(node.get("set_flag",       ""))
	var start_quest    : String = str(node.get("start_quest",    ""))
	var complete_quest : String = str(node.get("complete_quest", ""))
	var add_member     : String = str(node.get("add_member",     ""))
	var give_item      : String = str(node.get("give_item",      ""))

	if set_flag       != "": GameManager.set_flag(set_flag)
	if start_quest    != "": StoryManager.start_quest(start_quest)
	if complete_quest != "": StoryManager.complete_quest(complete_quest)
	if add_member     != "": PartyManager.add_member(add_member)
	if give_item      != "":
		GameManager.add_item({ "id": give_item, "name": give_item.capitalize(), "qty": 1, "type": "equipment" })
