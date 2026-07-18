class_name PlayerController
extends CharacterBody3D

# --- Exported Parameters ---
@export_group("Movement Physics")
@export var walk_speed: float = 4.0
@export var sprint_speed: float = 7.0
@export var acceleration: float = 12.0
@export var friction: float = 10.0
@export var jump_velocity: float = 5.5
@export var gravity_multiplier: float = 2.0

@export_group("Camera Settings")
@export var mouse_sensitivity: float = 0.003
@export var camera_tilt_min: float = -60.0 # Degrees
@export var camera_tilt_max: float = 50.0  # Degrees
@export var initial_first_person: bool = false

# --- Performance Cached Node References ---
@onready var camera_pivot: Node3D = $CameraPivot as Node3D
@onready var visuals: Node3D = $Visuals as Node3D
@onready var first_person_cam: Camera3D = $FirstPersonCam as Camera3D
@onready var third_person_cam: Camera3D = $CameraPivot/ThirdPersonCam as Camera3D

# --- Runtime Architecture States ---
var is_sprinting: bool = false
var is_attacking: bool = false
var is_grounded: bool = true
var is_first_person: bool = false

# Get the gravity from the project settings to maintain physics consistency
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float

# Pre-allocated vector to save memory allocations during physics ticks
var _move_direction: Vector3 = Vector3.ZERO

# Pure numerical channels for camera orientation to eliminate axis drift
var _camera_yaw: float = 0.0
var _camera_pitch: float = 0.0

func _ready() -> void:
	# Capture the mouse for smooth character camera rotation
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Synchronize our tracking variables with the editor's initial spawn angles
	_camera_yaw = camera_pivot.rotation.y
	_camera_pitch = camera_pivot.rotation.x
	
	# Initialize the perspective preference smoothly
	_set_perspective(initial_first_person)

func _unhandled_input(event: InputEvent) -> void:
	# 1. Handle Window Focus and Mouse Capture Toggling
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			get_tree().quit()
			
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# 2. Perspective Toggle Action
	if event.is_action_pressed("toggle_perspective") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_set_perspective(not is_first_person)

	# 3. Camera Rotation Control Loop
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mouse_motion := event as InputEventMouseMotion
		
		# Accumulate raw look values independently to dodge coordinate contamination
		_camera_yaw -= mouse_motion.relative.x * mouse_sensitivity
		_camera_pitch -= mouse_motion.relative.y * mouse_sensitivity
		
		# Enforce explicit physical constraints converting degrees to radians
		_camera_pitch = clamp(
			_camera_pitch, 
			deg_to_rad(camera_tilt_min), 
			deg_to_rad(camera_tilt_max)
		)
		
		if is_first_person:
			# Apply yaw directly to the player body capsule to drive physical directional basis orientation
			rotation.y = _camera_yaw
			# Reset the vertical pivot channels locally relative to the body capsule
			camera_pivot.rotation = Vector3(_camera_pitch, 0.0, 0.0)
			first_person_cam.rotation = Vector3(_camera_pitch, 0.0, 0.0)
		else:
			# Direct Overwrite Assignment on the pivot node: Keeps Z (roll) completely locked out
			camera_pivot.rotation = Vector3(_camera_pitch, _camera_yaw, 0.0)

func _physics_process(delta: float) -> void:
	# 1. Update Grounded State & Apply Gravity
	is_grounded = is_on_floor() 
	
	if not is_grounded:
		velocity.y -= gravity * gravity_multiplier * delta
	
	# 2. Handle Action Inputs (Jump & Combat States)
	if Input.is_action_just_pressed("jump") and is_grounded and not is_attacking:
		velocity.y = jump_velocity

	# Toggle sprint check
	is_sprinting = Input.is_action_pressed("sprint") and is_grounded

	# 3. Process Directional Movement Math
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	
	# Project input vectors relative to whichever camera is actively driving rendering instructions
	var active_basis_node: Node3D = first_person_cam if is_first_person else camera_pivot
	var camera_forward := -active_basis_node.global_transform.basis.z
	var camera_right := active_basis_node.global_transform.basis.x
	
	# Flatten vectors completely along the horizontal plane (Y = 0)
	camera_forward.y = 0.0
	camera_right.y = 0.0
	camera_forward = camera_forward.normalized()
	camera_right = camera_right.normalized()
	
	# Process clean directional target fields
	_move_direction = (camera_right * input_dir.x + camera_forward * -input_dir.y).normalized()

	# 4. Handle Velocity Transitions (Acceleration & Friction)
	var current_target_speed := 0.0
	if _move_direction.length_squared() > 0.001 and not is_attacking:
		current_target_speed = sprint_speed if is_sprinting else walk_speed

	# Isolate horizontal calculations from gravity mechanics
	var horizontal_velocity := velocity
	horizontal_velocity.y = 0.0

	var target_velocity := _move_direction * current_target_speed
	
	# Squared validation optimization avoids square-root processing overhead
	var blend_weight := acceleration if _move_direction.length_squared() > 0.001 else friction
	horizontal_velocity = horizontal_velocity.lerp(target_velocity, blend_weight * delta)
	
	# Recombine clean vectors safely back into the physics body properties
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	# 5. Move Character Physics Body
	move_and_slide()

	# 6. Smooth Visual Orientation Tracking
	if is_first_person:
		# In First-Person, the body's visual mesh must always point exactly forward.
		visuals.rotation.y = 0.0
	else:
		# In Third-Person, smoothly rotate the visual mesh toward the horizontal movement vector.
		if horizontal_velocity.length_squared() > 0.1:
			var target_angle := atan2(-horizontal_velocity.x, -horizontal_velocity.z)
			visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, 10.0 * delta)

	# 7. Animation System Data Provider Hooks
	_update_animation_blending_data()

func _set_perspective(first_person: bool) -> void:
	is_first_person = first_person
	
	if is_first_person:
		# Activate first-person viewport tracking
		first_person_cam.current = true
		
		# Transfer the cumulative global horizontal yaw directly into the player body
		rotation.y = _camera_yaw
		
		# Reset internal local space transformations to eliminate spatial offset compounding
		camera_pivot.rotation = Vector3(_camera_pitch, 0.0, 0.0)
		first_person_cam.rotation = Vector3(_camera_pitch, 0.0, 0.0)
	else:
		# Activate third-person viewport tracking
		third_person_cam.current = true
		
		# Transfer the current body rotation back into our tracking yaw channel before detaching control loops
		_camera_yaw = rotation.y
		camera_pivot.rotation = Vector3(_camera_pitch, _camera_yaw, 0.0)
		
		# Reset parent capsule transform rotation so directional vector projections remain clean
		rotation.y = 0.0

func _update_animation_blending_data() -> void:
	# Explicit hook architecture maintained to prevent future state breakdown
	pass
