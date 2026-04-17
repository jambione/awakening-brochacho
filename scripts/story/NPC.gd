## NPC — base script for interactive non-player characters.
##
## Extends StaticBody2D so the Player's InteractRay (RayCast2D) can detect it.
## Set npc_id in the Inspector; StoryManager.get_dialogue_id() routes to the
## correct dialogue tree. Call set_dialogue_box() from Overworld to wire the
## shared DialoguePlayer before the scene is used.
extends StaticBody2D

@export var npc_id : String = ""

var _dialogue_box : DialoguePlayer = null

## Called by Overworld._ready() to inject the shared DialoguePlayer reference.
func set_dialogue_box(dp: DialoguePlayer) -> void:
	_dialogue_box = dp

func interact(_caller: Node = null) -> void:
	if _dialogue_box == null:
		push_error("NPC '%s': no DialoguePlayer set — call set_dialogue_box() first." % npc_id)
		return
	if npc_id == "":
		push_error("NPC has no npc_id set.")
		return
	var dialogue_id : String = StoryManager.get_dialogue_id(npc_id)
	if dialogue_id == "":
		return   ## NPC has nothing to say right now.
	_dialogue_box.play(dialogue_id)
