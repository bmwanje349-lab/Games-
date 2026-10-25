extends Node3D
## Turbo Trails: multi-course arcade racer. Course geometry is generated once per route
## and repeated scenery is instanced to keep draw-call pressure reasonable on phones.

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

const ROAD_WIDTH := 14.0
const ROAD_HALF := ROAD_WIDTH * 0.5
const SAMPLE_STEP := 4.0
const CRUISE_SPEED := 47.0
const BOOST_SPEED := 67.0
const BRAKE_SPEED := 18.0
const LANE_LIMIT := 5.0
const COIN_SCORE := 250
const ROAD_DASH_LENGTH := 7.0

var route_index := 0
var car_index := 0
var route_length := 4800.0
var travel_distance := 0.0
var lateral_offset := 0.0
var current_speed := CRUISE_SPEED
var elapsed_time := 0.0
var coins_collected := 0
var race_over := false
var start_countdown := 3.0
var steering_touch := 0.0
var brake_touch := false
var boost_touch := false
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

var coin_nodes: Array[Dictionary] = []
var obstacle_nodes: Array[Dictionary] = []
var checkpoint_distances: Array[float] = []
var next_checkpoint := 0

var score_label: Label
var speed_label: Label
var car_label: Label
var route_label: Label
var time_label: Label
var message_label: Label
var progress_bar: ProgressBar
var nitro_bar: ProgressBar
var boost_button: Button


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
    # A stalled or resumed frame must not jump the car past pickups, gates, or
    # collisions. Cap simulation time and use swept-distance checks below.
    delta = clampf(delta, 0.0, 0.05)
    if race_over:
        _refresh_hud()
        return

    if start_countdown > 0.0:
        start_countdown = maxf(0.0, start_countdown - delta)
        current_speed = 0.0
        if start_countdown > 0.0:
            message_label.text = "GET READY  •  %d" % int(ceil(start_countdown))
        else:
            message_label.text = "GO!  •  FIND THE RACING LINE"
        _place_player_and_camera(delta)
        _refresh_hud()
        return

    elapsed_time += delta
    var previous_lateral_offset := lateral_offset
    var steer := steering_touch
    if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
        steer -= 1.0
    if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
        steer += 1.0
    steer = clampf(steer, -1.0, 1.0)

    var braking := brake_touch or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
    var boosting := (boost_touch or Input.is_key_pressed(KEY_SPACE)) and not braking
    var target_speed := CRUISE_SPEED
    if braking:
        target_speed = BRAKE_SPEED
    elif boosting and nitro_bar.value > 0.0:
        target_speed = BOOST_SPEED
        nitro_bar.value = maxf(0.0, nitro_bar.value - 28.0 * delta)
    else:
        nitro_bar.value = minf(100.0, nitro_bar.value + 8.5 * delta)

    current_speed = move_toward(current_speed, target_speed, (48.0 if boosting else 37.0) * delta)
    var steering_response := lerpf(5.6, 3.9, current_speed / BOOST_SPEED)
    lateral_offset = clampf(lateral_offset + steer * steering_response * delta * 6.0, -LANE_LIMIT, LANE_LIMIT)
    if absf(steer) > 0.01:
        steering_mouse = false

    var previous_distance := travel_distance
    travel_distance = minf(route_length, travel_distance + current_speed * delta)
    _place_player_and_camera(delta)
    _check_pickups_and_collisions(previous_distance, previous_lateral_offset)
    # A crash must end the frame before checkpoints or finish logic can overwrite
    # the crash message or award a finish on the same frame.
    if race_over:
        _refresh_hud()
        return

    while next_checkpoint < checkpoint_distances.size() and travel_distance >= checkpoint_distances[next_checkpoint]:
        next_checkpoint += 1
        message_label.text = "CHECKPOINT %d / %d" % [next_checkpoint, checkpoint_distances.size()]
    elif message_label.text.begins_with("CHECKPOINT") and next_checkpoint > 0:
        message_label.text = "KEEP PUSHING  •  USE NITRO ON THE STRAIGHTS"

    if travel_distance >= route_length:
        race_over = true
        current_speed = 0.0
        var route_name := String(ROUTES[route_index]["name"])
        var previous_best := float(best_times.get(route_name, 0.0))
        var is_record := previous_best <= 0.0 or elapsed_time < previous_best
        if is_record:
            best_times[route_name] = elapsed_time
            _save_records()
            message_label.text = "NEW PERSONAL BEST!  •  %s" % _format_time(elapsed_time)
        else:
            message_label.text = "FINISH!  •  %s" % _format_time(elapsed_time)
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
    if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
        _release_touch_controls()


func _release_touch_controls() -> void:
    steering_touch = 0.0
    brake_touch = false
    boost_touch = false


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
        uvs.append(Vector2(0.0, distance / 8.0))
        uvs.append(Vector2(1.0, distance / 8.0))
        if i < steps:
            var idx := i * 2
            indices.append_array(PackedInt32Array([idx, idx + 1, idx + 2, idx + 1, idx + 3, idx + 2]))
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices
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


func _build_route_surface() -> void:
    var route: Dictionary = ROUTES[route_index]
    var asphalt: Material = _make_asphalt_material(route)
    var shoulder: Material = _mat(route["shoulder"], 0.94)
    var edge_paint := _mat(Color(0.94, 0.91, 0.78), 0.78)
    var yellow_paint := _mat(Color(1.0, 0.70, 0.08), 0.74)

    _make_ribbon(course_root, "WideSafetyShoulder", -ROAD_HALF - 2.5, ROAD_HALF + 2.5, -0.13, shoulder)
    _make_ribbon(course_root, "MainRoadSurface", -ROAD_HALF, ROAD_HALF, 0.0, asphalt)
    _make_ribbon(course_root, "LeftWhiteEdge", -ROAD_HALF + 0.18, -ROAD_HALF + 0.43, 0.018, edge_paint)
    _make_ribbon(course_root, "RightWhiteEdge", ROAD_HALF - 0.43, ROAD_HALF - 0.18, 0.018, edge_paint)
    _make_ribbon(course_root, "CenterDashLeft", -0.20, -0.07, 0.022, yellow_paint, ROAD_DASH_LENGTH * 2.0)
    _make_ribbon(course_root, "CenterDashRight", 0.07, 0.20, 0.022, yellow_paint, ROAD_DASH_LENGTH * 2.0)

    # Intermittent white lane marks give the road scale without creating thousands of nodes.
    _make_dashed_lane_markings()
    _make_racing_curbs(route)

    var rail_mat := _mat(Color(0.54, 0.60, 0.65), 0.32, 0.72)
    var rail_glint := _mat(Color(0.79, 0.84, 0.88), 0.3, 0.66)
    _make_ribbon(course_root, "LeftGuardrailLower", -ROAD_HALF - 1.65, -ROAD_HALF - 1.48, 0.55, rail_mat)
    _make_ribbon(course_root, "RightGuardrailLower", ROAD_HALF + 1.48, ROAD_HALF + 1.65, 0.55, rail_mat)
    _make_ribbon(course_root, "LeftGuardrailTop", -ROAD_HALF - 1.65, -ROAD_HALF - 1.48, 1.05, rail_glint)
    _make_ribbon(course_root, "RightGuardrailTop", ROAD_HALF + 1.48, ROAD_HALF + 1.65, 1.05, rail_glint)
    _make_guardrail_posts(rail_mat)


func _make_asphalt_material(route: Dictionary) -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 asphalt_color : source_color = vec4(0.10, 0.11, 0.12, 1.0);

float hash_cell(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
    vec2 uv = UV;
    float fine_grain = hash_cell(floor(uv * vec2(150.0, 190.0)));
    float coarse_grain = hash_cell(floor(uv * vec2(5.0, 12.0)));
    float speckle = (fine_grain - 0.5) * 0.105;
    float patch = (coarse_grain - 0.5) * 0.075;
    ALBEDO = asphalt_color.rgb * (0.91 + speckle + patch);
    ROUGHNESS = 0.93;
    METALLIC = 0.015;
    SPECULAR = 0.20;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("asphalt_color", route["asphalt"])
    return material


func _make_racing_curbs(route: Dictionary) -> void:
    var curb_mesh := BoxMesh.new()
    curb_mesh.size = Vector3(0.60, 0.075, 8.5)
    var transforms: Array[Transform3D] = []
    var colors := PackedColorArray()
    var accent: Color = route["accent"]
    var ivory := Color(0.94, 0.93, 0.86)
    var segments := int(route_length / 9.0)
    for i in range(segments):
        var d := float(i) * 9.0 + 4.5
        var basis := Basis.looking_at(_forward_at(d), Vector3.UP)
        var strip_color := accent if i % 2 == 0 else ivory
        for side_value in [-1.0, 1.0]:
            var side: float = side_value
            var point := _point_at(d) + _right_at(d) * side * (ROAD_HALF - 0.60) + Vector3.UP * 0.045
            transforms.append(Transform3D(basis, point))
            colors.append(strip_color)
    var curb_material := _mat(Color.WHITE, 0.7, 0.0)
    curb_material.vertex_color_use_as_albedo = true
    _add_instanced_mesh(course_root, "InstancedRaceKerbs", curb_mesh, curb_material, transforms, colors)


func _make_dashed_lane_markings() -> void:
    var count := int(route_length / 24.0)
    var dash_mesh := BoxMesh.new()
    dash_mesh.size = Vector3(0.11, 0.025, 7.2)
    var dash_multi := MultiMesh.new()
    dash_multi.transform_format = MultiMesh.TRANSFORM_3D
    dash_multi.mesh = dash_mesh
    dash_multi.instance_count = count * 2
    var idx := 0
    for i in range(count):
        var d := 14.0 + float(i) * 24.0
        var point := _point_at(d)
        var forward := _forward_at(d)
        var basis := Basis.looking_at(forward, Vector3.UP)
        for lane_x in [-3.3, 3.3]:
            var pos: Vector3 = point + _right_at(d) * float(lane_x) + Vector3.UP * 0.035
            dash_multi.set_instance_transform(idx, Transform3D(basis, pos))
            idx += 1
    var instance := MultiMeshInstance3D.new()
    instance.name = "InstancedLaneDashes"
    instance.multimesh = dash_multi
    instance.material_override = _mat(Color(0.88, 0.89, 0.85), 0.72)
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    course_root.add_child(instance)


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
    _build_race_objects()
    _build_race_gates()
    _restart_race(false)
    route_label.text = "%02d / %02d   %s" % [route_index + 1, ROUTES.size(), route["name"]]
    message_label.text = "%s  •  READY TO RACE" % route["subtitle"]
    _refresh_hud()


func _build_landscape() -> void:
    var route: Dictionary = ROUTES[route_index]
    var ground_mat := _mat(route["ground"], 1.0)
    var terrain := MeshInstance3D.new()
    terrain.name = "Terrain"
    var plane := PlaneMesh.new()
    plane.size = Vector2(1000.0, route_length + 700.0)
    plane.subdivide_width = 1
    plane.subdivide_depth = 1
    terrain.mesh = plane
    terrain.position = Vector3(0.0, -3.0, -route_length * 0.5)
    terrain.material_override = ground_mat
    terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    course_root.add_child(terrain)

    if route["kind"] == "coast":
        var water := MeshInstance3D.new()
        water.name = "Ocean"
        var ocean_mesh := PlaneMesh.new()
        ocean_mesh.size = Vector2(580.0, route_length + 1000.0)
        water.mesh = ocean_mesh
        water.position = Vector3(-258.0, -4.1, -route_length * 0.5)
        var water_mat := _mat(Color(0.025, 0.24, 0.39), 0.22, 0.35)
        water.material_override = water_mat
        course_root.add_child(water)
        _add_coastal_cliffs()

    elif route["kind"] == "alpine":
        _add_alpine_ridge()

    else:
        var city_ground := _mat(Color(0.035, 0.04, 0.075), 0.96)
        _add_box(course_root, Vector3(180.0, 0.35, route_length + 200.0), Vector3(0.0, -2.72, -route_length * 0.5), city_ground, "UrbanPlinth")


func _add_coastal_cliffs() -> void:
    var rock_mat := _mat(Color(0.50, 0.44, 0.33), 0.98)
    var mesh := SphereMesh.new()
    mesh.radius = 1.0
    mesh.height = 2.0
    mesh.radial_segments = 10
    mesh.rings = 6
    var multi := MultiMesh.new()
    multi.transform_format = MultiMesh.TRANSFORM_3D
    multi.mesh = mesh
    var count := int(route_length / 18.0)
    multi.instance_count = count
    for i in range(count):
        var d := float(i) * 18.0
        var point := _point_at(d) + _right_at(d) * randf_range(18.0, 43.0)
        var sx := randf_range(4.0, 15.0)
        var sy := randf_range(4.0, 18.0)
        var sz := randf_range(5.0, 17.0)
        multi.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(sx, sy, sz)), point + Vector3(0.0, sy * 0.38 - 1.8, 0.0)))
    var cliffs := MultiMeshInstance3D.new()
    cliffs.name = "CoastalRockFormations"
    cliffs.multimesh = multi
    cliffs.material_override = rock_mat
    cliffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    course_root.add_child(cliffs)


func _add_alpine_ridge() -> void:
    var rock_mesh := SphereMesh.new()
    rock_mesh.radius = 1.0
    rock_mesh.height = 2.0
    rock_mesh.radial_segments = 12
    rock_mesh.rings = 6
    var rock_multi := MultiMesh.new()
    rock_multi.transform_format = MultiMesh.TRANSFORM_3D
    rock_multi.mesh = rock_mesh
    var count := int(route_length / 26.0) * 2
    rock_multi.instance_count = count
    var index := 0
    for side in [-1.0, 1.0]:
        for i in range(int(route_length / 26.0)):
            var d := float(i) * 26.0 + 8.0
            var base: Vector3 = _point_at(d) + _right_at(d) * side * randf_range(21.0, 42.0)
            var height := randf_range(13.0, 43.0)
            var width := randf_range(10.0, 25.0)
            rock_multi.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3(width, height, width * 1.2)), base + Vector3(0.0, height * 0.34, 0.0)))
            index += 1
    var peaks := MultiMeshInstance3D.new()
    peaks.name = "AlpineRockRidge"
    peaks.multimesh = rock_multi
    peaks.material_override = _mat(Color(0.29, 0.34, 0.36), 0.99)
    peaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    course_root.add_child(peaks)

    var snow_mesh := SphereMesh.new()
    snow_mesh.radius = 1.0
    snow_mesh.height = 2.0
    snow_mesh.radial_segments = 10
    snow_mesh.rings = 5
    var snow_multi := MultiMesh.new()
    snow_multi.transform_format = MultiMesh.TRANSFORM_3D
    snow_multi.mesh = snow_mesh
    snow_multi.instance_count = int(route_length / 55.0) * 2
    index = 0
    for side in [-1.0, 1.0]:
        for i in range(int(route_length / 55.0)):
            var d := float(i) * 55.0 + 12.0
            var base: Vector3 = _point_at(d) + _right_at(d) * side * randf_range(44.0, 68.0)
            var scale := randf_range(4.5, 11.0)
            snow_multi.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3(scale * 1.35, scale, scale)), base + Vector3(0.0, scale * 0.7, 0.0)))
            index += 1
    var snow := MultiMeshInstance3D.new()
    snow.name = "SnowHighlights"
    snow.multimesh = snow_multi
    snow.material_override = _mat(Color(0.72, 0.79, 0.82), 0.95)
    snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    course_root.add_child(snow)


func _build_route_props() -> void:
    var kind: String = ROUTES[route_index]["kind"]
    if kind == "city":
        _build_city_props()
    else:
        _build_nature_props(kind)


func _build_nature_props(kind: String) -> void:
    var count := int(route_length / 13.0)
    var trunk_mesh := CylinderMesh.new()
    trunk_mesh.top_radius = 0.13 if kind == "coast" else 0.20
    trunk_mesh.bottom_radius = 0.22 if kind == "coast" else 0.30
    trunk_mesh.height = 3.0 if kind == "coast" else 4.0
    trunk_mesh.radial_segments = 8
    var canopy_mesh := SphereMesh.new()
    canopy_mesh.radius = 1.25 if kind == "coast" else 1.7
    canopy_mesh.height = 2.65 if kind == "coast" else 3.2
    canopy_mesh.radial_segments = 10
    canopy_mesh.rings = 6
    var trunk_multi := MultiMesh.new()
    trunk_multi.transform_format = MultiMesh.TRANSFORM_3D
    trunk_multi.mesh = trunk_mesh
    var canopy_multi := MultiMesh.new()
    canopy_multi.transform_format = MultiMesh.TRANSFORM_3D
    canopy_multi.mesh = canopy_mesh
    var tree_total := count * 2
    trunk_multi.instance_count = tree_total
    canopy_multi.instance_count = tree_total

    var crown_colors := [
        Color(0.07, 0.30, 0.14) if kind == "coast" else Color(0.06, 0.22, 0.12),
        Color(0.12, 0.38, 0.16) if kind == "coast" else Color(0.12, 0.29, 0.13),
        Color(0.17, 0.34, 0.16) if kind == "coast" else Color(0.15, 0.25, 0.13),
    ]
    var idx := 0
    for side in [-1.0, 1.0]:
        for i in range(count):
            var d := float(i) * 13.0 + 4.0
            var offset := randf_range(13.0, 33.0) if kind == "coast" else randf_range(12.0, 26.0)
            var tree_pos: Vector3 = _point_at(d) + _right_at(d) * side * offset
            var scale := randf_range(0.68, 1.42)
            var trunk_scale := Basis.from_scale(Vector3(scale, scale, scale))
            trunk_multi.set_instance_transform(idx, Transform3D(trunk_scale, tree_pos + Vector3(0.0, 1.5 * scale - 2.7, 0.0)))
            canopy_multi.set_instance_transform(idx, Transform3D(trunk_scale, tree_pos + Vector3(0.0, 3.1 * scale - 1.2, 0.0)))
            idx += 1
    var trunks := MultiMeshInstance3D.new()
    trunks.name = "InstancedTreeTrunks"
    trunks.multimesh = trunk_multi
    trunks.material_override = _mat(Color(0.25, 0.15, 0.085) if kind == "coast" else Color(0.30, 0.28, 0.22), 0.96)
    trunks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    course_root.add_child(trunks)
    var canopies := MultiMeshInstance3D.new()
    canopies.name = "InstancedCanopies"
    canopies.multimesh = canopy_multi
    canopies.material_override = _mat(crown_colors[0].lerp(crown_colors[1], 0.55), 0.92)
    canopies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    course_root.add_child(canopies)


func _add_instanced_mesh(parent: Node3D, node_name: String, mesh: Mesh, material: Material, transforms: Array[Transform3D], colors: PackedColorArray = PackedColorArray()) -> MultiMeshInstance3D:
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
            var height := randf_range(11.0, 38.0)
            var width := randf_range(8.0, 16.0)
            var depth := randf_range(13.0, 23.0)
            var yaw := atan2(_forward_at(d).x, -_forward_at(d).z)
            var rotation_basis := Basis(Vector3.UP, yaw)
            var facade_basis := rotation_basis * Basis.from_scale(Vector3(width, height, depth))
            var facade_origin := base + Vector3(0.0, height * 0.5 - 2.7, 0.0)
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

    # Five illuminated overhead gates work as visual landmarks between sectors.
    var cyan := _emissive_mat(Color(0.04, 0.70, 1.0), 1.8)
    var warm := _emissive_mat(Color(1.0, 0.34, 0.10), 1.35)
    for d in [300.0, 1150.0, 2100.0, 3100.0, 3900.0]:
        if d < route_length:
            var gate := Node3D.new()
            gate.name = "NeonGantry"
            gate.position = _point_at(d) + Vector3(0.0, 7.4, 0.0)
            gate.rotation.y = atan2(_forward_at(d).x, -_forward_at(d).z)
            course_root.add_child(gate)
            _add_box(gate, Vector3(0.22, 7.0, 0.28), Vector3(-ROAD_WIDTH * 0.55, -3.6, 0.0), cyan, "LeftPillar")
            _add_box(gate, Vector3(0.22, 7.0, 0.28), Vector3(ROAD_WIDTH * 0.55, -3.6, 0.0), warm, "RightPillar")
            _add_box(gate, Vector3(ROAD_WIDTH * 1.15, 0.22, 0.3), Vector3(0.0, 0.0, 0.0), cyan, "TopBar")


func _build_race_objects() -> void:
    coin_nodes.clear()
    obstacle_nodes.clear()
    checkpoint_distances.clear()
    next_checkpoint = 0

    for i in range(1, 7):
        checkpoint_distances.append(route_length * float(i) / 7.0)

    var coin_mat := _emissive_mat(Color(1.0, 0.65, 0.075), 1.25)
    var coin_mesh := CylinderMesh.new()
    coin_mesh.top_radius = 0.48
    coin_mesh.bottom_radius = 0.48
    coin_mesh.height = 0.13
    coin_mesh.radial_segments = 20
    for i in range(1, int(route_length / 33.0)):
        var d := float(i) * 33.0 + 20.0
        if d >= route_length - 65.0:
            continue
        var lane: float = [-4.4, -2.2, 0.0, 2.2, 4.4][i % 5]
        var coin := MeshInstance3D.new()
        coin.name = "PickupCoin"
        coin.mesh = coin_mesh
        coin.material_override = coin_mat
        coin.position = _point_at(d) + _right_at(d) * lane + Vector3.UP * 1.15
        coin.rotation.x = PI * 0.5
        course_root.add_child(coin)
        coin_nodes.append({"root": coin, "distance": d, "lane": lane, "taken": false})

    for i in range(1, int(route_length / 67.0)):
        var d := float(i) * 67.0 + 47.0
        if d >= route_length - 90.0 or i % 4 == 0:
            continue
        var lane: float = [-4.45, -2.2, 0.0, 2.2, 4.45][(i * 3 + route_index) % 5]
        if i % 3 == 0:
            _create_traffic_car(d, lane, i)
        elif i % 3 == 1:
            _create_barrier(d, lane, i)
        else:
            _create_boost_pad(d, lane, i)


func _create_traffic_car(distance: float, lane: float, seed_id: int) -> void:
    var root := Node3D.new()
    root.name = "TrafficVehicle_%02d" % seed_id
    root.position = _point_at(distance) + _right_at(distance) * lane
    root.basis = Basis.looking_at(_forward_at(distance), Vector3.UP)
    course_root.add_child(root)
    var palette := [Color(0.76, 0.08, 0.075), Color(0.83, 0.78, 0.63), Color(0.05, 0.29, 0.78), Color(0.075, 0.09, 0.12), Color(0.92, 0.40, 0.06)]
    _add_box(root, Vector3(1.8, 0.64, 3.6), Vector3(0.0, 0.58, 0.0), _mat(palette[seed_id % palette.size()], 0.27, 0.27), "Body")
    _add_box(root, Vector3(1.3, 0.50, 1.62), Vector3(0.0, 1.06, 0.10), _mat(Color(0.028, 0.06, 0.095), 0.16, 0.18), "Glass")
    var headlamp := _emissive_mat(Color(0.78, 0.91, 1.0), 1.4)
    _add_box(root, Vector3(0.35, 0.12, 0.08), Vector3(-0.57, 0.59, -1.82), headlamp, "LeftHeadlight")
    _add_box(root, Vector3(0.35, 0.12, 0.08), Vector3(0.57, 0.59, -1.82), headlamp, "RightHeadlight")
    for x in [-0.94, 0.94]:
        for z in [-1.12, 1.12]:
            var wheel := MeshInstance3D.new()
            var mesh := CylinderMesh.new()
            mesh.top_radius = 0.34
            mesh.bottom_radius = 0.34
            mesh.height = 0.22
            mesh.radial_segments = 12
            wheel.mesh = mesh
            wheel.rotation.z = PI * 0.5
            wheel.position = Vector3(x, 0.34, z)
            wheel.material_override = _mat(Color(0.018, 0.022, 0.028), 0.95)
            root.add_child(wheel)
    obstacle_nodes.append({"root": root, "distance": distance, "original_distance": distance, "lane": lane, "kind": "car"})


func _create_barrier(distance: float, lane: float, seed_id: int) -> void:
    var root := Node3D.new()
    root.name = "TrackBarrier_%02d" % seed_id
    root.position = _point_at(distance) + _right_at(distance) * lane
    root.basis = Basis.looking_at(_forward_at(distance), Vector3.UP)
    course_root.add_child(root)
    _add_box(root, Vector3(1.35, 0.76, 0.76), Vector3(0.0, 0.4, 0.0), _mat(Color(0.94, 0.24, 0.045), 0.58), "BarrierBody")
    _add_box(root, Vector3(1.38, 0.15, 0.79), Vector3(0.0, 0.57, 0.0), _mat(Color(0.96, 0.88, 0.69), 0.6), "ReflectiveBand")
    obstacle_nodes.append({"root": root, "distance": distance, "original_distance": distance, "lane": lane, "kind": "barrier"})


func _create_boost_pad(distance: float, lane: float, seed_id: int) -> void:
    var root := Node3D.new()
    root.name = "NitroPad_%02d" % seed_id
    root.position = _point_at(distance) + _right_at(distance) * lane + Vector3.UP * 0.055
    root.basis = Basis.looking_at(_forward_at(distance), Vector3.UP)
    course_root.add_child(root)
    var pad_mat := _emissive_mat(Color(0.06, 0.80, 1.0), 1.4)
    _add_box(root, Vector3(1.65, 0.09, 3.5), Vector3.ZERO, pad_mat, "BoostPad")
    obstacle_nodes.append({"root": root, "distance": distance, "original_distance": distance, "lane": lane, "kind": "boost"})


func _build_race_gates() -> void:
    var start_mat := _emissive_mat(Color(0.10, 0.85, 1.0), 1.2)
    var finish_mat := _emissive_mat(Color(1.0, 0.63, 0.11), 1.6)
    _create_race_gate(16.0, "START", start_mat)
    for i in range(checkpoint_distances.size()):
        _create_race_gate(checkpoint_distances[i], "CHECKPOINT %02d" % (i + 1), start_mat if i % 2 == 0 else finish_mat)
    _create_race_gate(route_length - 18.0, "FINISH", finish_mat)


func _create_race_gate(distance: float, sign_text: String, accent_material: Material) -> void:
    var gate := Node3D.new()
    gate.name = "RaceGate_" + sign_text.replace(" ", "_")
    gate.position = _point_at(distance)
    gate.basis = Basis.looking_at(_forward_at(distance), Vector3.UP)
    course_root.add_child(gate)

    var dark_metal := _mat(Color(0.035, 0.06, 0.09), 0.28, 0.72)
    _add_box(gate, Vector3(0.34, 5.9, 0.40), Vector3(-9.15, 2.95, 0.0), dark_metal, "LeftUpright")
    _add_box(gate, Vector3(0.34, 5.9, 0.40), Vector3(9.15, 2.95, 0.0), dark_metal, "RightUpright")
    _add_box(gate, Vector3(18.8, 0.45, 0.58), Vector3(0.0, 5.85, 0.0), accent_material, "IlluminatedCrossbar")
    _add_box(gate, Vector3(8.2, 1.08, 0.45), Vector3(0.0, 4.92, 0.36), _mat(Color(0.015, 0.03, 0.05), 0.35, 0.25), "SignPanel")

    var sign := Label3D.new()
    sign.name = "GateSign"
    sign.text = sign_text
    sign.font_size = 82
    sign.pixel_size = 0.010
    sign.outline_size = 10
    sign.outline_modulate = Color(0.005, 0.01, 0.02, 1.0)
    sign.modulate = Color(1.0, 1.0, 1.0, 1.0)
    sign.position = Vector3(0.0, 4.68, 0.62)
    sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    gate.add_child(sign)


func _build_player() -> void:
    player_root = Node3D.new()
    player_root.name = "PlayerCar"
    add_child(player_root)
    chase_camera = Camera3D.new()
    chase_camera.name = "ChaseCamera"
    chase_camera.current = true
    chase_camera.fov = 73.0
    chase_camera.near = 0.06
    chase_camera.far = 600.0
    add_child(chase_camera)


func _place_player_and_camera(delta: float) -> void:
    var point := _point_at(travel_distance) + _right_at(travel_distance) * lateral_offset
    point.y += 0.09
    player_root.position = point
    var forward := _forward_at(travel_distance)
    player_root.basis = Basis.looking_at(forward, Vector3.UP)
    # Keep the imported model's normalization offset; resetting its X coordinate
    # here mis-centres vehicles whose source pivot is not at the origin.
    var cam_target := point - forward * 9.4 + Vector3.UP * 4.3
    chase_camera.global_position = chase_camera.global_position.lerp(cam_target, clampf(delta * 4.2, 0.0, 1.0))
    var look_target := point + forward * 13.0 + Vector3.UP * 1.0
    chase_camera.look_at(look_target, Vector3.UP)
    if is_instance_valid(car_visual):
        car_visual.rotation.z = -steering_touch * 0.035


func _collect_bounds(node: Node, transform_to_root: Transform3D, points: Array) -> void:
    var local_transform := transform_to_root
    if node is Node3D:
        local_transform = transform_to_root * (node as Node3D).transform
    if node is MeshInstance3D and node.mesh != null:
        var bounds: AABB = node.mesh.get_aabb()
        for bits in range(8):
            var corner := bounds.position + Vector3(
                bounds.size.x if (bits & 1) != 0 else 0.0,
                bounds.size.y if (bits & 2) != 0 else 0.0,
                bounds.size.z if (bits & 4) != 0 else 0.0
            )
            points.append(local_transform * corner)
    for child in node.get_children():
        _collect_bounds(child, local_transform, points)


func _load_selected_car() -> void:
    if is_instance_valid(car_visual):
        # Free immediately before loading the next model to avoid a one-frame
        # overlap of two full-resolution car scenes on memory-constrained phones.
        car_visual.free()
        car_visual = null
    var entry: Dictionary = CARS[car_index]
    var packed: PackedScene = null
    # Exported Godot packages remap imported .glb files to generated .scn
    # resources and may omit the original GLB bytes. ResourceLoader resolves
    # that remap; FileAccess.file_exists does not reliably do so.
    # IGNORE_DEEP also avoids retaining all nine cars' textures in the global
    # resource cache after players cycle through the garage.
    packed = ResourceLoader.load(String(entry["file"]), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
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
    var points: Array = []
    _collect_bounds(car_visual, Transform3D.IDENTITY, points)
    if points.is_empty():
        car_visual.scale = Vector3.ONE * 0.5
        car_visual.position.y = 0.14
    else:
        var low := Vector3(INF, INF, INF)
        var high := Vector3(-INF, -INF, -INF)
        for point in points:
            low = low.min(point)
            high = high.max(point)
        var dimensions := high - low
        var longest := maxf(dimensions.x, dimensions.z)
        var factor := 4.25 / maxf(longest, 0.001)
        var yaw := PI * 0.5 if dimensions.x > dimensions.z else 0.0
        car_visual.rotation.y = yaw
        car_visual.scale = Vector3.ONE * factor
        var center := (low + high) * 0.5
        var offset := -(Basis(Vector3.UP, yaw) * Vector3(center.x * factor, 0.0, center.z * factor))
        offset.y = -low.y * factor
        car_visual.position = offset
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


func _check_pickups_and_collisions(previous_distance: float = -1.0, previous_lane: float = INF) -> void:
    if previous_distance < 0.0:
        previous_distance = travel_distance
    if is_inf(previous_lane):
        previous_lane = lateral_offset

    for item in coin_nodes:
        if item["taken"]:
            continue
        var item_distance := float(item["distance"])
        var item_lane := _lane_at_distance(item_distance, previous_distance, travel_distance, previous_lane, lateral_offset)
        if not _crossed_distance(item_distance, previous_distance, travel_distance, 2.4) or absf(float(item["lane"]) - item_lane) >= 1.55:
            item["taken"] = true
            var coin_root: Node3D = item["root"]
            if is_instance_valid(coin_root):
                coin_root.visible = false
            coins_collected += 1
            score_label.text = "SCORE  %07d" % _score()
    for obstacle in obstacle_nodes:
        var obstacle_distance := float(obstacle["distance"])
        var obstacle_lane := _lane_at_distance(obstacle_distance, previous_distance, travel_distance, previous_lane, lateral_offset)
        var lane_gap := absf(float(obstacle["lane"]) - obstacle_lane)
        if _crossed_distance(obstacle_distance, previous_distance, travel_distance, 2.15) and lane_gap < 1.45:
            if obstacle["kind"] == "boost":
                nitro_bar.value = minf(100.0, nitro_bar.value + 32.0)
                obstacle["distance"] = -10000.0
                var pad: Node3D = obstacle["root"]
                if is_instance_valid(pad):
                    pad.visible = false
                message_label.text = "NITRO PICKUP  •  BOOST REFILLED"
            else:
                race_over = true
                current_speed = 0.0
                message_label.text = "CRASH!  •  TAP RESTART TO TRY AGAIN"
                return


func _crossed_distance(target: float, from_distance: float, to_distance: float, tolerance: float) -> bool:
    var low := minf(from_distance, to_distance) - tolerance
    var high := maxf(from_distance, to_distance) + tolerance
    return target >= low and target <= high


func _lane_at_distance(target_distance: float, from_distance: float, to_distance: float, from_lane: float, to_lane: float) -> float:
    var span := to_distance - from_distance
    if absf(span) < 0.0001:
        return to_lane
    var ratio := clampf((target_distance - from_distance) / span, 0.0, 1.0)
    return lerpf(from_lane, to_lane, ratio)


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
    logo.text = "TURBO TRAILS   /   ARCADE RACING"
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

    var nitro_panel := PanelContainer.new()
    nitro_panel.position = Vector2(445.0, 97.0)
    nitro_panel.size = Vector2(365.0, 47.0)
    nitro_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.015, 0.032, 0.06, 0.74), Color(0.18, 0.68, 0.95, 0.58), 13))
    overlay.add_child(nitro_panel)
    var nitro_box := VBoxContainer.new()
    nitro_box.add_theme_constant_override("separation", 1)
    nitro_panel.add_child(nitro_box)
    var nitro_title := Label.new()
    nitro_title.text = "NITRO"
    nitro_title.add_theme_font_size_override("font_size", 12)
    nitro_title.add_theme_color_override("font_color", Color(0.47, 0.87, 1.0))
    nitro_box.add_child(nitro_title)
    nitro_bar = ProgressBar.new()
    nitro_bar.show_percentage = false
    nitro_bar.max_value = 100.0
    nitro_bar.value = 100.0
    nitro_bar.custom_minimum_size = Vector2(330.0, 14.0)
    nitro_bar.add_theme_stylebox_override("background", _bar_style(Color(0.06, 0.10, 0.15, 1.0)))
    nitro_bar.add_theme_stylebox_override("fill", _bar_style(Color(0.0, 0.75, 1.0, 1.0)))
    nitro_box.add_child(nitro_bar)

    var left := _make_button(overlay, "◀", Vector2(25.0, 566.0), Vector2(100.0, 120.0), 34)
    left.button_down.connect(func(): steering_touch = -1.0)
    left.button_up.connect(func(): steering_touch = 0.0)
    var right := _make_button(overlay, "▶", Vector2(137.0, 566.0), Vector2(100.0, 120.0), 34)
    right.button_down.connect(func(): steering_touch = 1.0)
    right.button_up.connect(func(): steering_touch = 0.0)

    var brake := _make_button(overlay, "BRAKE", Vector2(1000.0, 585.0), Vector2(115.0, 88.0), 17)
    brake.button_down.connect(func(): brake_touch = true)
    brake.button_up.connect(func(): brake_touch = false)
    boost_button = _make_button(overlay, "NITRO  ▶", Vector2(1122.0, 565.0), Vector2(136.0, 108.0), 19)
    boost_button.button_down.connect(func(): boost_touch = true)
    boost_button.button_up.connect(func(): boost_touch = false)
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
    # Restore pickups as well as counters. Otherwise restart would show a zero
    # coin score while every previously collected coin remained invisible.
    for item in coin_nodes:
        item["taken"] = false
        var coin_root := item["root"] as Node3D
        if is_instance_valid(coin_root):
            coin_root.visible = true
    for obstacle in obstacle_nodes:
        obstacle["distance"] = float(obstacle.get("original_distance", obstacle["distance"]))
        var obstacle_root := obstacle["root"] as Node3D
        if is_instance_valid(obstacle_root):
            obstacle_root.visible = true

    travel_distance = 0.0
    lateral_offset = 0.0
    current_speed = 0.0
    elapsed_time = 0.0
    coins_collected = 0
    race_over = false
    start_countdown = 3.0
    steering_touch = 0.0
    brake_touch = false
    boost_touch = false
    next_checkpoint = 0
    nitro_bar.value = 100.0
    if show_message:
        message_label.text = "GET READY"
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


func _score() -> int:
    return int(travel_distance * 2.0) + coins_collected * COIN_SCORE


func _format_time(seconds: float) -> String:
    # Format rounded centiseconds as integer fields so 59.999 seconds rolls over
    # to 01:00.00 instead of displaying the impossible 00:60.00.
    var total_centiseconds := maxi(0, int(round(seconds * 100.0)))
    var minutes := int(total_centiseconds / 6000)
    var whole_seconds := int((total_centiseconds / 100) % 60)
    var centiseconds := total_centiseconds % 100
    return "%02d:%02d.%02d" % [minutes, whole_seconds, centiseconds]


func _refresh_hud() -> void:
    if not is_instance_valid(score_label):
        return
    score_label.text = "SCORE  %07d" % _score()
    speed_label.text = "SPEED  %03d km/h" % int(current_speed * 3.6)
    time_label.text = "TIME  %s    COINS  %03d" % [_format_time(elapsed_time), coins_collected]
    var saved_best := float(best_times.get(String(ROUTES[route_index]["name"]), 0.0))
    best_time_label.text = "BEST  %s" % (_format_time(saved_best) if saved_best > 0.0 else "--:--.--")
    progress_bar.value = clampf(travel_distance / maxf(route_length, 1.0) * 100.0, 0.0, 100.0)
    if is_instance_valid(boost_button):
        boost_button.disabled = nitro_bar.value <= 0.0
