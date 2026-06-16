# 🪙 Golden Coin AR

A **"magic-window" augmented-reality** web app built with Godot 4.5. It shows the
live **rear camera** full-screen (like a camera app) and renders a **3D golden
coin** floating in front of you. Move your phone around and the coin stays
anchored in space — driven by the device's orientation sensors.

Built to run in the browser, deployed automatically to **GitHub Pages** via
GitHub Actions — the same pipeline as the sibling `godot-test1` project.

> Sibling project this was modeled on: `../godot-test1` (CI, web export config,
> and the motion-sensor bridge `scripts/mobile_sensors.gd` are reused from it).

---

## How it works (and the one important caveat)

Godot's built-in camera API (`CameraServer` / `CameraFeed`) is **not implemented
for the Web/HTML5 export** — you cannot read the camera "the Godot way" in a
browser. So we use the browser itself:

```
 ┌─────────────────────────────────────────────┐
 │  Godot canvas  (TRANSPARENT)  — draws the coin│   z-index: 0
 ├─────────────────────────────────────────────┤
 │  <video id="ar-video">  — rear camera feed    │   z-index: -1  (behind)
 └─────────────────────────────────────────────┘
```

* **Camera** → `scripts/camera_feed.gd` calls the browser's `getUserMedia` (rear
  camera, `facingMode: environment`) through `JavaScriptBridge` and puts the
  stream in a plain HTML `<video>` element *behind* the Godot canvas.
* **Transparency** → the Godot canvas is made transparent (`project.godot`
  `viewport/transparent_background` + `main.gd` `transparent_bg`, plus CSS in the
  export `head_include`), so the camera shows through everywhere the coin isn't.
* **Coin** → `scripts/coin.gd` is a procedurally-built gold cylinder that spins
  and bobs; Godot lights give it animated glints.
* **"Looking around"** → `scripts/mobile_sensors.gd` (reused from `godot-test1`)
  reads device orientation; `main.gd` rotates the 3D camera to match, so the coin
  stays put as you move the phone.

### What's realistic vs. not
* ✅ Live camera background + a coin overlay anchored by device **orientation**
  (turn/tilt the phone and the coin holds its place). This is what's built.
* ⚠️ **True world-tracking** (coin pinned to a real table, staying put as you
  *walk around* it) needs WebXR-AR or computer-vision marker tracking — neither
  is available in Godot's web export. We get orientation-anchored, not
  position-tracked.

---

## Requirements to actually see the camera

`getUserMedia` only works in a **secure context**:

* **GitHub Pages** (HTTPS) → works. This is the intended way to test on a phone.
* **`http://localhost`** → counts as secure, so the camera works when testing on
  the *same* computer.
* **`http://<LAN-ip>` from your phone** → **blocked** by the browser. To test on a
  phone you must use the HTTPS GitHub Pages URL (or your own HTTPS tunnel).
* On **iOS Safari**, both the camera and the motion sensors require a **user tap**
  — that's why there's a single **START AR** button that requests both at once.

---

## Run locally (desktop preview)

```bash
godot --path .            # opens the project; press F5 to run
```

On desktop there's no browser camera or sensors, so you'll see the lit, spinning
coin over a plain background — useful for iterating on the look. The camera and
orientation only come alive in the deployed web build on a phone.

### Test the web build locally
```bash
godot --headless --export-release "Web" build/web/index.html
cd build/web && python3 -m http.server 8080
# open http://localhost:8080  (camera works because localhost is "secure")
```

---

## Deploy (GitHub Pages)

1. Push to a GitHub repo (branch `master` or `main`).
2. Repo **Settings → Pages → Build and deployment → Source: GitHub Actions**.
3. `.github/workflows/build.yml` builds the web export and deploys it on every
   push to `master`/`main`. Open the Pages URL **on your phone** (HTTPS) and tap
   **START AR**.

---

## On-device tuning (expect to flip a sign or two)

Phone/browser axis conventions vary, so the orientation mapping in `main.gd` is
the first thing to adjust on a real device. Tunables (exported, editable in the
Inspector):

| Where | Var | What it does |
|-------|-----|--------------|
| `main.gd` | `yaw_gain` / `pitch_gain` / `roll_gain` | strength + **sign** of each axis. If turning the phone moves the world the wrong way, negate the gain. |
| `main.gd` | `orientation_smooth` | higher = snappier, lower = smoother. |
| `coin.gd` | `spin_speed_deg`, `bob_amplitude`, `bob_hz` | coin animation. |

The on-screen **Recenter** button re-zeros "straight ahead" (calls
`MobileSensors.calibrate()`) — handy because gyro-integrated yaw drifts.

The bottom status line reports camera state (`requesting…` / `live` /
`error:NotAllowedError` …) and the motion source (`native` / `js`) for quick
on-device diagnosis.

---

## Project layout

```
project.godot              # Godot 4.5 config; web = gl_compatibility + transparent canvas
export_presets.cfg         # Web preset; head_include CSS for the camera <video>
.github/workflows/build.yml# CI: build web export + deploy to GitHub Pages
scenes/main.tscn           # minimal root; the scene is built in code
scripts/
  main.gd                  # orchestrator: camera rig, lights, coin, UI, wiring
  camera_feed.gd           # rear-camera <video> via getUserMedia (RearCameraFeed)
  coin.gd                  # procedural golden coin (spin + bob)
  mobile_sensors.gd        # device-orientation bridge (reused from godot-test1)
```
