extends Node

@onready var new_game_btn:      Button = $UI/MainMenu/VBox/NewGame
@onready var continue_btn:      Button = $UI/MainMenu/VBox/Continue
@onready var level_designer_btn: Button = $UI/MainMenu/VBox/LevelDesigner
@onready var asset_painter_btn: Button = $UI/MainMenu/VBox/AssetPainter
@onready var quit_btn:          Button = $UI/MainMenu/VBox/Quit

func _ready() -> void:
	continue_btn.disabled = not GameManager.save_exists(0)

	new_game_btn.pressed.connect(_on_new_game)
	continue_btn.pressed.connect(_on_continue)
	level_designer_btn.pressed.connect(func(): SceneManager.go_to("level_designer"))
	asset_painter_btn.pressed.connect(func(): SceneManager.go_to("asset_painter"))
	quit_btn.pressed.connect(func(): get_tree().quit())

	# Inject designer tool buttons before Quit.
	var vbox : VBoxContainer = $UI/MainMenu/VBox
	for entry : Array in [
		["Dialogue Designer",     "dialogue_designer"],
		["Enemy Designer",        "enemy_designer"],
		["Item Designer",         "item_designer"],
		["Skill Designer",        "skill_designer"],
		["Quest Designer",        "quest_designer"],
		["Dungeon Room Designer", "room_designer"],
		["Animation Designer",    "anim_designer"],
	]:
		var btn := Button.new()
		btn.text = str(entry[0])
		var key := str(entry[1])
		btn.pressed.connect(func(): SceneManager.go_to(key))
		vbox.add_child(btn)
		vbox.move_child(btn, quit_btn.get_index())

	AudioManager.play_music("res://assets/audio/music/title_theme.ogg")

func _on_new_game() -> void:
	GameManager.new_game()
	SceneManager.go_to("overworld")

func _on_continue() -> void:
	if GameManager.load_game(0):
		SceneManager.go_to(GameManager.current_map)
