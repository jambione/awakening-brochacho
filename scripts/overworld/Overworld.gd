## Overworld — Act 1 scene controller for Brochan Hold.
##
## Wires the shared DialoguePlayer to every NPC child, restores player
## position from save, and handles top-level input (menu, dev shortcuts).
extends Node2D

@onready var _player   : CharacterBody2D = $Player
@onready var _npcs     : Node2D          = $NPCs
@onready var _dialogue : DialoguePlayer  = $HUD/DialogueBox as DialoguePlayer

func _ready() -> void:
	# Restore player position from save data.
	_player.position = GameManager.player_position * float(GameManager.TILE_SIZE)

	# Inject the shared DialoguePlayer into every NPC in the scene.
	for child in _npcs.get_children():
		if child.has_method("set_dialogue_box"):
			child.set_dialogue_box(_dialogue)

	AudioManager.play_music_for_chapter(StoryManager.current_chapter)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		GameManager.save_game(0)
		SceneManager.go_to("main")
	if event.is_action_pressed("open_level_designer"):
		if OS.is_debug_build():
			SceneManager.go_to("level_designer")
