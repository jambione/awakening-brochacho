## AudioManager — music, SFX, haptics, and era-aware audio bus effects.
##
## Music vision: Diablo II — Matt Uelmen's Spanish guitar fingerpicking
## over dark orchestral pads and ambient dread. Each chapter has a distinct
## track; transitions crossfade over 2 seconds so scene changes feel cinematic.
##
## Era audio: the Music bus gains a lowpass filter (Atari→GBC = lo-fi),
## which rolls off high frequencies to match the era's visual fidelity.
## SNES and PS1 layers in reverb; Modern is full-fidelity clean.
##
## SFX: addressed by string ID (e.g. "interact", "footstep_grass").
##      play_sfx() no-ops gracefully if the file doesn't exist yet — drop
##      the .ogg files in assets/audio/sfx/ and they are picked up automatically.
extends Node

# ---------------------------------------------------------------------------
# Music track manifest  —  chapter_id → .ogg path
# ---------------------------------------------------------------------------
##
## Recommended Uelmen-style production notes per track:
##   ch1 — "Brochan Hold": solo acoustic Spanish guitar, Amin → Dm arpeggios,
##          sparse hand percussion.  Think Tristram Village.
##   ch2 — "The Unmooring": guitar fades mid-phrase, strings enter dissonant,
##          unresolved cadence.  Loss.
##   ch3 — "The Seduction": faux-elegant harpsichord, Settlement motif,
##          underneath the guitar theme plays out of phase with itself.
##   ch4 — "The Reckoning": full orchestral tension, driving low strings,
##          brass stabs, the Settlement motif inverted and ugly.
##   ch5 — "The Embers": single aged guitar, slower tempo, no percussion,
##          Brochacho's theme reduced to three notes.
##   ch6 — "The Awakening": guitar returns full force, orchestra swells,
##          Brochan Hold theme recapitulated triumphantly.
##
const CHAPTER_MUSIC : Dictionary = {
	"ch1_the_hold"      : "res://assets/audio/music/ch1_brochan_hold.ogg",
	"ch2_the_unmooring" : "res://assets/audio/music/ch2_the_unmooring.ogg",
	"ch3_the_seduction" : "res://assets/audio/music/ch3_the_seduction.ogg",
	"ch4_the_reckoning" : "res://assets/audio/music/ch4_the_reckoning.ogg",
	"ch5_the_embers"    : "res://assets/audio/music/ch5_the_embers.ogg",
	"ch6_the_awakening" : "res://assets/audio/music/ch6_the_awakening.ogg",
}

# ---------------------------------------------------------------------------
# SFX manifest  —  sfx_id → .ogg path
# ---------------------------------------------------------------------------
const SFX : Dictionary = {
	# Movement
	"footstep_grass"  : "res://assets/audio/sfx/footstep_grass.ogg",
	"footstep_stone"  : "res://assets/audio/sfx/footstep_stone.ogg",
	"footstep_wood"   : "res://assets/audio/sfx/footstep_wood.ogg",
	# Interaction
	"interact"        : "res://assets/audio/sfx/interact.ogg",
	"chest_open"      : "res://assets/audio/sfx/chest_open.ogg",
	"door_open"       : "res://assets/audio/sfx/door_open.ogg",
	# Dialogue
	"dialogue_open"   : "res://assets/audio/sfx/dialogue_open.ogg",
	"dialogue_next"   : "res://assets/audio/sfx/dialogue_next.ogg",
	"dialogue_close"  : "res://assets/audio/sfx/dialogue_close.ogg",
	# Inventory / items
	"item_pickup"     : "res://assets/audio/sfx/item_pickup.ogg",
	"item_equip"      : "res://assets/audio/sfx/item_equip.ogg",
	"gold_pickup"     : "res://assets/audio/sfx/gold_pickup.ogg",
	# Quests
	"quest_start"     : "res://assets/audio/sfx/quest_start.ogg",
	"quest_complete"  : "res://assets/audio/sfx/quest_complete.ogg",
	# UI
	"menu_open"       : "res://assets/audio/sfx/menu_open.ogg",
	"menu_close"      : "res://assets/audio/sfx/menu_close.ogg",
	"button_confirm"  : "res://assets/audio/sfx/button_confirm.ogg",
	"button_cancel"   : "res://assets/audio/sfx/button_cancel.ogg",
	# Era
	"era_transition"  : "res://assets/audio/sfx/era_transition.ogg",
	# Combat
	"sword_swing"     : "res://assets/audio/sfx/sword_swing.ogg",
	"hit_impact"      : "res://assets/audio/sfx/hit_impact.ogg",
	"player_hurt"     : "res://assets/audio/sfx/player_hurt.ogg",
	"enemy_death"     : "res://assets/audio/sfx/enemy_death.ogg",
	# Dungeon
	"dungeon_descend" : "res://assets/audio/sfx/dungeon_descend.ogg",
}

# ---------------------------------------------------------------------------
# Era bus settings  —  indexed by EraManager era int (0=ATARI … 5=MODERN)
# ---------------------------------------------------------------------------
## Each entry: { filter_hz, reverb_wet, reverb_room }
## filter_hz = lowpass cutoff; values above ~18000 are effectively off.
const ERA_AUDIO : Array[Dictionary] = [
	{ "filter_hz": 2200.0,  "reverb_wet": 0.0,  "reverb_room": 0.0  },  # ATARI
	{ "filter_hz": 4000.0,  "reverb_wet": 0.0,  "reverb_room": 0.0  },  # NES
	{ "filter_hz": 7000.0,  "reverb_wet": 0.0,  "reverb_room": 0.0  },  # GBC
	{ "filter_hz": 18000.0, "reverb_wet": 0.15, "reverb_room": 0.35 },  # SNES
	{ "filter_hz": 18000.0, "reverb_wet": 0.28, "reverb_room": 0.55 },  # PS1
	{ "filter_hz": 22000.0, "reverb_wet": 0.0,  "reverb_room": 0.0  },  # MODERN
]

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const SFX_POOL_SIZE    : int   = 8
const CROSSFADE_TIME   : float = 2.0  ## Seconds to blend between music tracks.

# ---------------------------------------------------------------------------
# Node pool
# ---------------------------------------------------------------------------
## A/B players for crossfade — we ping-pong between them.
var _music_a     : AudioStreamPlayer
var _music_b     : AudioStreamPlayer
var _music_hot   : AudioStreamPlayer   ## Whichever player is currently audible.
var _sfx_pool    : Array[AudioStreamPlayer] = []

# ---------------------------------------------------------------------------
# Bus effect handles (set up once in _ready, tweaked per era)
# ---------------------------------------------------------------------------
var _music_bus_idx  : int = -1
var _filter_idx     : int = -1  ## Index of AudioEffectFilter in Music bus.
var _reverb_idx     : int = -1  ## Index of AudioEffectReverb in Music bus.

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _current_music : String = ""

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_music_bus_idx = AudioServer.get_bus_index("Music")

	_music_a = _make_music_player()
	_music_b = _make_music_player()
	_music_hot = _music_a

	for _i : int in SFX_POOL_SIZE:
		var p : AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)

	_setup_era_effects()
	_apply_volumes()

	GameManager.settings_changed.connect(_apply_volumes)
	StoryManager.chapter_started.connect(_on_chapter_started)
	EraManager.era_changed.connect(_on_era_changed)

func _make_music_player() -> AudioStreamPlayer:
	var p : AudioStreamPlayer = AudioStreamPlayer.new()
	p.bus = "Music"
	add_child(p)
	return p

# ---------------------------------------------------------------------------
# Bus setup helpers
# ---------------------------------------------------------------------------

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx : int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")

## Add a lowpass filter and reverb to the Music bus so we can tweak them per era.
func _setup_era_effects() -> void:
	if _music_bus_idx == -1:
		return

	var lp : AudioEffectFilter = AudioEffectFilter.new()
	lp.cutoff_hz = 22000.0
	lp.resonance = 0.5
	AudioServer.add_bus_effect(_music_bus_idx, lp)
	_filter_idx = AudioServer.get_bus_effect_count(_music_bus_idx) - 1

	var rv : AudioEffectReverb = AudioEffectReverb.new()
	rv.wet    = 0.0
	rv.room_size = 0.0
	AudioServer.add_bus_effect(_music_bus_idx, rv)
	_reverb_idx = AudioServer.get_bus_effect_count(_music_bus_idx) - 1

	# Boot in Act 1 era (ATARI/NES will be set when EraManager fires).
	_apply_era_effects(EraManager.current_era)

func _apply_volumes() -> void:
	var music_idx : int = AudioServer.get_bus_index("Music")
	var sfx_idx   : int = AudioServer.get_bus_index("SFX")
	if music_idx != -1:
		AudioServer.set_bus_volume_db(music_idx,
			linear_to_db(float(GameManager.settings.get("music_volume", 0.7))))
	if sfx_idx != -1:
		AudioServer.set_bus_volume_db(sfx_idx,
			linear_to_db(float(GameManager.settings.get("sfx_volume", 0.8))))

# ---------------------------------------------------------------------------
# Music — crossfade A/B
# ---------------------------------------------------------------------------

## Play music for a specific chapter (looks up CHAPTER_MUSIC).
func play_music_for_chapter(chapter_id: String) -> void:
	var path : String = CHAPTER_MUSIC.get(chapter_id, "")
	if path == "":
		return
	crossfade_to(path)

## Start `path` immediately (no crossfade) — use for scene boot.
func play_music(path: String, loop: bool = true) -> void:
	if path == _current_music:
		return
	_load_and_play(_music_hot, path, loop)
	_current_music = path
	# Silence the cold player in case it was still fading.
	var cold : AudioStreamPlayer = _cold_player()
	cold.stop()
	cold.volume_db = 0.0

## Blend from the current track to `path` over CROSSFADE_TIME.
func crossfade_to(path: String, duration: float = CROSSFADE_TIME) -> void:
	if path == _current_music:
		return
	_current_music = path

	var hot  : AudioStreamPlayer = _music_hot
	var cold : AudioStreamPlayer = _cold_player()

	if not _load_and_play(cold, path, true):
		return  # File doesn't exist yet — silently skip.

	cold.volume_db = -80.0
	_music_hot     = cold

	var tween : Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(hot,  "volume_db", -80.0, duration)
	tween.tween_property(cold, "volume_db",   0.0, duration)
	tween.tween_callback(hot.stop).set_delay(duration)

func stop_music() -> void:
	_music_hot.stop()
	_cold_player().stop()
	_current_music = ""

func fade_out(duration: float = 1.5) -> void:
	var tween : Tween = create_tween()
	tween.tween_property(_music_hot, "volume_db", -80.0, duration)
	tween.tween_callback(stop_music).set_delay(duration)

func _cold_player() -> AudioStreamPlayer:
	return _music_b if _music_hot == _music_a else _music_a

func _load_and_play(player: AudioStreamPlayer, path: String, loop: bool) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var stream : AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	player.stream    = stream
	player.volume_db = 0.0
	player.play()
	return true

# ---------------------------------------------------------------------------
# SFX
# ---------------------------------------------------------------------------

## Play a named sound effect.  No-ops silently if the file isn't present yet.
func play_sfx(sfx_id: String) -> void:
	var path : String = SFX.get(sfx_id, "")
	if path == "" or not ResourceLoader.exists(path):
		return
	for player : AudioStreamPlayer in _sfx_pool:
		if not player.playing:
			player.stream = load(path)
			player.play()
			return
	# Pool full — steal oldest (first in array).
	_sfx_pool[0].stream = load(path)
	_sfx_pool[0].play()

# ---------------------------------------------------------------------------
# Haptics  —  mobile tactile feedback (Feedback Trio principle)
# ---------------------------------------------------------------------------

## Short pulse — footstep, menu tap.
func haptic_tap() -> void:
	Input.vibrate_handheld(25)

## Medium pulse — NPC interact, chest open, item pickup.
func haptic_interact() -> void:
	Input.vibrate_handheld(60)

## Hard double — combat impact.
func haptic_hit() -> void:
	Input.vibrate_handheld(90)

## Celebratory long buzz — level up, quest complete, era transition.
func haptic_celebrate() -> void:
	Input.vibrate_handheld(180)

# ---------------------------------------------------------------------------
# Era audio effects
# ---------------------------------------------------------------------------

func _apply_era_effects(era: int) -> void:
	if _music_bus_idx == -1 or _filter_idx == -1 or _reverb_idx == -1:
		return
	if era < 0 or era >= ERA_AUDIO.size():
		return

	var settings : Dictionary = ERA_AUDIO[era]
	var lp : AudioEffect = AudioServer.get_bus_effect(_music_bus_idx, _filter_idx)
	var rv : AudioEffect = AudioServer.get_bus_effect(_music_bus_idx, _reverb_idx)

	if lp is AudioEffectFilter:
		(lp as AudioEffectFilter).cutoff_hz = float(settings.get("filter_hz", 22000.0))

	if rv is AudioEffectReverb:
		(rv as AudioEffectReverb).wet       = float(settings.get("reverb_wet",  0.0))
		(rv as AudioEffectReverb).room_size = float(settings.get("reverb_room", 0.0))

# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_chapter_started(chapter_id: String) -> void:
	crossfade_to(CHAPTER_MUSIC.get(chapter_id, ""))

func _on_era_changed(era: int) -> void:
	play_sfx("era_transition")
	haptic_celebrate()
	_apply_era_effects(era)
