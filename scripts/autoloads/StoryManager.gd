## StoryManager — chapter flow, dialogue state, and quest tracking.
##
## Autoloaded as "StoryManager". DialoguePlayer calls start_dialogue /
## end_dialogue; everything else uses flags in GameManager for persistence.
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
var current_chapter      : String         = "ch1_awakening"
var active_dialogue      : String         = ""
var completed_dialogues  : Array[String]  = []
var quests               : Dictionary     = {}   ## { id: { status, objectives_done } }

# ---------------------------------------------------------------------------
# Chapter flow
# ---------------------------------------------------------------------------

func start_chapter(chapter_id: String) -> void:
	current_chapter = chapter_id
	emit_signal("chapter_started", chapter_id)

# ---------------------------------------------------------------------------
# Dialogue  (DialoguePlayer is the runtime; this tracks what has been seen)
# ---------------------------------------------------------------------------

## Call before showing a dialogue box. Locks player movement automatically
## because Player checks is_in_dialogue() in _physics_process.
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

## Return the appropriate dialogue id for an NPC, accounting for flags.
## This is the central routing function — add cases here as the story grows.
func get_dialogue_id(npc_id: String) -> String:
	match npc_id:
		"old_rufus":
			return "old_rufus_repeat" if GameManager.check_flag("met_rufus") else "old_rufus_intro"
		"mira":
			if GameManager.check_flag("mira_upgraded"):
				return ""   ## Mira has nothing new to say after the upgrade.
			return "mira_has_ingots" if GameManager.get_item_qty("copper_ingot") >= 3 else "mira_the_smith"
		"zara":
			return "" if GameManager.check_flag("zara_joined") else "zara_join"
		"slink":
			return "" if GameManager.check_flag("slink_joined") else "slink_join"
		_:
			return npc_id   ## Fall back to using the npc_id directly as dialogue_id.

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
	current_chapter     = str(data.get("current_chapter", "ch1_awakening"))
	completed_dialogues = data.get("completed_dialogues", [])
	quests              = data.get("quests", {})

func reset() -> void:
	current_chapter     = "ch1_awakening"
	completed_dialogues = []
	quests              = {}
	active_dialogue     = ""
