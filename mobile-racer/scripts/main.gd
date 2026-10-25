extends Node3D
## Turbo Trails: a mobile-focused 3D driving simulator with textured roads, terrain, and traffic.
## Curves, vegetation, and repeated props are instanced for mobile rendering.

const CARS: Array[Dictionary] = [
    {"name": "Zenith X1", "file": "res://assets/cars/zenith_x1.glb"},
    {"name": "Apex V12R", "file": "res://assets/cars/apex_v12r.glb"},
    {"name": "Titan GT", "file": "res://assets/cars/titan_gt.glb"},
    {"name": "Rallyfox X", "file": "res://assets/cars/rallyfox_x.glb"},
    {"name": "Volt E RS", "file": "res://assets/cars/volt_e_rs.glb"},
    {"name": "Phantom Blackline", "file": "res://assets/cars/phantom_blackline.glb"},
    {"name": "Tempest Roadster", "file": "res://assets/cars/tempest_roadster.glb"},
    {"name": "Monarch SVR", "file": "res://assets/cars/monarch_svr.glb"},
    {"name": "Viper Street RS", "file": "res://assets/cars/viper_street_rs.glb"},
]

const ROUTES: Array[Dictionary] = [
    {
        "name": "COASTAL SPRINT",
        "subtitle": "Ocean road • fast sweepers",
        "length": 4800.0,
        "kind": "coast",
        "sky_top": Color(0.035, 0.20, 0.40),
        "sky_horizon": Color(0.60, 0.82, 0.94),
        "ground": Color(0.13, 0.31, 0.20),
        "asphalt": Color(0.105, 0.115, 0.13),
        "shoulder": Color(0.70, 0.68, 0.55),
        "accent": Color(0.05, 0.69, 0.91),
    },
    {
        "name": "ALPINE PASS",
        "subtitle": "High country • elevation changes",
        "length": 5100.0,
        "kind": "alpine",
        "sky_top": Color(0.055, 0.13, 0.29),
        "sky_horizon": Color(0.60, 0.75, 0.86),
        "ground": Color(0.17, 0.29, 0.16),
        "asphalt": Color(0.095, 0.105, 0.115),
        "shoulder": Color(0.35, 0.36, 0.35),
        "accent": Color(1.0, 0.48, 0.13),
    },
    {
        "name": "NEON CITY GP",
        "subtitle": "Night circuit • city lights",
        "length": 4400.0,
        "kind": "city",
        "sky_top": Color(0.012, 0.018, 0.075),
        "sky_horizon": Color(0.075, 0.08, 0.18),
        "ground": Color(0.055, 0.06, 0.095),
        "asphalt": Color(0.045, 0.05, 0.075),
        "shoulder": Color(0.10, 0.105, 0.16),
        "accent": Color(0.12, 0.88, 1.0),
    },
]

const ROAD_WIDTH := 10.5
const ROAD_HALF := ROAD_WIDTH * 0.5
const SAMPLE_STEP := 4.0
const CRUISE_SPEED := 47.0
const BOOST_SPEED := 67.0
const BRAKE_SPEED := 18.0
const LANE_LIMIT := 10.0
const COIN_SCORE := 250
const ROAD_DASH_LENGTH := 7.0
const WHEELBASE := 2.65
const TOP_SPEED_MPS := 52.0
const ROAD_EDGE_MARGIN := 0.85

var route_index := 0
var car_index := 0
var route_length := 4800.0
var travel_distance := 0.0
var lateral_offset := 0.0
var current_speed := 0.0
var elapsed_time := 0.0
var race_over := false
var start_countdown := 0.0
var vehicle_heading := 0.0
var engine_rpm := 900.0
var current_gear := 1
var throttle_touch := false
var drive_started := false
var steering_touch := 0.0
var steering_left_held := false
var steering_right_held := false
var brake_touch := false
var steering_mouse := false

var course_root: Node3D
var player_root: Node3D
var car_visual: Node3D
var chase_camera: Camera3D
var world_environment: WorldEnvironment
var key_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var best_times: Dictionary = {}
var best_time_label: Label

var traffic_nodes: Array[Dictionary] = []
var checkpoint_distances: Array[float] = []
var next_checkpoint := 0

var score_label: Label
var speed_label: Label
var car_label: Label
var route_label: Label
var time_label: Label
var message_label: Label
var progress_bar: ProgressBar
var throttle_button: Button


func _ready() -> void:
    _configure_input()
    _load_records()
    _build_world()
    _build_player()
    _build_hud()
    _load_selected_car()
    _rebuild_route()
    _refresh_hud()


func _process(delta: float) -> void:
    delta = clampf(delta, 0.0, 0.05)
    if race_over:
        _refresh_hud()
        return
    if delta <= 0.0:
        return
    var previous_distance := travel_distance
    var previous_lane := lateral_offset
    var steer := steering_touch
    if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
        steer -= 1.0
    if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
        steer += 1.0
    steer = clampf(steer, -1.0, 1.0)
    var braking := brake_touch or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
    var accelerating := throttle_touch or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
    if braking:
        current_speed = move_toward(current_speed, 0.0, 10.5 * delta)
    elif accelerating:
        current_speed = move_toward(current_speed, TOP_SPEED_MPS, 3.6 * delta)
        drive_started = drive_started or current_speed > 0.5
    else:
        current_speed = maxf(0.0, current_speed - (0.18 + current_speed * 0.022) * delta)
    if drive_started:
        elapsed_time += delta

    # Speed-sensitive bicycle-model steering; yaw is integrated instead of snapping
    # the car back onto the track centreline every frame.
    var steering_scale := clampf(3.0 / maxf(current_speed, 3.0), 0.035, 1.0)
    var wheel_angle := steer * deg_to_rad(29.0) * steering_scale
    if current_speed > 0.15:
        vehicle_heading = wrapf(vehicle_heading + (current_speed / WHEELBASE) * tan(wheel_angle) * delta, -PI, PI)
    var tangent := _forward_at(travel_distance)
    var road_heading := atan2(tangent.x, -tangent.z)
    var heading_error := wrapf(road_heading - vehicle_heading, -PI, PI)
    vehicle_heading = wrapf(vehicle_heading + heading_error * clampf(current_speed / 32.0, 0.0, 1.0) * 0.14 * delta, -PI, PI)
    var relative_heading := wrapf(vehicle_heading - road_heading, -PI, PI)
    travel_distance = clampf(travel_distance + current_speed * cos(relative_heading) * delta, 0.0, route_length)
    lateral_offset = clampf(lateral_offset + current_speed * sin(relative_heading) * delta, -LANE_LIMIT, LANE_LIMIT)

    var offroad := absf(lateral_offset) > ROAD_HALF - ROAD_EDGE_MARGIN
    if offroad:
        current_speed = move_toward(current_speed, minf(current_speed, 17.0), 2.8 * delta)
        if not message_label.text.begins_with("OFF ROAD"):
            message_label.text = "OFF ROAD  •  EASE OFF AND REJOIN"
    elif message_label.text.begins_with("OFF ROAD"):
        message_label.text = "DRIVE CAREFULLY  •  TRAFFIC AHEAD"

    _advance_traffic(delta)
    _place_player_and_camera(delta)
    _check_traffic_collisions(previous_distance, previous_lane)
    if race_over:
        _refresh_hud()
        return
    if travel_distance >= route_length - 0.01:
        race_over = true
        current_speed = 0.0
        drive_started = false
        var route_name := String(ROUTES[route_index]["name"])
        var previous_best := float(best_times.get(route_name, 0.0))
        if previous_best <= 0.0 or elapsed_time < previous_best:
            best_times[route_name] = elapsed_time
            _save_records()
            message_label.text = "STAGE COMPLETE  •  NEW BEST %s" % _format_time(elapsed_time)
        else:
            message_label.text = "STAGE COMPLETE  •  %s" % _format_time(elapsed_time)
    _refresh_hud()

func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_C:
            _change_car()
        elif event.keycode == KEY_R:
            _restart_race()
        elif event.keycode == KEY_Q:
            _change_route(-1)
        elif event.keycode == KEY_E:
            _change_route(1)


func _configure_input() -> void:
    # Standard UI arrows are kept available for keyboard play as well as touch.
    for action in ["ui_left", "ui_right"]:
        if not InputMap.has_action(action):
            InputMap.add_action(action)


func _notification(what: int) -> void:
    # Android can interrupt a touch without delivering Button.button_up. Clear
    # held controls on app pause/focus loss so the car cannot keep steering or
    # boosting when the player returns.
    if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
        _release_touch_controls()


func _release_touch_controls() -> void:
    steering_left_held = false
    steering_right_held = false
    steering_touch = 0.0
    brake_touch = false
    throttle_touch = false


func _update_touch_steering() -> void:
    if steering_left_held == steering_right_held:
        steering_touch = 0.0
    elif steering_left_held:
        steering_touch = -1.0
    else:
        steering_touch = 1.0


func _on_left_button_down() -> void:
    steering_left_held = true
    _update_touch_steering()


func _on_left_button_up() -> void:
    steering_left_held = false
    _update_touch_steering()


func _on_right_button_down() -> void:
    steering_right_held = true
    _update_touch_steering()


func _on_right_button_up() -> void:
    steering_right_held = false
    _update_touch_steering()


func _build_world() -> void:
    world_environment = WorldEnvironment.new()
    world_environment.name = "WorldEnvironment"
    world_environment.environment = Environment.new()
    add_child(world_environment)
    _configure_route_environment()

    key_light = DirectionalLight3D.new()
    key_light.name = "KeyLight"
    key_light.rotation_degrees = Vector3(-42.0, -24.0, 0.0)
    key_light.light_energy = 1.35
    key_light.light_color = Color(1.0, 0.91, 0.78)
    key_light.shadow_enabled = true
    key_light.directional_shadow_max_distance = 120.0
    add_child(key_light)

    fill_light = DirectionalLight3D.new()
    fill_light.name = "SkyFill"
    fill_light.rotation_degrees = Vector3(-22.0, 153.0, 0.0)
    fill_light.light_energy = 0.36
    fill_light.light_color = Color(0.43, 0.64, 1.0)
    fill_light.shadow_enabled = false
    add_child(fill_light)


func _configure_route_environment() -> void:
    var route: Dictionary = ROUTES[route_index]
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var sky_mat := ProceduralSkyMaterial.new()
    sky_mat.sky_top_color = route["sky_top"]
    sky_mat.sky_horizon_color = route["sky_horizon"]
    sky_mat.ground_bottom_color = route["ground"].darkened(0.25)
    sky_mat.ground_horizon_color = route["ground"]
    sky_mat.sun_angle_max = 18.0
    sky.sky_material = sky_mat
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_energy = 0.75 if route["kind"] != "city" else 0.34
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.tonemap_exposure = 1.12 if route["kind"] == "city" else 1.0
    env.fog_enabled = true
    env.fog_light_color = route["sky_horizon"]
    env.fog_density = 0.0012 if route["kind"] != "city" else 0.0028
    env.volumetric_fog_enabled = false
    world_environment.environment = env
    if is_instance_valid(key_light):
        key_light.light_energy = 0.22 if route["kind"] == "city" else 1.35
        key_light.light_color = Color(0.48, 0.59, 1.0) if route["kind"] == "city" else Color(1.0, 0.91, 0.78)
    if is_instance_valid(fill_light):
        fill_light.light_energy = 0.62 if route["kind"] == "city" else 0.36
        fill_light.light_color = Color(0.18, 0.40, 1.0) if route["kind"] == "city" else Color(0.43, 0.64, 1.0)


func _mat(color: Color, roughness := 0.8, metallic := 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material


func _emissive_mat(color: Color, energy: float) -> StandardMaterial3D:
    var material := _mat(color, 0.42, 0.0)
    material.emission_enabled = true
    material.emission = color
    material.emission_energy_multiplier = energy
    return material


func _add_box(parent: Node3D, size: Vector3, position: Vector3, material: Material, node_name := "Mesh") -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    instance.name = node_name
    var mesh := BoxMesh.new()
    mesh.size = size
    instance.mesh = mesh
    instance.position = position
    instance.material_override = material
    parent.add_child(instance)
    return instance


func _point_at(distance: float) -> Vector3:
    var d := clampf(distance, 0.0, route_length)
    var kind: String = ROUTES[route_index]["kind"]
    var x := 0.0
    var y := 0.0
    if kind == "coast":
        x = 40.0 * sin(d / 470.0) + 16.0 * sin(d / 195.0 + 0.4) + 7.0 * sin(d / 94.0)
        y = 2.1 * sin(d / 290.0) + 0.9 * sin(d / 101.0)
    elif kind == "alpine":
        x = 34.0 * sin(d / 315.0) + 29.0 * sin(d / 610.0 + 0.65) + 6.0 * sin(d / 106.0)
        y = 12.0 * sin(d / 390.0) + 3.5 * sin(d / 135.0) + 0.0014 * d
    else:
        x = 27.0 * sin(d / 300.0) + 13.0 * sin(d / 151.0 + 0.6) + 4.0 * sin(d / 68.0)
        y = 0.5 * sin(d / 280.0)
    return Vector3(x, y, -d)


func _forward_at(distance: float) -> Vector3:
    var step := 1.0
    var a := _point_at(maxf(0.0, distance - step))
    var b := _point_at(minf(route_length, distance + step))
    var forward := (b - a).normalized()
    forward.y = clampf(forward.y, -0.38, 0.38)
    return forward.normalized()


func _right_at(distance: float) -> Vector3:
    var forward := _forward_at(distance)
    return Vector3(-forward.z, 0.0, forward.x).normalized()


func _make_ribbon(parent: Node3D, node_name: String, left_offset: float, right_offset: float, y_offset: float, material: Material, step := SAMPLE_STEP) -> MeshInstance3D:
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    var vertices := PackedVector3Array()
    var uvs := PackedVector2Array()
    var indices := PackedInt32Array()
    var steps := int(ceil(route_length / step))
    for i in range(steps + 1):
        var distance := minf(float(i) * step, route_length)
        var center := _point_at(distance)
        var right := _right_at(distance)
        vertices.append(center + right * left_offset + Vector3.UP * y_offset)
        vertices.append(center + right * right_offset + Vector3.UP * y_offset)
        uvs.append(Vector2(0.0, distance / 2.0))
        uvs.append(Vector2(absf(right_offset - left_offset) / 2.0, distance / 2.0))
        if i < steps:
            var idx := i * 2
            indices.append_array(PackedInt32Array([idx, idx + 1, idx + 2, idx + 1, idx + 3, idx + 2]))
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices
    arrays[Mesh.ARRAY_NORMAL] = _calculate_normals(vertices, indices)
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    mesh.surface_set_material(0, material)
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.material_override = material
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(instance)
    return instance


func _calculate_normals(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
    var normals := PackedVector3Array()
    normals.resize(vertices.size())
    for i in range(0, indices.size(), 3):
        var ia := indices[i]
        var ib := indices[i + 1]
        var ic := indices[i + 2]
        var face := (vertices[ib] - vertices[ia]).cross(vertices[ic] - vertices[ia])
        if face.length_squared() > 0.000001:
            face = face.normalized()
            normals[ia] += face
            normals[ib] += face
            normals[ic] += face
    for i in range(normals.size()):
        normals[i] = normals[i].normalized() if normals[i].length_squared() > 0.000001 else Vector3.UP
    return normals


func _texture_or_null(path: String) -> Texture2D:
    if not ResourceLoader.exists(path):
        return null
    return ResourceLoader.load(path) as Texture2D


func _make_pbr_material(texture_set: String, tint: Color, uv_scale := Vector3.ONE) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = tint
    material.roughness = 0.9
    material.metallic = 0.0
    material.uv1_scale = uv_scale
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
    var root := "res://assets/environment/" + texture_set
    var diffuse := _texture_or_null(root + "_diff_1k.jpg")
    var normal_map := _texture_or_null(root + "_nor_gl_1k.jpg")
    var roughness_map := _texture_or_null(root + "_rough_1k.jpg")
    if diffuse != null:
        material.albedo_texture = diffuse
    if normal_map != null:
        material.normal_enabled = true
        material.normal_texture = normal_map
        material.normal_scale = 0.68
    if roughness_map != null:
        material.roughness_texture = roughness_map
        material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
    return material


func _make_asphalt_material(route: Dictionary) -> Material:
    var tint := Color(0.91, 0.92, 0.94)
    if route["kind"] == "city":
        tint = Color(0.72, 0.78, 0.92)
    return _make_pbr_material("asphalt_03", tint)


func _build_route_surface() -> void:
    var route: Dictionary = ROUTES[route_index]
    var asphalt: Material = _make_asphalt_material(route)
    var shoulder := _make_pbr_material("gravel_road", Color(0.78, 0.76, 0.70))
    var edge_paint := _mat(Color(0.92, 0.92, 0.86), 0.8)
    var yellow_paint := _mat(Color(0.96, 0.72, 0.12), 0.8)
    _make_ribbon(course_root, "TexturedGravelShoulder", -ROAD_HALF - 2.8, ROAD_HALF + 2.8, -0.14, shoulder)
    _make_ribbon(course_root, "PBRAsphaltRoad", -ROAD_HALF, ROAD_HALF, 0.0, asphalt)
    _make_ribbon(course_root, "LeftRoadEdgeLine", -ROAD_HALF + 0.12, -ROAD_HALF + 0.30, 0.024, edge_paint)
    _make_ribbon(course_root, "RightRoadEdgeLine", ROAD_HALF - 0.30, ROAD_HALF - 0.12, 0.024, edge_paint)
    _make_ribbon(course_root, "CentreYellowLineLeft", -0.23, -0.11, 0.028, yellow_paint)
    _make_ribbon(course_root, "CentreYellowLineRight", 0.11, 0.23, 0.028, yellow_paint)
    var rail_mat := _mat(Color(0.52, 0.57, 0.61), 0.42, 0.55)
    var rail_glint := _mat(Color(0.78, 0.81, 0.82), 0.38, 0.48)
    _make_ribbon(course_root, "LeftGuardrailLower", -ROAD_HALF - 1.65, -ROAD_HALF - 1.48, 0.53, rail_mat)
    _make_ribbon(course_root, "RightGuardrailLower", ROAD_HALF + 1.48, ROAD_HALF + 1.65, 0.53, rail_mat)
    _make_ribbon(course_root, "LeftGuardrailTop", -ROAD_HALF - 1.65, -ROAD_HALF - 1.48, 1.02, rail_glint)
    _make_ribbon(course_root, "RightGuardrailTop", ROAD_HALF + 1.48, ROAD_HALF + 1.65, 1.02, rail_glint)
    _make_guardrail_posts(rail_mat)

func _make_guardrail_posts(material: Material) -> void:
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.17, 0.9, 0.24)
    var count_per_side := int(route_length / 12.0)
    var multi := MultiMesh.new()
    multi.transform_format = MultiMesh.TRANSFORM_3D
    multi.mesh = mesh
    multi.instance_count = count_per_side * 2
    var idx := 0
    for side in [-1.0, 1.0]:
        for i in range(count_per_side):
            var d := float(i) * 12.0 + 3.0
            var pos: Vector3 = _point_at(d) + _right_at(d) * side * (ROAD_HALF + 1.56)
            pos.y += 0.45
            multi.set_instance_transform(idx, Transform3D(Basis.looking_at(_forward_at(d), Vector3.UP), pos))
            idx += 1
    var post_instance := MultiMeshInstance3D.new()
    post_instance.name = "InstancedGuardrailSupports"
    post_instance.multimesh = multi
    post_instance.material_override = material
    post_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    course_root.add_child(post_instance)


func _rebuild_route() -> void:
    var route: Dictionary = ROUTES[route_index]
    route_length = float(route["length"])
    _configure_route_environment()
    if is_instance_valid(course_root):
        course_root.free()
    course_root = Node3D.new()
    course_root.name = "Course_" + String(route["name"]).replace(" ", "_")
    add_child(course_root)

    _build_landscape()
    _build_route_surface()
    _build_route_props()
    _build_traffic()
    _restart_race(false)
    route_label.text = "%02d / %02d   %s" % [route_index + 1, ROUTES.size(), route["name"]]
    message_label.text = "%s  •  READY TO DRIVE" % route["subtitle"]
    _refresh_hud()


func _terrain_height_offset(distance: float, lateral: float, kind: String) -> float:
    var side := absf(lateral)
    if side <= ROAD_HALF + 2.8:
        return -0.42
    var blend := clampf((side - ROAD_HALF - 2.8) / 22.0, 0.0, 1.0)
    blend = blend * blend * (3.0 - 2.0 * blend)
    var wave := sin(distance * 0.0041 + lateral * 0.023) * 2.3 + sin(distance * 0.014 + lateral * 0.061) * 0.75
    var target_height := 1.0 + wave
    if kind == "alpine":
        target_height = 6.5 + absf(sin(distance * 0.0031 + lateral * 0.027)) * 24.0 + wave
    elif kind == "coast":
        target_height = 1.6 + wave
        if lateral < 0.0 and side > 58.0:
            var cliff_blend := clampf((side - 58.0) / 38.0, 0.0, 1.0)
            cliff_blend = cliff_blend * cliff_blend * (3.0 - 2.0 * cliff_blend)
            target_height = lerpf(target_height + 5.0, -5.5, cliff_blend)
    elif kind == "city":
        target_height = 0.3 + wave * 0.12
    return lerpf(-0.42, target_height, blend)


func _build_landscape() -> void:
    var kind: String = ROUTES[route_index]["kind"]
    var terrain_tint := Color(0.83, 0.86, 0.77) if kind == "alpine" else (Color(0.50, 0.55, 0.62) if kind == "city" else Color(0.95, 0.94, 0.86))
    var terrain_material := _make_pbr_material("forrest_ground_01", terrain_tint)
    var rows := int(ceil(route_length / 16.0)) + 1
    var lateral_extent := 180.0
    var lateral_step := 6.0
    var columns := int((lateral_extent * 2.0) / lateral_step) + 1
    var vertices := PackedVector3Array()
    var uvs := PackedVector2Array()
    var indices := PackedInt32Array()
    for row in range(rows):
        var distance := minf(float(row) * 16.0, route_length)
        var center := _point_at(distance)
        var right := _right_at(distance)
        for col in range(columns):
            var lateral := -lateral_extent + float(col) * lateral_step
            vertices.append(center + right * lateral + Vector3.UP * _terrain_height_offset(distance, lateral, kind))
            uvs.append(Vector2((lateral + lateral_extent) / 8.0, distance / 8.0))
            if row < rows - 1 and col < columns - 1:
                var idx := row * columns + col
                indices.append_array(PackedInt32Array([idx, idx + 1, idx + columns, idx + 1, idx + columns + 1, idx + columns]))
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices
    arrays[Mesh.ARRAY_NORMAL] = _calculate_normals(vertices, indices)
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    mesh.surface_set_material(0, terrain_material)
    var terrain := MeshInstance3D.new()
    terrain.name = "ContouredPBRLandscape"
    terrain.mesh = mesh
    terrain.material_override = terrain_material
    terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    course_root.add_child(terrain)
    if kind == "coast":
        _build_coastal_water()


func _build_coastal_water() -> void:
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var uvs := PackedVector2Array()
    var indices := PackedInt32Array()
    var rows := int(ceil(route_length / 14.0)) + 1
    for i in range(rows):
        var distance := minf(float(i) * 14.0, route_length)
        var center := _point_at(distance)
        var right := _right_at(distance)
        vertices.append(Vector3(center.x - right.x * 520.0, -4.1, center.z - right.z * 520.0))
        vertices.append(Vector3(center.x - right.x * 98.0, -4.1, center.z - right.z * 98.0))
        normals.append(Vector3.UP)
        normals.append(Vector3.UP)
        uvs.append(Vector2(0.0, distance / 24.0))
        uvs.append(Vector2(12.0, distance / 24.0))
        if i < rows - 1:
            var idx := i * 2
            indices.append_array(PackedInt32Array([idx, idx + 1, idx + 2, idx + 1, idx + 3, idx + 2]))
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var water := MeshInstance3D.new()
    water.name = "CoastalOcean"
    water.mesh = mesh
    var material := _mat(Color(0.025, 0.18, 0.27), 0.18, 0.28)
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.metallic = 0.16
    water.material_override = material
    water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    course_root.add_child(water)

func _build_route_props() -> void:
    var kind: String = ROUTES[route_index]["kind"]
    if kind == "city":
        _build_city_props()
        _build_nature_props("city")
    else:
        _build_nature_props(kind)


func _build_nature_props(kind: String) -> void:
    var spacing := 58.0 if kind == "city" else (19.0 if kind == "alpine" else 17.0)
    var count := maxi(1, int(route_length / spacing))
    var trunk_height := 3.6 if kind == "city" else (4.4 if kind == "alpine" else 3.8)
    var trunk_mesh := CylinderMesh.new()
    trunk_mesh.top_radius = 0.16 if kind != "alpine" else 0.20
    trunk_mesh.bottom_radius = 0.28 if kind != "alpine" else 0.34
    trunk_mesh.height = trunk_height
    trunk_mesh.radial_segments = 9
    var trunk_transforms: Array[Transform3D] = []
    var trunk_colors := PackedColorArray()
    var broadleaf_transforms: Array[Transform3D] = []
    var broadleaf_colors := PackedColorArray()
    var pine_meshes: Array[Mesh] = []
    var pine_transforms: Array = []
    var pine_colors: Array = []
    if kind == "alpine":
        for layer in range(4):
            var cone := CylinderMesh.new()
            cone.top_radius = 0.025
            cone.bottom_radius = 2.65 - float(layer) * 0.48
            cone.height = 4.35
            cone.radial_segments = 11
            cone.rings = 2
            pine_meshes.append(cone)
            pine_transforms.append([])
            pine_colors.append(PackedColorArray())
    var canopy_mesh := SphereMesh.new()
    canopy_mesh.radius = 1.0
    canopy_mesh.height = 2.0
    canopy_mesh.radial_segments = 12
    canopy_mesh.rings = 8
    var bark := [Color(0.30, 0.21, 0.14), Color(0.37, 0.27, 0.18), Color(0.25, 0.20, 0.15)]
    var leaves := [Color(0.10, 0.27, 0.12), Color(0.16, 0.34, 0.15), Color(0.19, 0.38, 0.17), Color(0.12, 0.30, 0.14)]
    if kind == "alpine":
        leaves = [Color(0.055, 0.22, 0.13), Color(0.075, 0.28, 0.15), Color(0.09, 0.31, 0.17), Color(0.06, 0.25, 0.13)]
    var tree_index := 0
    for side_value in [-1.0, 1.0]:
        var side: float = side_value
        for i in range(count):
            var d := float(i) * spacing + spacing * 0.5 + randf_range(-2.0, 2.0)
            if d >= route_length:
                continue
            var lateral := randf_range(10.5, 16.0) if kind == "city" else (randf_range(15.0, 33.0) if kind == "coast" else randf_range(13.0, 26.0))
            var base := _point_at(d) + _right_at(d) * side * lateral
            base.y += _terrain_height_offset(d, side * lateral, kind)
            var scale := randf_range(0.78, 1.32) if kind != "city" else randf_range(0.72, 1.05)
            var rotation := Basis(Vector3.UP, randf_range(-PI, PI))
            trunk_transforms.append(Transform3D(rotation * Basis.from_scale(Vector3.ONE * scale), base + Vector3.UP * trunk_height * 0.5 * scale))
            trunk_colors.append(bark[tree_index % bark.size()])
            if kind == "alpine":
                for layer in range(4):
                    var tier_transforms: Array = pine_transforms[layer]
                    var tier_colors: PackedColorArray = pine_colors[layer]
                    tier_transforms.append(Transform3D(rotation * Basis.from_scale(Vector3.ONE * scale), base + Vector3.UP * ((2.65 + float(layer) * 2.22) * scale)))
                    tier_colors.append(leaves[(tree_index + layer) % leaves.size()])
                    pine_transforms[layer] = tier_transforms
                    pine_colors[layer] = tier_colors
            else:
                var offsets := [Vector3(0.0, 5.0, 0.0), Vector3(-0.88, 4.45, 0.12), Vector3(0.92, 4.50, -0.10), Vector3(0.12, 5.65, -0.18)]
                var scales := [Vector3(1.75, 1.55, 1.75), Vector3(1.32, 1.18, 1.35), Vector3(1.38, 1.22, 1.30), Vector3(1.18, 1.08, 1.20)]
                for part in range(offsets.size()):
                    broadleaf_transforms.append(Transform3D(rotation * Basis.from_scale(scales[part] * scale), base + rotation * offsets[part] * scale))
                    broadleaf_colors.append(leaves[(tree_index + part) % leaves.size()])
            tree_index += 1
    var bark_mat := _mat(Color.WHITE, 0.92)
    bark_mat.vertex_color_use_as_albedo = true
    var trunks := _add_instanced_mesh(course_root, "InstancedTreeTrunks", trunk_mesh, bark_mat, trunk_transforms, trunk_colors)
    trunks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    var leaf_mat := _mat(Color.WHITE, 0.91)
    leaf_mat.vertex_color_use_as_albedo = true
    if kind == "alpine":
        for layer in range(4):
            var pine := _add_instanced_mesh(course_root, "InstancedPineCanopyTier_%d" % layer, pine_meshes[layer], leaf_mat, pine_transforms[layer], pine_colors[layer])
            pine.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    else:
        var canopy := _add_instanced_mesh(course_root, "InstancedBroadleafCanopyClusters", canopy_mesh, leaf_mat, broadleaf_transforms, broadleaf_colors)
        canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _add_instanced_mesh(parent: Node3D, node_name: String, mesh: Mesh, material: Material, transforms: Array, colors: PackedColorArray = PackedColorArray()) -> MultiMeshInstance3D:
    var multi := MultiMesh.new()
    multi.transform_format = MultiMesh.TRANSFORM_3D
    multi.mesh = mesh
    multi.use_colors = colors.size() == transforms.size()
    multi.instance_count = transforms.size()
    for i in range(transforms.size()):
        multi.set_instance_transform(i, transforms[i])
        if multi.use_colors:
            multi.set_instance_color(i, colors[i])
    var instance := MultiMeshInstance3D.new()
    instance.name = node_name
    instance.multimesh = multi
    instance.material_override = material
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(instance)
    return instance


func _build_city_props() -> void:
    var facade_colors := [
        Color(0.055, 0.065, 0.105),
        Color(0.105, 0.12, 0.18),
        Color(0.16, 0.17, 0.23),
        Color(0.075, 0.105, 0.14),
    ]
    var facade_transforms: Array[Transform3D] = []
    var facade_instance_colors := PackedColorArray()
    var cool_window_transforms: Array[Transform3D] = []
    var warm_window_transforms: Array[Transform3D] = []
    var lamp_pole_transforms: Array[Transform3D] = []
    var cyan_lamp_transforms: Array[Transform3D] = []
    var warm_lamp_transforms: Array[Transform3D] = []
    var buildings_per_side := int(route_length / 48.0)

    for side_value in [-1.0, 1.0]:
        var side: float = side_value
        for i in range(buildings_per_side):
            var d := float(i) * 48.0 + 24.0
            var side_offset: float = side * randf_range(24.0, 46.0)
            var road_point := _point_at(d)
            var right := _right_at(d)
            var base := road_point + right * side_offset
            base.y += _terrain_height_offset(d, side_offset, "city")
            var height := randf_range(11.0, 38.0)
            var width := randf_range(8.0, 16.0)
            var depth := randf_range(13.0, 23.0)
            var yaw := atan2(_forward_at(d).x, -_forward_at(d).z)
            var rotation_basis := Basis(Vector3.UP, yaw)
            var facade_basis := rotation_basis * Basis.from_scale(Vector3(width, height, depth))
            var facade_origin := base + Vector3(0.0, height * 0.5, 0.0)
            facade_transforms.append(Transform3D(facade_basis, facade_origin))
            facade_instance_colors.append(facade_colors[i % facade_colors.size()])

            for floor_idx in range(int(height / 3.4)):
                var window_y := -height * 0.5 + 2.0 + float(floor_idx) * 3.2
                var window_origin := facade_origin + Vector3(0.0, window_y, 0.0)
                var window_basis := rotation_basis * Basis.from_scale(Vector3(width * 0.69, 0.15, depth + 0.06))
                var window_transform := Transform3D(window_basis, window_origin)
                if (i + floor_idx) % 3 != 0:
                    cool_window_transforms.append(window_transform)
                else:
                    warm_window_transforms.append(window_transform)

    # GPU instancing turns hundreds of separate facade/window nodes into a few draws.
    var facade_mesh := BoxMesh.new()
    facade_mesh.size = Vector3.ONE
    var facade_material := _mat(Color.WHITE, 0.48, 0.18)
    facade_material.vertex_color_use_as_albedo = true
    _add_instanced_mesh(course_root, "InstancedCityFacades", facade_mesh, facade_material, facade_transforms, facade_instance_colors)

    var window_mesh := BoxMesh.new()
    window_mesh.size = Vector3.ONE
    _add_instanced_mesh(course_root, "InstancedCyanWindows", window_mesh, _emissive_mat(Color(0.035, 0.58, 1.0), 1.75), cool_window_transforms)
    _add_instanced_mesh(course_root, "InstancedWarmWindows", window_mesh, _emissive_mat(Color(1.0, 0.28, 0.075), 1.45), warm_window_transforms)

    # Streetlights repeat along the outside of the safety rail. Their luminous
    # bars establish a night-race silhouette without a dynamic point light per lamp.
    var pole_mesh := BoxMesh.new()
    pole_mesh.size = Vector3(0.13, 6.0, 0.13)
    var lamp_mesh := BoxMesh.new()
    lamp_mesh.size = Vector3(1.3, 0.16, 0.4)
    for side_value in [-1.0, 1.0]:
        var side: float = side_value
        for i in range(int(route_length / 42.0)):
            var d := float(i) * 42.0 + 18.0
            var p := _point_at(d) + _right_at(d) * side * 10.4
            p.y += _terrain_height_offset(d, side * 10.4, "city")
            var basis := Basis.looking_at(_forward_at(d), Vector3.UP)
            lamp_pole_transforms.append(Transform3D(basis, p + Vector3.UP * 2.9))
            var lamp_pos := p + Vector3.UP * 5.95
            var lamp_transform := Transform3D(basis, lamp_pos)
            if side < 0.0:
                cyan_lamp_transforms.append(lamp_transform)
            else:
                warm_lamp_transforms.append(lamp_transform)
    _add_instanced_mesh(course_root, "InstancedStreetlightPoles", pole_mesh, _mat(Color(0.15, 0.19, 0.26), 0.35, 0.7), lamp_pole_transforms)
    _add_instanced_mesh(course_root, "CyanStreetlights", lamp_mesh, _emissive_mat(Color(0.04, 0.68, 1.0), 2.2), cyan_lamp_transforms)
    _add_instanced_mesh(course_root, "AmberStreetlights", lamp_mesh, _emissive_mat(Color(1.0, 0.28, 0.07), 1.9), warm_lamp_transforms)

func _build_traffic() -> void:
    traffic_nodes.clear()
    var traffic_index := 0
    for distance in range(145, int(route_length) - 100, 295):
        _create_traffic_car(float(distance), 2.35, traffic_index, 1)
        traffic_index += 1
    traffic_index = 0
    for distance in range(int(route_length) - 145, 100, -315):
        _create_traffic_car(float(distance), -2.35, traffic_index + 20, -1)
        traffic_index += 1


func _create_traffic_car(distance: float, lane: float, seed_id: int, direction: int) -> void:
    var root := Node3D.new()
    root.name = "TrafficVehicle_%02d" % seed_id
    course_root.add_child(root)
    var model_paths := ["res://assets/cars/titan_gt.glb", "res://assets/cars/zenith_x1.glb", "res://assets/cars/rallyfox_x.glb"]
    var packed := ResourceLoader.load(model_paths[posmod(seed_id, model_paths.size())], "PackedScene") as PackedScene
    var visual: Node3D
    if packed != null:
        var instance := packed.instantiate()
        if instance is Node3D:
            visual = instance as Node3D
            root.add_child(visual)
            _normalize_car_visual(visual, 3.85)
            _set_car_shadow(visual, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
        else:
            instance.free()
            visual = _make_traffic_fallback(root, seed_id)
    else:
        visual = _make_traffic_fallback(root, seed_id)
    var speed := randf_range(17.0, 24.0) if direction > 0 else randf_range(20.0, 28.0)
    var item := {"root": root, "visual": visual, "distance": distance, "previous_distance": distance, "original_distance": distance, "lane": lane, "speed": speed, "direction": direction}
    traffic_nodes.append(item)
    _place_traffic_item(item)


func _make_traffic_fallback(parent: Node3D, seed_id: int) -> Node3D:
    var visual := Node3D.new()
    visual.name = "TrafficFallback"
    parent.add_child(visual)
    var palette := [Color(0.62, 0.08, 0.07), Color(0.75, 0.78, 0.78), Color(0.06, 0.18, 0.43), Color(0.10, 0.11, 0.12)]
    _add_box(visual, Vector3(1.78, 0.62, 3.70), Vector3(0.0, 0.52, 0.0), _mat(palette[posmod(seed_id, palette.size())], 0.26, 0.25), "FallbackBody")
    _add_box(visual, Vector3(1.28, 0.45, 1.72), Vector3(0.0, 0.93, 0.05), _mat(Color(0.025, 0.045, 0.065), 0.14, 0.15), "FallbackGlass")
    return visual


func _set_car_shadow(node: Node, shadow_setting: int) -> void:
    if node is GeometryInstance3D:
        (node as GeometryInstance3D).cast_shadow = shadow_setting
    for child in node.get_children():
        _set_car_shadow(child, shadow_setting)


func _advance_traffic(delta: float) -> void:
    for item in traffic_nodes:
        item["previous_distance"] = float(item["distance"])
        item["distance"] = float(item["distance"]) + float(item["speed"]) * int(item["direction"]) * delta
        _place_traffic_item(item)


func _place_traffic_item(item: Dictionary) -> void:
    var d := float(item["distance"])
    var root := item["root"] as Node3D
    var visual := item["visual"] as Node3D
    if not is_instance_valid(root):
        return
    if d < 0.0 or d > route_length:
        root.visible = false
        return
    root.position = _point_at(d) + _right_at(d) * float(item["lane"]) + Vector3.UP * 0.025
    var forward := _forward_at(d)
    if int(item["direction"]) < 0:
        forward = -forward
    root.basis = Basis.looking_at(forward, Vector3.UP)
    root.visible = absf(d - travel_distance) <= 240.0
    if is_instance_valid(visual):
        visual.visible = root.visible


func _check_traffic_collisions(previous_player_distance: float, previous_player_lane: float) -> void:
    for item in traffic_nodes:
        var root := item["root"] as Node3D
        if not is_instance_valid(root) or not root.visible:
            continue
        var start_gap := float(item["previous_distance"]) - previous_player_distance
        var end_gap := float(item["distance"]) - travel_distance
        if absf(end_gap) > 3.6 and start_gap * end_gap > 0.0:
            continue
        var denominator := absf(start_gap) + absf(end_gap)
        var ratio := 1.0 if denominator < 0.001 else clampf(absf(start_gap) / denominator, 0.0, 1.0)
        var player_lane_at_contact := lerpf(previous_player_lane, lateral_offset, ratio)
        if absf(float(item["lane"]) - player_lane_at_contact) < 1.85:
            race_over = true
            current_speed = 0.0
            drive_started = false
            message_label.text = "COLLISION  •  TAP RESTART TO DRIVE AGAIN"
            return

func _build_player() -> void:
    player_root = Node3D.new()
    player_root.name = "PlayerCar"
    add_child(player_root)
    chase_camera = Camera3D.new()
    chase_camera.name = "ChaseCamera"
    chase_camera.current = true
    chase_camera.fov = 66.0
    chase_camera.near = 0.10
    chase_camera.far = 600.0
    add_child(chase_camera)


func _place_player_and_camera(delta: float) -> void:
    var point := _point_at(travel_distance) + _right_at(travel_distance) * lateral_offset
    point.y += 0.005
    player_root.position = point
    var road_forward := _forward_at(travel_distance)
    var grade := road_forward.y / maxf(Vector2(road_forward.x, road_forward.z).length(), 0.001)
    var horizontal_forward := Vector3(sin(vehicle_heading), 0.0, -cos(vehicle_heading))
    var vehicle_forward := Vector3(horizontal_forward.x, grade, horizontal_forward.z).normalized()
    if vehicle_forward.length_squared() < 0.001:
        vehicle_forward = road_forward
    player_root.basis = Basis.looking_at(vehicle_forward, Vector3.UP)
    var cam_target := point - vehicle_forward * 7.6 + Vector3.UP * 2.35
    chase_camera.global_position = chase_camera.global_position.lerp(cam_target, clampf(delta * 5.0, 0.0, 1.0))
    chase_camera.look_at(point + vehicle_forward * 12.0 + Vector3.UP * 0.65, Vector3.UP)


func _collect_bounds(node: Node, transform_to_root: Transform3D, points: Array) -> void:
    var local_transform := transform_to_root
    if node is Node3D:
        local_transform = transform_to_root * (node as Node3D).transform
    if node is MeshInstance3D and node.mesh != null:
        var bounds: AABB = node.mesh.get_aabb()
        for bits in range(8):
            var corner := bounds.position + Vector3(bounds.size.x if (bits & 1) != 0 else 0.0, bounds.size.y if (bits & 2) != 0 else 0.0, bounds.size.z if (bits & 4) != 0 else 0.0)
            points.append(local_transform * corner)
    for child in node.get_children():
        _collect_bounds(child, local_transform, points)


func _normalize_car_visual(visual: Node3D, target_length: float) -> void:
    var points: Array = []
    _collect_bounds(visual, Transform3D.IDENTITY, points)
    if points.is_empty():
        visual.scale = Vector3.ONE * 0.5
        visual.position = Vector3(0.0, 0.005, 0.0)
        return
    var low := Vector3(INF, INF, INF)
    var high := Vector3(-INF, -INF, -INF)
    for point in points:
        low = low.min(point)
        high = high.max(point)
    var dimensions := high - low
    var factor := target_length / maxf(maxf(dimensions.x, dimensions.z), 0.001)
    var yaw := PI * 0.5 if dimensions.x > dimensions.z else 0.0
    var rotation := Basis(Vector3.UP, yaw)
    var adjusted_low := Vector3(INF, INF, INF)
    var adjusted_high := Vector3(-INF, -INF, -INF)
    for point in points:
        var adjusted := rotation * point * factor
        adjusted_low = adjusted_low.min(adjusted)
        adjusted_high = adjusted_high.max(adjusted)
    visual.rotation = Vector3(0.0, yaw, 0.0)
    visual.scale = Vector3.ONE * factor
    visual.position = Vector3(-(adjusted_low.x + adjusted_high.x) * 0.5, -adjusted_low.y + 0.005, -(adjusted_low.z + adjusted_high.z) * 0.5)


func _load_selected_car() -> void:
    if is_instance_valid(car_visual):
        car_visual.free()
        car_visual = null
    var entry: Dictionary = CARS[car_index]
    var packed := ResourceLoader.load(String(entry["file"]), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
    if packed == null:
        _make_fallback_car()
        car_label.text = "%s  •  fallback model" % entry["name"]
        return
    var instance := packed.instantiate()
    if not instance is Node3D:
        instance.free()
        _make_fallback_car()
        car_label.text = "%s  •  fallback model" % entry["name"]
        return
    car_visual = instance as Node3D
    player_root.add_child(car_visual)
    _normalize_car_visual(car_visual, 4.25)
    _set_car_shadow(car_visual, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
    car_label.text = "%02d / %02d  •  %s" % [car_index + 1, CARS.size(), entry["name"]]

func _make_fallback_car() -> void:
    car_visual = Node3D.new()
    car_visual.name = "FallbackSportsCar"
    player_root.add_child(car_visual)
    var paint := _mat(Color(0.02, 0.43, 0.98), 0.2, 0.72)
    _add_box(car_visual, Vector3(1.78, 0.56, 3.9), Vector3(0.0, 0.58, 0.0), paint, "Body")
    _add_box(car_visual, Vector3(1.22, 0.51, 1.53), Vector3(0.0, 1.02, 0.12), _mat(Color(0.025, 0.07, 0.12), 0.13, 0.22), "PanoramicCabin")
    var lamp := _emissive_mat(Color(0.75, 0.92, 1.0), 1.6)
    _add_box(car_visual, Vector3(0.34, 0.12, 0.08), Vector3(-0.58, 0.57, -1.98), lamp, "HeadlampL")
    _add_box(car_visual, Vector3(0.34, 0.12, 0.08), Vector3(0.58, 0.57, -1.98), lamp, "HeadlampR")
    for x in [-0.91, 0.91]:
        for z in [-1.25, 1.25]:
            var wheel := MeshInstance3D.new()
            var wheel_mesh := CylinderMesh.new()
            wheel_mesh.top_radius = 0.37
            wheel_mesh.bottom_radius = 0.37
            wheel_mesh.height = 0.23
            wheel_mesh.radial_segments = 18
            wheel.mesh = wheel_mesh
            wheel.rotation.z = PI * 0.5
            wheel.position = Vector3(x, 0.36, z)
            wheel.material_override = _mat(Color(0.02, 0.024, 0.03), 0.95)
            car_visual.add_child(wheel)




func _build_hud() -> void:
    var layer := CanvasLayer.new()
    layer.name = "RaceHUD"
    layer.layer = 8
    add_child(layer)
    var overlay := Control.new()
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.mouse_filter = Control.MOUSE_FILTER_PASS
    layer.add_child(overlay)

    var top_panel := PanelContainer.new()
    top_panel.name = "RaceInfoPanel"
    top_panel.position = Vector2(22.0, 18.0)
    top_panel.size = Vector2(415.0, 176.0)
    top_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.015, 0.032, 0.06, 0.84), Color(0.2, 0.65, 0.91, 0.8), 16))
    overlay.add_child(top_panel)
    var info := VBoxContainer.new()
    info.add_theme_constant_override("separation", 3)
    top_panel.add_child(info)

    var logo := Label.new()
    logo.text = "TURBO TRAILS   /   3D DRIVE SIMULATION"
    logo.add_theme_font_size_override("font_size", 17)
    logo.add_theme_color_override("font_color", Color(0.36, 0.83, 1.0))
    info.add_child(logo)

    route_label = Label.new()
    route_label.add_theme_font_size_override("font_size", 21)
    route_label.add_theme_color_override("font_color", Color.WHITE)
    info.add_child(route_label)

    score_label = Label.new()
    score_label.add_theme_font_size_override("font_size", 22)
    score_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
    info.add_child(score_label)

    speed_label = Label.new()
    speed_label.add_theme_font_size_override("font_size", 18)
    speed_label.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0))
    info.add_child(speed_label)

    time_label = Label.new()
    time_label.add_theme_font_size_override("font_size", 18)
    time_label.add_theme_color_override("font_color", Color(0.78, 0.88, 0.97))
    info.add_child(time_label)

    best_time_label = Label.new()
    best_time_label.add_theme_font_size_override("font_size", 16)
    best_time_label.add_theme_color_override("font_color", Color(0.42, 0.88, 0.96))
    info.add_child(best_time_label)

    var car_panel := PanelContainer.new()
    car_panel.position = Vector2(850.0, 18.0)
    car_panel.size = Vector2(408.0, 112.0)
    car_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.015, 0.032, 0.06, 0.82), Color(0.2, 0.65, 0.91, 0.72), 16))
    overlay.add_child(car_panel)
    var car_box := VBoxContainer.new()
    car_box.add_theme_constant_override("separation", 6)
    car_panel.add_child(car_box)
    car_label = Label.new()
    car_label.add_theme_font_size_override("font_size", 18)
    car_label.add_theme_color_override("font_color", Color(1.0, 0.91, 0.63))
    car_box.add_child(car_label)
    var car_buttons := HBoxContainer.new()
    car_box.add_child(car_buttons)
    var prev_car := _make_button(car_buttons, "‹ CAR", Vector2.ZERO, Vector2(100, 40), 16)
    prev_car.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    prev_car.pressed.connect(func(): _change_car(-1))
    var next_car := _make_button(car_buttons, "NEXT CAR ›", Vector2.ZERO, Vector2(130, 40), 16)
    next_car.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    next_car.pressed.connect(func(): _change_car(1))

    var route_panel := PanelContainer.new()
    route_panel.position = Vector2(850.0, 142.0)
    route_panel.size = Vector2(408.0, 62.0)
    route_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.015, 0.032, 0.06, 0.76), Color(0.2, 0.65, 0.91, 0.56), 14))
    overlay.add_child(route_panel)
    var route_buttons := HBoxContainer.new()
    route_buttons.add_theme_constant_override("separation", 8)
    route_panel.add_child(route_buttons)
    var prev_route := _make_button(route_buttons, "‹ COURSE", Vector2.ZERO, Vector2(150, 43), 16)
    prev_route.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    prev_route.pressed.connect(func(): _change_route(-1))
    var next_route := _make_button(route_buttons, "NEXT COURSE ›", Vector2.ZERO, Vector2(190, 43), 16)
    next_route.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    next_route.pressed.connect(func(): _change_route(1))

    message_label = Label.new()
    message_label.position = Vector2(310.0, 203.0)
    message_label.size = Vector2(660.0, 48.0)
    message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    message_label.add_theme_font_size_override("font_size", 22)
    message_label.add_theme_color_override("font_color", Color.WHITE)
    overlay.add_child(message_label)

    var progress_panel := PanelContainer.new()
    progress_panel.position = Vector2(445.0, 28.0)
    progress_panel.size = Vector2(365.0, 59.0)
    progress_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.015, 0.032, 0.06, 0.76), Color(0.2, 0.65, 0.91, 0.6), 13))
    overlay.add_child(progress_panel)
    var progress_box := VBoxContainer.new()
    progress_box.add_theme_constant_override("separation", 2)
    progress_panel.add_child(progress_box)
    var progress_text := Label.new()
    progress_text.text = "RACE DISTANCE"
    progress_text.add_theme_font_size_override("font_size", 12)
    progress_text.add_theme_color_override("font_color", Color(0.64, 0.78, 0.90))
    progress_box.add_child(progress_text)
    progress_bar = ProgressBar.new()
    progress_bar.show_percentage = false
    progress_bar.custom_minimum_size = Vector2(330.0, 16.0)
    progress_bar.max_value = 100.0
    progress_bar.value = 0.0
    progress_bar.add_theme_stylebox_override("background", _bar_style(Color(0.06, 0.10, 0.15, 1.0)))
    progress_bar.add_theme_stylebox_override("fill", _bar_style(Color(0.06, 0.78, 1.0, 1.0)))
    progress_box.add_child(progress_bar)

    var left := _make_button(overlay, "◀", Vector2(25.0, 566.0), Vector2(100.0, 120.0), 34)
    left.button_down.connect(_on_left_button_down)
    left.button_up.connect(_on_left_button_up)
    var right := _make_button(overlay, "▶", Vector2(137.0, 566.0), Vector2(100.0, 120.0), 34)
    right.button_down.connect(_on_right_button_down)
    right.button_up.connect(_on_right_button_up)

    var brake := _make_button(overlay, "BRAKE", Vector2(1000.0, 585.0), Vector2(115.0, 88.0), 17)
    brake.button_down.connect(func(): brake_touch = true)
    brake.button_up.connect(func(): brake_touch = false)
    throttle_button = _make_button(overlay, "THROTTLE  ▲", Vector2(1122.0, 565.0), Vector2(136.0, 108.0), 18)
    throttle_button.button_down.connect(func(): throttle_touch = true)
    throttle_button.button_up.connect(func(): throttle_touch = false)
    var restart := _make_button(overlay, "RESTART", Vector2(870.0, 650.0), Vector2(140.0, 45.0), 15)
    restart.pressed.connect(_restart_race)
    var garage := _make_button(overlay, "GARAGE  •  C", Vector2(1018.0, 650.0), Vector2(239.0, 45.0), 15)
    garage.pressed.connect(func(): _change_car(1))


func _panel_style(color: Color, border: Color, radius: int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.border_color = border
    style.set_border_width_all(1)
    style.set_corner_radius_all(radius)
    style.content_margin_left = 12.0
    style.content_margin_right = 12.0
    style.content_margin_top = 8.0
    style.content_margin_bottom = 8.0
    return style


func _bar_style(color: Color) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.set_corner_radius_all(6)
    return style


func _make_button(parent: Control, text_value: String, button_pos: Vector2, button_size: Vector2, font_size: int) -> Button:
    var button := Button.new()
    button.text = text_value
    button.position = button_pos
    button.size = button_size
    button.focus_mode = Control.FOCUS_NONE
    button.add_theme_font_size_override("font_size", font_size)
    button.add_theme_color_override("font_color", Color.WHITE)
    var normal := _panel_style(Color(0.025, 0.07, 0.115, 0.88), Color(0.19, 0.68, 0.93, 0.78), 13)
    button.add_theme_stylebox_override("normal", normal)
    var hover := normal.duplicate() as StyleBoxFlat
    hover.bg_color = Color(0.035, 0.18, 0.29, 0.96)
    button.add_theme_stylebox_override("hover", hover)
    var pressed := normal.duplicate() as StyleBoxFlat
    pressed.bg_color = Color(0.02, 0.34, 0.52, 0.98)
    button.add_theme_stylebox_override("pressed", pressed)
    parent.add_child(button)
    return button


func _change_car(direction := 1) -> void:
    car_index = posmod(car_index + direction, CARS.size())
    _load_selected_car()
    _place_player_and_camera(0.18)


func _change_route(direction: int) -> void:
    route_index = posmod(route_index + direction, ROUTES.size())
    _rebuild_route()


func _restart_race(show_message := true) -> void:
    travel_distance = 0.0
    lateral_offset = 0.0
    current_speed = 0.0
    elapsed_time = 0.0
    race_over = false
    start_countdown = 0.0
    drive_started = false
    _release_touch_controls()
    vehicle_heading = atan2(_forward_at(0.0).x, -_forward_at(0.0).z)
    current_gear = 1
    engine_rpm = 900.0
    for item in traffic_nodes:
        item["distance"] = float(item["original_distance"])
        item["previous_distance"] = float(item["original_distance"])
        _place_traffic_item(item)
    if show_message:
        message_label.text = "READY TO DRIVE"
    _place_player_and_camera(1.0)
    _refresh_hud()

func _load_records() -> void:
    var config := ConfigFile.new()
    if config.load("user://turbo_trails_records.cfg") != OK:
        return
    for route in ROUTES:
        var route_name := String(route["name"])
        best_times[route_name] = float(config.get_value("records", route_name, 0.0))


func _save_records() -> void:
    var config := ConfigFile.new()
    for route in ROUTES:
        var route_name := String(route["name"])
        config.set_value("records", route_name, float(best_times.get(route_name, 0.0)))
    var err := config.save("user://turbo_trails_records.cfg")
    if err != OK:
        push_warning("Could not save personal-best times: " + error_string(err))


func _format_time(seconds: float) -> String:
    var total_centiseconds := maxi(0, int(round(seconds * 100.0)))
    var minutes := int(total_centiseconds / 6000)
    var whole_seconds := int((total_centiseconds / 100) % 60)
    var centiseconds := total_centiseconds % 100
    return "%02d:%02d.%02d" % [minutes, whole_seconds, centiseconds]


func _refresh_hud() -> void:
    if not is_instance_valid(score_label):
        return
    var speed_kmh := current_speed * 3.6
    current_gear = 1 if speed_kmh < 35.0 else (2 if speed_kmh < 65.0 else (3 if speed_kmh < 100.0 else (4 if speed_kmh < 135.0 else (5 if speed_kmh < 170.0 else 6))))
    engine_rpm = clampf(900.0 + speed_kmh * 31.0 + (1100.0 if throttle_touch else 0.0), 900.0, 7600.0)
    score_label.text = "GEAR  %d    RPM  %04d" % [current_gear, int(engine_rpm)]
    speed_label.text = "SPEED  %03d km/h" % int(speed_kmh)
    time_label.text = "TIME  %s    TRIP  %.2f km" % [_format_time(elapsed_time), travel_distance / 1000.0]
    var saved_best := float(best_times.get(String(ROUTES[route_index]["name"]), 0.0))
    best_time_label.text = "BEST  %s" % (_format_time(saved_best) if saved_best > 0.0 else "--:--.--")
    progress_bar.value = clampf(travel_distance / maxf(route_length, 1.0) * 100.0, 0.0, 100.0)
