extends Node2D

@onready var player:     CharacterBody2D = $Player
@onready var player_script: Node         = $Player
@onready var dialogue_box: Control       = $HUD/DialogueBox
@onready var dialogue_text: Label        = $HUD/DialogueBox/Panel/Text

func _ready() -> void:
	# Restore player position from save
	player.position = GameManager.player_position * GameManager.TILE_SIZE
	AudioManager.play_music("res://assets/audio/music/overworld_theme.ogg")

	StoryManager.dialogue_started.connect(_on_dialogue_started)
	StoryManager.dialogue_ended.connect(_on_dialogue_ended)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		SceneManager.go_to("main")
	if event.is_action_pressed("open_level_designer"):
		if OS.is_debug_build():
			SceneManager.go_to("level_designer")

func _on_dialogue_started(_id: String) -> void:
	dialogue_box.visible = true

func _on_dialogue_ended(_id: String) -> void:
	dialogue_box.visible = false
	dialogue_text.text   = ""

func show_dialogue_text(text: String) -> void:
	dialogue_text.text = text
