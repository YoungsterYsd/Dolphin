## 音频管理器（Autoload 单例）。
##
## 三总线音频管理（BGM / SFX / UI）。
## 从 ConfigCenter 加载 SfxBindings.tres，按 sfx_id 查表播放；
## 内部维护 SFX AudioStreamPlayer 池（默认 8 路并发）。
##
## 设计：每条总线一个 AudioStreamPlayer 或一池；SFX 用对象池避免单 player 抢断。
extends Node

enum Bus { BGM, SFX, UI }

const SFX_POOL_SIZE: int = 8

# === SFX 池 ===
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_round_robin: int = 0

# === BGM 单实例 ===
var _bgm_player: AudioStreamPlayer = null

# === UI 单实例 ===
var _ui_player: AudioStreamPlayer = null


func _ready() -> void:
	GameLogger.info("Audio", "AudioManager ready")
	_build_pools()
	# 订阅技能事件
	EventBus.skill_event_sfx.connect(_on_skill_event_sfx)


# ─────────────────────────────────────────────────────────────
# 信号回调
# ─────────────────────────────────────────────────────────────

func _on_skill_event_sfx(sfx_id: StringName, _caster: Node, _payload: Dictionary) -> void:
	if sfx_id == &"":
		return
	# R-Core：ConfigCenter 走 class_name 强类型直访
	var stream: AudioStream = ConfigCenter.get_sfx_stream(sfx_id)
	if stream == null:
		GameLogger.info("Audio", "sfx_id not bound in SfxBindings.tres: %s" % sfx_id)
		return
	play_sfx(stream)


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

## 播放 BGM（直接切歌，无淡入淡出）。
func play_bgm(stream: AudioStream, _fade_in: float = 0.0) -> void:
	if _bgm_player == null:
		return
	if stream == null:
		return
	_bgm_player.stream = stream
	_bgm_player.play()


## 停止 BGM。
func stop_bgm(_fade_out: float = 0.0) -> void:
	if _bgm_player != null and _bgm_player.playing:
		_bgm_player.stop()


## 一次性播放 SFX（圆桶轮转池）。
func play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null or _sfx_players.is_empty():
		return
	var p: AudioStreamPlayer = _sfx_players[_sfx_round_robin]
	_sfx_round_robin = (_sfx_round_robin + 1) % _sfx_players.size()
	p.stream = stream
	p.volume_db = volume_db
	p.play()


## 一次性播放 UI 音效。
func play_ui(stream: AudioStream, volume_db: float = 0.0) -> void:
	if _ui_player == null or stream == null:
		return
	_ui_player.stream = stream
	_ui_player.volume_db = volume_db
	_ui_player.play()


## 便捷：按 sfx_id 播放 SFX（外部业务可直接调）。
func play_sfx_by_id(sfx_id: StringName, volume_db: float = 0.0) -> void:
	# R-Core：ConfigCenter 走 class_name 强类型直访
	var stream: AudioStream = ConfigCenter.get_sfx_stream(sfx_id)
	play_sfx(stream, volume_db)


## 设置某条总线音量（线性 0.0–1.0）。
func set_bus_volume(bus: int, linear: float) -> void:
	var bus_name: String = ""
	match bus:
		Bus.BGM:
			bus_name = "Master"  # 项目目前没建独立 bus，统一走 Master
		Bus.SFX:
			bus_name = "Master"
		Bus.UI:
			bus_name = "Master"
		_:
			return
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var db: float = linear_to_db(clampf(linear, 0.0, 1.0))
	AudioServer.set_bus_volume_db(idx, db)


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _build_pools() -> void:
	for i in range(SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		add_child(p)
		_sfx_players.append(p)
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = &"Master"
	add_child(_bgm_player)
	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = &"Master"
	add_child(_ui_player)
