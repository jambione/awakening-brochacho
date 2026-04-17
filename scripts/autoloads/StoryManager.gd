## StoryManager — chapter flow, dialogue routing, and quest tracking.
##
## Autoloaded as "StoryManager".
## DialoguePlayer calls start_dialogue / end_dialogue.
## All flag checks go through GameManager for persistence.
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal chapter_started(chapter_id: String)
signal dialogue_started(dialogue_id: String)
signal dialogue_ended(dialogue_id: String)
signal quest_updated(quest_id: String)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var current_chapter     : String        = "ch1_the_hold"
var active_dialogue     : String        = ""
var completed_dialogues : Array[String] = []
var quests              : Dictionary    = {}   ## { id: { status, objectives_done } }

# ---------------------------------------------------------------------------
# Chapter flow
# ---------------------------------------------------------------------------

func start_chapter(chapter_id: String) -> void:
	current_chapter = chapter_id
	emit_signal("chapter_started", chapter_id)

# ---------------------------------------------------------------------------
# Dialogue  (DialoguePlayer is the runtime; this tracks what was seen)
# ---------------------------------------------------------------------------

## Lock player movement — Player checks is_in_dialogue() in _physics_process.
func start_dialogue(dialogue_id: String) -> void:
	active_dialogue = dialogue_id
	emit_signal("dialogue_started", dialogue_id)

func end_dialogue() -> void:
	if active_dialogue != "":
		if active_dialogue not in completed_dialogues:
			completed_dialogues.append(active_dialogue)
	emit_signal("dialogue_ended", active_dialogue)
	active_dialogue = ""

func is_in_dialogue() -> bool:
	return active_dialogue != ""

func has_seen(dialogue_id: String) -> bool:
	return dialogue_id in completed_dialogues

# ---------------------------------------------------------------------------
# NPC dialogue routing
# ---------------------------------------------------------------------------

## Central routing function — maps npc_id to the correct dialogue tree id.
## Add cases here as the story grows.
func get_dialogue_id(npc_id: String) -> String:
	match npc_id:

		## --- Act 1: Brochan Hold ---
		"jambione":
			if not GameManager.check_flag("met_jambione"):
				return "jambione_intro"
			if GameManager.check_flag("met_cassin") and not GameManager.check_flag("jambione_warned_cassin"):
				return "jambione_cassin_warning"
			if GameManager.check_flag("act1_boundary_complete"):
				return "act1_complete"
			return "jambione_repeat"

		"jesse":
			return "jesse_repeat" if GameManager.check_flag("met_jesse") else "jesse_intro"

		"cassin":
			return "cassin_repeat" if GameManager.check_flag("met_cassin") else "cassin_intro"

		## --- Future acts (stubs) ---
		"jordan":
			return ""   ## Not yet implemented.

		_:
			return npc_id   ## Fall back to using npc_id directly as dialogue_id.

# ---------------------------------------------------------------------------
# Quests
# ---------------------------------------------------------------------------

func start_quest(quest_id: String) -> void:
	if quest_id not in quests:
		quests[quest_id] = { "status": "active", "objectives_done": [] }
		emit_signal("quest_updated", quest_id)

func complete_objective(quest_id: String, objective: String) -> void:
	if quest_id in quests:
		var q : Dictionary = quests[quest_id]
		if objective not in q.objectives_done:
			q.objectives_done.append(objective)
			emit_signal("quest_updated", quest_id)

func complete_quest(quest_id: String) -> void:
	if quest_id in quests:
		quests[quest_id].status = "completed"
		emit_signal("quest_updated", quest_id)

func is_quest_active(quest_id: String) -> bool:
	return quests.get(quest_id, {}).get("status", "") == "active"

func is_quest_done(quest_id: String) -> bool:
	return quests.get(quest_id, {}).get("status", "") == "completed"

# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"current_chapter"     : current_chapter,
		"completed_dialogues" : completed_dialogues,
		"quests"              : quests,
	}

func deserialize(data: Dictionary) -> void:
	current_chapter     = str(data.get("current_chapter", "ch1_the_hold"))
	completed_dialogues = _load_string_array(data.get("completed_dialogues", []))
	quests              = data.get("quests", {}) if data.get("quests", null) is Dictionary else {}

func _load_string_array(raw: Variant) -> Array[String]:
	var result : Array[String] = []
	if not raw is Array:
		return result
	for item : Variant in (raw as Array):
		result.append(str(item))
	return result

func reset() -> void:
	current_chapter     = "ch1_the_hold"
	completed_dialogues = []
	quests              = {}
	active_dialogue     = ""
