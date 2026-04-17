extends Node

# ── Signals ───────────────────────────────────────────────────────────────────
signal chapter_started(chapter_id: String)
signal dialogue_started(dialogue_id: String)
signal dialogue_ended(dialogue_id: String)
signal quest_updated(quest_id: String)

# ── State ─────────────────────────────────────────────────────────────────────
var current_chapter: String = "ch1_awakening"
var active_dialogue: String  = ""
var completed_dialogues: Array[String] = []
var quests: Dictionary = {}  # { quest_id: { status, objectives_done } }

# ── Chapter flow ──────────────────────────────────────────────────────────────
func start_chapter(chapter_id: String) -> void:
	current_chapter = chapter_id
	emit_signal("chapter_started", chapter_id)

# ── Dialogue ──────────────────────────────────────────────────────────────────
func start_dialogue(dialogue_id: String) -> void:
	active_dialogue = dialogue_id
	emit_signal("dialogue_started", dialogue_id)

func end_dialogue() -> void:
	if active_dialogue != "":
		completed_dialogues.append(active_dialogue)
	emit_signal("dialogue_ended", active_dialogue)
	active_dialogue = ""

func has_seen(dialogue_id: String) -> bool:
	return dialogue_id in completed_dialogues

func is_in_dialogue() -> bool:
	return active_dialogue != ""

# ── Quests ────────────────────────────────────────────────────────────────────
func start_quest(quest_id: String) -> void:
	if quest_id not in quests:
		quests[quest_id] = { "status": "active", "objectives_done": [] }
		emit_signal("quest_updated", quest_id)

func complete_objective(quest_id: String, objective: String) -> void:
	if quest_id in quests:
		var q: Dictionary = quests[quest_id]
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

# ── Serialization ─────────────────────────────────────────────────────────────
func serialize() -> Dictionary:
	return {
		"current_chapter":     current_chapter,
		"completed_dialogues": completed_dialogues,
		"quests":              quests,
	}

func deserialize(data: Dictionary) -> void:
	current_chapter     = data.get("current_chapter", "ch1_awakening")
	completed_dialogues = data.get("completed_dialogues", [])
	quests              = data.get("quests", {})

func reset() -> void:
	current_chapter     = "ch1_awakening"
	completed_dialogues = []
	quests              = {}
	active_dialogue     = ""
