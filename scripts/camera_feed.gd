extends Node
class_name RearCameraFeed
## Rear-camera background for the AR view — the piece Godot can't do natively.
##
## NOTE: named RearCameraFeed (not CameraFeed) on purpose — Godot already ships a
## built-in `CameraFeed` class (part of CameraServer, a RefCounted), and reusing
## that name would shadow it and break `add_child()` type-checking.
##
## Godot's own `CameraServer`/`CameraFeed` is NOT implemented for the Web/HTML5
## export, so we can't read the camera "the Godot way" in a browser. Instead we
## use the browser's `getUserMedia` API through `JavaScriptBridge` (the exact
## same escape hatch godot-test1 uses to read motion sensors) and put the live
## camera in a plain HTML `<video>` element that sits *behind* the Godot canvas:
##
##   page:  [ #ar-video  (rear camera, z-index:-1) ]   <- this file creates it
##          [ #canvas    (Godot, TRANSPARENT)      ]   <- the coin is drawn here
##
## Because the Godot canvas is transparent (see project.godot
## `viewport/transparent_background` + `main.gd` setting `transparent_bg`), the
## camera shows through everywhere the coin isn't drawn. Godot never touches the
## camera pixels, so this is both the best-looking and the cheapest approach —
## no per-frame pixel copy across the JS/wasm boundary.
##
## Platform behaviour:
##   * **Web**: `start()` (called from a user tap — required by iOS Safari and by
##     `getUserMedia`'s secure-context/gesture rules) requests the rear camera and
##     attaches the stream. `status()` reports progress for the UI.
##   * **Desktop/editor**: there is no browser camera. `start()` is a safe no-op
##     and `status()` returns "unsupported", so main.gd can still show the coin
##     over a plain background for development.
##
## Requires HTTPS (a secure context). GitHub Pages serves HTTPS, so the deployed
## build works; `file://` and plain `http://` (except localhost) will report a
## permissions error from the browser — that's a browser rule, not a bug here.

## Status string, mirrored from `window.__ar_cam_status` (web) so the UI can show
## what's happening. Values:
##   "idle"        — start() not called yet.
##   "unsupported" — desktop/editor, or a browser without getUserMedia.
##   "starting"    — getUserMedia requested, awaiting the user's permission grant.
##   "live"        — stream attached and playing; camera is visible.
##   "error:<Name>" — getUserMedia rejected (e.g. NotAllowedError if denied,
##                    NotFoundError if no rear camera, NotReadableError if busy).
var _status: String = "idle"

## True only on the HTML5 export — gates every JavaScriptBridge touch so this file
## is inert (and never errors) on desktop/editor.
var _is_web: bool = false


func _ready() -> void:
	_is_web = OS.has_feature("web")
	if not _is_web:
		# No browser camera off-web; report unsupported so the UI can adapt.
		_status = "unsupported"


## Begin the rear-camera stream. MUST be called from a user gesture (a button
## tap) on the web — iOS Safari and getUserMedia both require it. Safe no-op on
## desktop/editor. Idempotent: calling again after "live" just re-runs the JS,
## which reuses the existing <video> element.
func start() -> void:
	if not _is_web:
		_status = "unsupported"
		return
	_status = "starting"
	JavaScriptBridge.eval(_START_JS, true)


## Poll the live status from the browser side and return it. Call each frame from
## the UI to drive the START overlay / status label. Off-web returns the cached
## value ("unsupported").
func status() -> String:
	if not _is_web:
		return _status
	# `JavaScriptBridge.eval` returns a Variant (the JS value, or null). Read the
	# flag the JS blob keeps on window; keep the last known value if it's missing.
	var v: Variant = JavaScriptBridge.eval("window.__ar_cam_status || ''", true)
	if v != null and str(v) != "":
		_status = str(v)
	return _status


## True once the camera stream is attached and playing.
func is_live() -> bool:
	return status() == "live"


# The browser-side bootstrap. Creates (once) a full-screen <video id="ar-video">
# behind the transparent canvas, forces the canvas transparent (belt-and-braces
# with the head_include CSS), then requests the REAR camera
# (facingMode:"environment") and attaches the stream. All progress is written to
# window.__ar_cam_status, which status() polls. Wrapped in an IIFE so it leaves
# no globals behind except that one status flag.
const _START_JS := """
(function(){
	window.__ar_cam_status = window.__ar_cam_status || 'starting';
	// Force the Godot canvas transparent so the coin composits over the video.
	var c = document.getElementById('canvas') || document.querySelector('canvas');
	if (c) { c.style.background = 'transparent'; c.style.backgroundColor = 'transparent'; }
	document.documentElement.style.background = '#000';
	document.body.style.background = '#000';

	function ensureVideo(){
		var v = document.getElementById('ar-video');
		if (!v){
			v = document.createElement('video');
			v.id = 'ar-video';
			v.setAttribute('playsinline','');   // iOS: play inline, not fullscreen
			v.setAttribute('autoplay','');
			v.setAttribute('muted','');
			v.muted = true;                      // required for autoplay
			v.style.position = 'fixed';
			v.style.top = '0'; v.style.left = '0';
			v.style.width = '100%'; v.style.height = '100%';
			v.style.objectFit = 'cover';         // fill the screen, crop overflow
			v.style.zIndex = '-1';               // BEHIND the Godot canvas
			v.style.background = '#000';
			// Insert as the first body child so it sits under the canvas.
			document.body.insertBefore(v, document.body.firstChild);
		}
		return v;
	}

	if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia){
		window.__ar_cam_status = 'unsupported';
		return;
	}

	// Prefer the rear camera; "ideal" (not "exact") so a front-only device still
	// works rather than failing outright.
	var constraints = { audio: false, video: { facingMode: { ideal: 'environment' } } };
	navigator.mediaDevices.getUserMedia(constraints).then(function(stream){
		var v = ensureVideo();
		v.srcObject = stream;
		var p = v.play();
		if (p && p.then){
			p.then(function(){ window.__ar_cam_status = 'live'; })
			 .catch(function(){ window.__ar_cam_status = 'live'; });
		} else {
			window.__ar_cam_status = 'live';
		}
	}).catch(function(err){
		window.__ar_cam_status = 'error:' + ((err && err.name) ? err.name : 'unknown');
	});
})();
"""
