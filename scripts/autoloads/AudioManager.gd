extends Node

# ── Nodes ─────────────────────────────────────────────────────────────────────
var _music_player: AudioStreamPlayer
var _sfx_player:   AudioStreamPlayer
var _sfx_pool:     Array[AudioStreamPlayer] = []
const SFX_POOL_SIZE := 8

# ── State ─────────────────────────────────────────────────────────────────────
var _current_music: String = ""

func _ready() -> void:
	_ensure_bus("Music")
	_ensure_bus("SFX")

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)

	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)

	_apply_volumes()
	GameManager.settings_changed.connect(_apply_volumes)

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")

func _apply_volumes() -> void:
	var music_idx := AudioServer.get_bus_index("Music")
	var sfx_idx   := AudioServer.get_bus_index("SFX")
	if music_idx != -1:
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(GameManager.settings.music_volume))
	if sfx_idx != -1:
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(GameManager.settings.sfx_volume))

# ── Music ─────────────────────────────────────────────────────────────────────
func play_music(path: String, loop: bool = true) -> void:
	if path == _current_music:
		return
	_current_music = path
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		if stream is AudioStreamOggVorbis:
			stream.loop = loop
	_music_player.stream = stream
	_music_player.play()

func stop_music() -> void:
	_music_player.stop()
	_current_music = ""

func fade_music(duration: float = 1.0) -> void:
	var tween := create_tween()
	tween.tween_property(_music_player, "volume_db", -80.0, duration)
	tween.tween_callback(stop_music)

# ── SFX ───────────────────────────────────────────────────────────────────────
func play_sfx(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	for player in _sfx_pool:
		if not player.playing:
			player.stream = load(path)
			player.play()
			return
	# All busy — use first one anyway
	_sfx_pool[0].stream = load(path)
	_sfx_pool[0].play()
