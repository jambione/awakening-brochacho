## SceneManager — fade-transition scene switcher.
##
## Autoloaded as "SceneManager". Call SceneManager.go_to("dungeon") from
## anywhere; the black overlay fades out, the scene changes, then fades in.
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal transition_started(to_scene: String)
signal transition_finished(to_scene: String)

# ---------------------------------------------------------------------------
# Scene registry  —  add new scenes here; use the key as the argument to go_to.
# ---------------------------------------------------------------------------
const SCENES : Dictionary = {
	"main"               : "res://scenes/main/Main.tscn",
	"overworld"          : "res://scenes/overworld/Overworld.tscn",
	"dungeon"            : "res://scenes/dungeon/Dungeon.tscn",
	"combat"             : "res://scenes/combat/Combat.tscn",
	"level_designer"     : "res://scenes/tools/LevelDesigner.tscn",
	"asset_painter"      : "res://scenes/tools/AssetPainter.tscn",
	"dialogue_designer"  : "res://scenes/tools/DialogueDesigner.tscn",
	"enemy_designer"     : "res://scenes/tools/EnemyDesigner.tscn",
	"item_designer"      : "res://scenes/tools/ItemDesigner.tscn",
	"skill_designer"     : "res://scenes/tools/SkillDesigner.tscn",
	"quest_designer"     : "res://scenes/tools/QuestDesigner.tscn",
	"room_designer"      : "res://scenes/tools/DungeonRoomDesigner.tscn",
	"anim_designer"      : "res://scenes/tools/AnimationDesigner.tscn",
}

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------
var _overlay      : ColorRect
var _transitioning: bool = false

func _ready() -> void:
	# The overlay lives on SceneManager itself so it survives scene changes.
	_overlay                = ColorRect.new()
	_overlay.color          = Color.BLACK
	_overlay.modulate.a     = 0.0
	_overlay.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Transition to a named scene (key in SCENES) or a direct "res://" path.
func go_to(scene_key: String, fade: float = 0.35) -> void:
	if _transitioning:
		return
	var path : String = SCENES.get(scene_key, scene_key)
	_do_transition(path, fade)

## Convenience: roll a new dungeon seed and go to the dungeon scene.
func go_to_dungeon(seed_value: int = -1) -> void:
	if seed_value >= 0:
		GameManager.dungeon_seed = seed_value
	else:
		GameManager.dungeon_seed = randi()
	go_to("dungeon")

## Convenience: stash an enemy group and enter combat.
func go_to_combat(enemy_group: Array) -> void:
	get_tree().set_meta("combat_enemies", enemy_group)
	go_to("combat")

# ---------------------------------------------------------------------------
# Internal transition
# ---------------------------------------------------------------------------

func _do_transition(path: String, fade: float) -> void:
	_transitioning = true
	emit_signal("transition_started", path)

	# Move overlay on top of everything.
	move_child(_overlay, get_child_count() - 1)

	var tween : Tween = create_tween()
	# Fade to black.
	tween.tween_property(_overlay, "modulate:a", 1.0, fade * 0.5)
	# Change the scene while it is fully black.
	tween.tween_callback(func() -> void:
		get_tree().change_scene_to_file(path)
	)
	tween.tween_interval(0.05)
	# Fade back in.
	tween.tween_property(_overlay, "modulate:a", 0.0, fade * 0.5)
	tween.tween_callback(func() -> void:
		_transitioning = false
		emit_signal("transition_finished", path)
	)
