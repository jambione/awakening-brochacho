## EraManager — visual era system that evolves the game's look as chapters complete.
##
## Autoloaded as "EraManager". Sits above all other canvas layers (layer 100)
## and applies a full-screen post-process shader that simulates successive
## console eras: Atari → NES → GBC → SNES → PS1 → Modern.
##
## Era advances automatically when StoryManager emits chapter_started().
## Manual override: EraManager.set_era(EraManager.Era.NES)
extends Node

# ---------------------------------------------------------------------------
# Era enum  (int values are used as Dictionary keys)
# ---------------------------------------------------------------------------
enum Era { ATARI = 0, NES = 1, GBC = 2, SNES = 3, PS1 = 4, MODERN = 5 }

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal era_changed(new_era: Era)

# ---------------------------------------------------------------------------
# Era shader settings  (keys match shader uniform names minus the suffix)
# ---------------------------------------------------------------------------
const ERA_SETTINGS : Dictionary = {
	0: { "pixel_size": 4, "quantize": 1.0, "dither": 0.70, "scanline": 0.60, "flicker": 0.55 },
	1: { "pixel_size": 2, "quantize": 1.0, "dither": 0.40, "scanline": 0.38, "flicker": 0.00 },
	2: { "pixel_size": 2, "quantize": 1.0, "dither": 0.20, "scanline": 0.18, "flicker": 0.00 },
	3: { "pixel_size": 1, "quantize": 1.0, "dither": 0.08, "scanline": 0.08, "flicker": 0.00 },
	4: { "pixel_size": 1, "quantize": 0.30,"dither": 0.04, "scanline": 0.00, "flicker": 0.00 },
	5: { "pixel_size": 1, "quantize": 0.0, "dither": 0.00, "scanline": 0.00, "flicker": 0.00 },
}

## Maps chapter ids to the era that activates when that chapter starts.
const CHAPTER_ERA : Dictionary = {
	"ch1_the_hold"       : 0,   ## Era.ATARI  — boyhood, Brochan Hold
	"ch2_the_unmooring"  : 1,   ## Era.NES    — Jambione dies, young adult
	"ch3_the_seduction"  : 3,   ## Era.SNES   — prosperity, the lie (skip GBC — jump to vivid)
	"ch4_the_reckoning"  : 4,   ## Era.PS1    — betrayal revealed, harshness
	"ch5_the_embers"     : 2,   ## Era.GBC    — regression, world un-improves
	"ch6_the_awakening"  : 5,   ## Era.MODERN — full restoration
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var current_era  : Era             = Era.ATARI
var _material    : ShaderMaterial
var _overlay     : ColorRect
var _time        : float           = 0.0

## Per-era palettes — populated in _ready() to keep the const block readable.
var _palettes    : Dictionary      = {}

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_init_palettes()
	_build_overlay()
	_finish_apply(current_era)
	StoryManager.chapter_started.connect(_on_chapter_started)

func _process(delta: float) -> void:
	## Only animate the time uniform for eras that use flicker or scanlines.
	if current_era == Era.ATARI or current_era == Era.NES:
		_time += delta
		_material.set_shader_parameter("time_val", _time)

# ---------------------------------------------------------------------------
# Overlay construction
# ---------------------------------------------------------------------------

func _build_overlay() -> void:
	var shader_res : Resource = load("res://assets/shaders/era_post.gdshader")
	if not shader_res is Shader:
		push_error("EraManager: era_post.gdshader not found.")
		return

	_material         = ShaderMaterial.new()
	_material.shader  = shader_res as Shader

	_overlay              = ColorRect.new()
	_overlay.name         = "EraOverlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.material     = _material
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var layer : CanvasLayer = CanvasLayer.new()
	layer.name             = "EraLayer"
	layer.layer            = 100
	layer.add_child(_overlay)
	add_child(layer)

# ---------------------------------------------------------------------------
# Era management
# ---------------------------------------------------------------------------

func set_era(era: Era, animated: bool = true) -> void:
	if era == current_era:
		return
	var old_settings : Dictionary = _get_settings(current_era)
	var new_settings : Dictionary = _get_settings(era)
	var old_q        : float      = float(old_settings.get("quantize", 0.0))
	var new_q        : float      = float(new_settings.get("quantize", 0.0))
	current_era = era

	if animated and _material:
		var tw : Tween = create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.tween_method(_set_quantize, old_q, 0.0,   0.25)
		tw.tween_callback(_finish_apply.bind(era))
		tw.tween_method(_set_quantize, 0.0,   new_q, 0.40)
	else:
		_finish_apply(era)

	emit_signal("era_changed", era)

func _set_quantize(val: float) -> void:
	if _material:
		_material.set_shader_parameter("quantize_strength", val)

func _finish_apply(era: Era) -> void:
	if not _material:
		return
	var settings : Dictionary  = _get_settings(era)
	var palette  : Array       = _padded_palette(era)
	_material.set_shader_parameter("pixel_size",        int(settings.get("pixel_size", 1)))
	_material.set_shader_parameter("dither_strength",   float(settings.get("dither",   0.0)))
	_material.set_shader_parameter("scanline_strength", float(settings.get("scanline", 0.0)))
	_material.set_shader_parameter("flicker_strength",  float(settings.get("flicker",  0.0)))
	_material.set_shader_parameter("quantize_strength", float(settings.get("quantize", 0.0)))
	var raw_palette : Variant = _palettes.get(int(era), [])
	var pal_arr     : Array   = raw_palette if raw_palette is Array else []
	_material.set_shader_parameter("palette_size", min(pal_arr.size(), 32))
	_material.set_shader_parameter("palette",      palette)

func _on_chapter_started(chapter_id: String) -> void:
	if not CHAPTER_ERA.has(chapter_id):
		return
	var era_int : Variant = CHAPTER_ERA[chapter_id]
	if era_int is int:
		set_era(era_int as Era)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _get_settings(era: Era) -> Dictionary:
	var raw : Variant = ERA_SETTINGS.get(int(era), {})
	return raw if raw is Dictionary else {}

func _padded_palette(era: Era) -> Array:
	var raw    : Variant = _palettes.get(int(era), [])
	var colors : Array   = raw if raw is Array else []
	var result : Array   = colors.duplicate()
	var fill   : Color   = Color.BLACK
	if not result.is_empty():
		var last : Variant = result[result.size() - 1]
		if last is Color:
			fill = last as Color
	while result.size() < 32:
		result.append(fill)
	return result

func era_name() -> String:
	match current_era:
		Era.ATARI:  return "Atari 2600"
		Era.NES:    return "NES"
		Era.GBC:    return "Game Boy Color"
		Era.SNES:   return "SNES"
		Era.PS1:    return "PlayStation"
		Era.MODERN: return "Modern"
	return ""

# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

func serialize() -> Dictionary:
	return { "era": int(current_era) }

func deserialize(data: Dictionary) -> void:
	var era_int : int = int(data.get("era", 0))
	var clamped : int = clamp(era_int, 0, 5)
	current_era = clamped as Era
	_finish_apply(current_era)

func reset() -> void:
	current_era = Era.ATARI
	_finish_apply(current_era)

# ---------------------------------------------------------------------------
# Palette definitions
# ---------------------------------------------------------------------------

func _init_palettes() -> void:
	## Atari 2600 — four grey shades with a hint of sepia warmth.
	_palettes[0] = [
		Color("#0a0800"), Color("#3d3830"), Color("#8a8070"), Color("#e8dfc8"),
	]

	## NES — 16 entries drawn from the canonical NES palette.
	_palettes[1] = [
		Color("#000000"), Color("#fcfcfc"), Color("#f83800"), Color("#fc7460"),
		Color("#fc9838"), Color("#fce058"), Color("#00b800"), Color("#007800"),
		Color("#3cbcfc"), Color("#0078f8"), Color("#0000fc"), Color("#6844fc"),
		Color("#940084"), Color("#f878f8"), Color("#7c7c7c"), Color("#bcbcbc"),
	]

	## Game Boy Color — 20 colours; slightly more vibrant, warmer tones.
	_palettes[2] = [
		Color("#000000"), Color("#ffffff"), Color("#e82020"), Color("#f87830"),
		Color("#f8c800"), Color("#30d030"), Color("#00a800"), Color("#00c8c0"),
		Color("#3080f8"), Color("#1820c0"), Color("#8040f8"), Color("#c000c0"),
		Color("#f880c0"), Color("#804010"), Color("#c87830"), Color("#808080"),
		Color("#c0c0c0"), Color("#78f8c0"), Color("#78c0f8"), Color("#f8c078"),
	]

	## SNES — 28 entries covering the iconic Mode-7 colour range.
	_palettes[3] = [
		Color("#000000"), Color("#fcfcfc"), Color("#f83800"), Color("#fc7460"),
		Color("#fc9838"), Color("#fce058"), Color("#00b800"), Color("#007800"),
		Color("#00e8d8"), Color("#3cbcfc"), Color("#0078f8"), Color("#0000fc"),
		Color("#b800f8"), Color("#f800b8"), Color("#f85898"), Color("#fc3868"),
		Color("#803020"), Color("#c06820"), Color("#f0d050"), Color("#c8f060"),
		Color("#58d854"), Color("#58f898"), Color("#78c8f8"), Color("#7c7c7c"),
		Color("#bcbcbc"), Color("#f8b8f8"), Color("#f8a070"), Color("#b8f818"),
	]

	## PS1 — 32 entries; rich full spectrum, barely any restriction.
	_palettes[4] = [
		Color("#000000"), Color("#1a1a2e"), Color("#16213e"), Color("#0f3460"),
		Color("#533483"), Color("#e94560"), Color("#f5a623"), Color("#f8e71c"),
		Color("#7ed321"), Color("#417505"), Color("#4a90d9"), Color("#0079bf"),
		Color("#ffffff"), Color("#d8d8d8"), Color("#9b9b9b"), Color("#4a4a4a"),
		Color("#c0392b"), Color("#e74c3c"), Color("#e67e22"), Color("#f39c12"),
		Color("#27ae60"), Color("#2ecc71"), Color("#2980b9"), Color("#3498db"),
		Color("#8e44ad"), Color("#9b59b6"), Color("#1abc9c"), Color("#16a085"),
		Color("#f1c40f"), Color("#d35400"), Color("#7f8c8d"), Color("#bdc3c7"),
	]

	## Modern — not used for quantisation (quantize_strength = 0.0).
	_palettes[5] = []
