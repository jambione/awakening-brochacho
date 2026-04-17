extends Node

# ── Signals ───────────────────────────────────────────────────────────────────
signal scene_transition_started(to_scene: String)
signal scene_transition_finished(to_scene: String)

# ── Scene paths ───────────────────────────────────────────────────────────────
const SCENES := {
	"main":          "res://scenes/main/Main.tscn",
	"overworld":     "res://scenes/overworld/Overworld.tscn",
	"dungeon":       "res://scenes/dungeon/Dungeon.tscn",
	"combat":        "res://scenes/combat/Combat.tscn",
	"level_designer":"res://scenes/tools/LevelDesigner.tscn",
	"asset_painter": "res://scenes/tools/AssetPainter.tscn",
}

# ── Transition overlay ────────────────────────────────────────────────────────
var _overlay: ColorRect
var _transitioning: bool = false

func _ready() -> void:
	_overlay = ColorRect.new()
	_overlay.color = Color.BLACK
	_overlay.modulate.a = 0.0
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	move_child(_overlay, get_child_count() - 1)

# ── Public API ────────────────────────────────────────────────────────────────
func go_to(scene_key: String, fade_duration: float = 0.4) -> void:
	if _transitioning:
		return
	var path: String = SCENES.get(scene_key, scene_key)
	_transition_to(path, fade_duration)

func go_to_dungeon(seed_value: int = -1) -> void:
	if seed_value >= 0:
		GameManager.dungeon_seed = seed_value
	else:
		GameManager.dungeon_seed = randi()
	go_to("dungeon")

func go_to_combat(enemy_group: Array) -> void:
	# Store the encounter data for the Combat scene to pick up
	get_tree().set_meta("combat_enemies", enemy_group)
	go_to("combat")

# ── Internal ──────────────────────────────────────────────────────────────────
func _transition_to(path: String, duration: float) -> void:
	_transitioning = true
	emit_signal("scene_transition_started", path)

	var tween := create_tween()
	tween.tween_property(_overlay, "modulate:a", 1.0, duration * 0.5)
	tween.tween_callback(func():
		get_tree().change_scene_to_file(path)
	)
	tween.tween_interval(0.05)
	tween.tween_property(_overlay, "modulate:a", 0.0, duration * 0.5)
	tween.tween_callback(func():
		_transitioning = false
		emit_signal("scene_transition_finished", path)
	)
