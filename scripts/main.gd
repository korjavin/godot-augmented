extends Node3D
## Golden Coin AR — scene orchestrator.
##
## Builds the whole "magic-window" AR view in code:
##   * Makes the root viewport TRANSPARENT so the rear-camera <video> (created by
##     CameraFeed, sitting behind the canvas) shows through everywhere the coin
##     isn't drawn.
##   * A 3D Camera3D whose orientation is driven by the phone's motion sensors
##     (reused MobileSensors), so the golden coin stays anchored in space as you
##     move the phone — that's the "augmented" illusion.
##   * Lights + the spinning golden Coin.
##   * A START overlay: one tap that satisfies the browser's user-gesture
##     requirement for BOTH the camera (getUserMedia) and iOS motion permission.
##
## Desktop/editor: no browser camera and no sensors, so you see the lit, spinning
## coin over a plain background — handy for developing the look without a phone.

# --- Tuning (signs/scale are the things to confirm on a real device) ---------
## How strongly phone yaw/pitch/roll map to camera rotation. 1.0 = the world
## appears fixed (true magic-window). The SIGN of each may need flipping per
## device/browser axis convention — same on-device tuning posture as godot-test1.
@export var yaw_gain: float = 1.0
@export var pitch_gain: float = 1.0
@export var roll_gain: float = 0.5
## Smoothing: higher = snappier, lower = smoother/laggier. Tames sensor jitter.
@export var orientation_smooth: float = 12.0

# --- Nodes built in _ready ---------------------------------------------------
var _camera: Camera3D
var _coin: Coin
var _camera_feed: RearCameraFeed
var _sensors: MobileSensors

# --- UI ----------------------------------------------------------------------
var _overlay: Control          # full-screen START panel (hidden after tap)
var _start_button: Button
var _status_label: Label       # bottom status readout (camera + sensor state)
var _recenter_button: Button   # shown after start; re-zeros the orientation

var _started: bool = false
var _target_basis: Basis = Basis()


func _ready() -> void:
	# --- Transparency: let the camera <video> show through the canvas. ---
	get_viewport().transparent_bg = true
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))

	_build_world()
	_build_bridges()
	_build_ui()
	_refresh_status()


func _build_world() -> void:
	# Camera at the origin, looking down -Z (Godot's default forward).
	_camera = Camera3D.new()
	_camera.fov = 62.0
	_camera.current = true
	add_child(_camera)

	# Key + fill directional lights from different angles so the spinning coin
	# catches moving specular glints (there's no sky/IBL with a transparent bg).
	var key := DirectionalLight3D.new()
	key.light_energy = 1.6
	key.light_color = Color(1.0, 0.96, 0.85)
	key.rotation_degrees = Vector3(-35, -40, 0)
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.7
	fill.light_color = Color(0.8, 0.85, 1.0)
	fill.rotation_degrees = Vector3(-20, 130, 0)
	add_child(fill)

	# A warm point light near the camera gives the gold a bright catch-light.
	var catch := OmniLight3D.new()
	catch.light_energy = 1.2
	catch.light_color = Color(1.0, 0.9, 0.7)
	catch.omni_range = 12.0
	catch.position = Vector3(0.6, 0.6, 0.5)
	add_child(catch)

	# The coin, ~3 m in front of the camera.
	_coin = Coin.new()
	_coin.position = Vector3(0, 0, -3.0)
	add_child(_coin)


func _build_bridges() -> void:
	# Camera feed (rear-camera <video> behind the transparent canvas).
	_camera_feed = RearCameraFeed.new()
	add_child(_camera_feed)

	# Motion sensors (reused from godot-test1). Stays disabled until START so it
	# does nothing on desktop and touches no permissions until the user taps.
	_sensors = MobileSensors.new()
	add_child(_sensors)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Full-screen dim overlay with the START button.
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0, 0, 0, 0.55)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_overlay)

	var title := Label.new()
	title.text = "🪙  Golden Coin AR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-300, 180)
	title.custom_minimum_size = Vector2(600, 0)
	title.size = Vector2(600, 0)
	_overlay.add_child(title)

	var hint := Label.new()
	hint.text = "Tap START, allow camera + motion access,\nthen move your phone to find the coin."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 26)
	hint.set_anchors_preset(Control.PRESET_CENTER)
	hint.position = Vector2(-320, -180)
	hint.custom_minimum_size = Vector2(640, 0)
	hint.size = Vector2(640, 0)
	_overlay.add_child(hint)

	_start_button = Button.new()
	_start_button.text = "▶   START AR"
	_start_button.add_theme_font_size_override("font_size", 40)
	_start_button.custom_minimum_size = Vector2(420, 120)
	_start_button.set_anchors_preset(Control.PRESET_CENTER)
	_start_button.position = Vector2(-210, -60)
	_start_button.pressed.connect(_on_start_pressed)
	_overlay.add_child(_start_button)

	# Bottom status readout (camera + sensor diagnostics), always visible.
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 22)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status_label.position = Vector2(0, -60)
	layer.add_child(_status_label)

	# Recenter button (hidden until started): re-zeros "straight ahead".
	_recenter_button = Button.new()
	_recenter_button.text = "Recenter"
	_recenter_button.add_theme_font_size_override("font_size", 26)
	_recenter_button.custom_minimum_size = Vector2(180, 70)
	_recenter_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_recenter_button.position = Vector2(-200, 30)
	_recenter_button.visible = false
	_recenter_button.pressed.connect(func(): _sensors.calibrate())
	layer.add_child(_recenter_button)


func _on_start_pressed() -> void:
	_started = true
	# One user gesture, used for everything that needs one:
	_camera_feed.start()              # rear camera (getUserMedia)
	_sensors.enabled = true           # begin sensor polling
	_sensors.request_permission()     # iOS motion permission (no-op elsewhere)
	_sensors.calibrate()              # capture current pose as "straight ahead"
	_overlay.visible = false          # reveal the camera + coin
	_recenter_button.visible = true


func _process(delta: float) -> void:
	if _started:
		_update_camera_orientation(delta)
	_refresh_status()


## Rotate the Camera3D from the phone's orientation so the coin stays put in the
## world as you move the phone (the magic-window effect). Uses MobileSensors'
## calibrated tilt()/yaw(); falls back to no rotation when there's no live data
## (desktop, or before permission), so the coin simply sits dead ahead.
func _update_camera_orientation(delta: float) -> void:
	if _sensors.has_data():
		var tilt: Vector2 = _sensors.tilt()      # (roll, pitch) radians vs neutral
		var yaw: float = _sensors.yaw()           # radians vs neutral
		# Compose yaw (world up) -> pitch (local X) -> roll (local Z). The signs
		# below are the first thing to flip during on-device tuning if a gesture
		# moves the world the wrong way.
		var b := Basis()
		b = b.rotated(Vector3.UP, yaw * yaw_gain)
		b = b.rotated(b.x, tilt.y * pitch_gain)
		b = b.rotated(b.z, tilt.x * roll_gain)
		_target_basis = b
	# Smoothly approach the target orientation to tame sensor jitter.
	var t: float = clampf(orientation_smooth * delta, 0.0, 1.0)
	_camera.transform.basis = _camera.transform.basis.slerp(_target_basis, t).orthonormalized()


func _refresh_status() -> void:
	var cam: String = _camera_feed.status()
	var cam_txt := ""
	match cam:
		"idle": cam_txt = "Camera: tap START"
		"starting": cam_txt = "Camera: requesting permission…"
		"live": cam_txt = "Camera: live"
		"unsupported": cam_txt = "Camera: n/a (desktop preview)"
		_:
			cam_txt = "Camera: " + cam   # e.g. error:NotAllowedError
	var sensor_txt := ""
	if _started:
		if _sensors.has_data():
			sensor_txt = "  •  Motion: live (%s)" % _sensors.current_source()
		else:
			sensor_txt = "  •  Motion: waiting…"
	_status_label.text = cam_txt + sensor_txt
