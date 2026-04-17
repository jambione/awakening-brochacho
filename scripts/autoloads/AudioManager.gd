## AudioManager — music playback + pooled SFX.
##
## Autoloaded as "AudioManager". Creates "Music" and "SFX" buses at runtime
## if they don't exist in the project's audio bus layout (avoids requiring
## manual bus setup in a fresh project).
extends Node

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const SFX_POOL_SIZE : int = 8  ## Concurrent SFX channels.

# ---------------------------------------------------------------------------
# Node pool
# ---------------------------------------------------------------------------
var _music_player : AudioStreamPlayer
var _sfx_pool     : Array[AudioStreamPlayer] = []

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

	_music_player     = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)

	for _i in SFX_POOL_SIZE:
		var p : AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)

	_apply_volumes()
	GameManager.settings_changed.connect(_apply_volumes)

## Create a named audio bus routed to Master if it doesn't already exist.
func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx : int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")

func _apply_volumes() -> void:
	var music_idx : int = AudioServer.get_bus_index("Music")
	var sfx_idx   : int = AudioServer.get_bus_index("SFX")
	if music_idx != -1:
		AudioServer.set_bus_volume_db(
			music_idx,
			linear_to_db(float(GameManager.settings.get("music_volume", 0.7)))
		)
	if sfx_idx != -1:
		AudioServer.set_bus_volume_db(
			sfx_idx,
			linear_to_db(float(GameManager.settings.get("sfx_volume", 0.8)))
		)

# ---------------------------------------------------------------------------
# Music
# ---------------------------------------------------------------------------

## Play a music file, looping by default. No-ops if it is already playing.
func play_music(path: String, loop: bool = true) -> void:
	if path == _current_music:
		return
	_current_music = path
	if not ResourceLoader.exists(path):
		return
	var stream : AudioStream = load(path)
	# AudioStreamOggVorbis exposes a loop property; MP3 does not in 4.x.
	if stream is AudioStreamOggVorbis:
		stream.loop = loop
	_music_player.stream = stream
	_music_player.play()

func stop_music() -> void:
	_music_player.stop()
	_current_music = ""

## Smoothly fade out the current track then stop.
func fade_music(duration: float = 1.0) -> void:
	var tween : Tween = create_tween()
	tween.tween_property(_music_player, "volume_db", -80.0, duration)
	tween.tween_callback(stop_music)

# ---------------------------------------------------------------------------
# SFX
# ---------------------------------------------------------------------------

## Play a one-shot sound effect. Uses the first idle channel in the pool.
func play_sfx(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	for player in _sfx_pool:
		if not player.playing:
			player.stream = load(path)
			player.play()
			return
	# All channels busy — steal the first one (oldest sound).
	_sfx_pool[0].stream = load(path)
	_sfx_pool[0].play()
