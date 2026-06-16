extends MeshInstance3D
class_name Coin
## The golden coin — a thin spinning 3D cylinder with a gold material.
##
## Built entirely in code (mesh + material) so there are no binary assets to
## import. main.gd instantiates this, places it in front of the AR camera, and
## the coin spins + gently bobs so its gold surface catches the scene lights and
## reads as a coin rather than a flat disc.
##
## Gold without an environment map: with a transparent background there is no sky
## to reflect, so a fully-metallic surface would look black. We use a high-but-
## not-full metallic with a little emission and rely on the explicit lights in
## main.gd for specular glints — which animate nicely as the coin turns.

## Degrees per second the coin spins around its own (face) axis.
@export var spin_speed_deg: float = 70.0

## Vertical bob amplitude (metres) and rate (Hz) — a subtle float so the coin
## feels alive even when the phone is held still.
@export var bob_amplitude: float = 0.05
@export var bob_hz: float = 0.5

## Coin dimensions (metres). A real coin is wide and thin.
const RADIUS: float = 0.35
const THICKNESS: float = 0.06

var _base_y: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	_base_y = position.y
	mesh = _build_mesh()
	material_override = _build_material()
	# Lay the cylinder on its side so the broad face points at the camera, then
	# spin around the face normal (its local Y after this tilt) for a coin-flip
	# look. We orient it face-on by rotating 90° about X.
	rotation_degrees.x = 90.0


func _process(delta: float) -> void:
	_t += delta
	# Spin around the coin's face axis. After the 90° X tilt in _ready, rotating
	# about the local Y axis spins the face like a flipping coin edge-on; rotating
	# about local Z spins it like a record. We use Y for the classic "coin facing
	# you, turning" glint. rotate_object_local keeps it independent of bob.
	rotate_object_local(Vector3.UP, deg_to_rad(spin_speed_deg) * delta)
	# Gentle vertical bob.
	position.y = _base_y + sin(_t * TAU * bob_hz) * bob_amplitude


## A short, wide cylinder = a coin blank.
func _build_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = RADIUS
	m.bottom_radius = RADIUS
	m.height = THICKNESS
	m.radial_segments = 48      # smooth rim
	m.rings = 1
	return m


## Warm metallic gold. Tuned to look golden under direct lights with no IBL:
## high metallic for sheen, low roughness for tight highlights, a touch of
## emission so it never goes dead-black when a face turns away from every light.
func _build_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.82, 0.28)        # gold
	mat.metallic = 0.85
	mat.metallic_specular = 0.9
	mat.roughness = 0.28
	mat.emission_enabled = true
	mat.emission = Color(0.45, 0.33, 0.06)
	mat.emission_energy_multiplier = 0.5
	return mat
