## NPC — base script for interactive non-player characters.
##
## Place on a CharacterBody2D or StaticBody2D with a collision shape.
## Set `npc_id` in the Inspector; StoryManager routes it to the correct dialogue.
##
## Requires a DialogueBox node in the scene (or autoloaded).
## Reads the path from `dialogue_box_path` or falls back to a scene-tree search.
extends Node2D

@export var npc_id          : String = ""
@export var dialogue_box_path: NodePath

@onready var _dialogue_box : DialoguePlayer = _find_dialogue_box()

func _find_dialogue_box() -> DialoguePlayer:
	if not dialogue_box_path.is_empty():
		return get_node(dialogue_box_path) as DialoguePlayer
	# Fall back: search the current scene for any DialoguePlayer.
	var hits : Array = get_tree().get_nodes_in_group("dialogue_box")
	if not hits.is_empty():
		return hits[0] as DialoguePlayer
	return null

func interact() -> void:
	if _dialogue_box == null:
		push_error("NPC '%s': no DialoguePlayer found." % npc_id)
		return
	var dialogue_id : String = StoryManager.get_dialogue_id(npc_id)
	if dialogue_id == "":
		return   ## NPC has nothing to say right now.
	_dialogue_box.play(dialogue_id)
