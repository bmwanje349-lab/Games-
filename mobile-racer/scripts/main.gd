extends Node3D
## First playable mobile-racer foundation. Course geometry is generated at runtime.

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

const ROAD_WIDTH := 12.0
const ROAD_LENGTH := 8200.0
const ROAD_START_Z := 250.0
const ROAD_END_Z := ROAD_START_Z - ROAD_LENGTH
const CRUISE_SPEED := 34.0
const BOOST_SPEED := 49.0

var car_root: Node3D
var car_visual: Node3D
var car_index := 0
var current_speed := CRUISE_SPEED
var steering_touch := 0.0
var brake_touch := false
var boost_touch := false
var coins_collected := 0
var game_over := false
var score_label: Label
var car_label: Label
var message_label: Label
var speed_label: Label
var coin_nodes: Array[Node3D] = []
var obstacle_nodes: Array[Dictionary] = []


func _ready() -> void:
    randomize()
    _build_environment()
    _build_track()
    _build_scenery()
    _build_player()
    _build_pickups_and_traffic()
    _build_hud()
    _load_selected_car()
    message_label.text = "GO!  •  Collect coins and avoid traffic"


func _process(delta: float) -> void:
    if game_over:
        _update_hud()
        return
    var keyboard_steer := Input.get_axis("ui_left", "ui_right")
    if Input.is_key_pressed(KEY_A):
        keyboard_steer = -1.0
    elif Input.is_key_pressed(KEY_D):
        keyboard_steer = 1.0
    var steer := clampf(keyboard_steer + steering_touch, -1.0, 1.0)
    var braking := brake_touch or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
    var boosting := boost_touch or Input.is_key_pressed(KEY_SPACE)
    var target_speed := 0.0 if braking else (BOOST_SPEED if boosting else CRUISE_SPEED)
    current_speed = move_toward(current_speed, target_speed, (31.0 if boosting else 45.0) * delta)
    car_root.position.x = clampf(car_root.position.x + steer * (5.0 + current_speed * 0.12) * delta, -4.35, 4.35)
    car_root.position.z -= current_speed * delta
    _update_camera(delta)
    _check_pickups_and_collisions()
    if car_root.position.z <= ROAD_END_Z + 160.0:
        game_over = true
        current_speed = 0.0
        message_label.text = "FINISH LINE  •  Tap RESTART to race again"
    _update_hud()


func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_C:
            _change_car()
        elif event.keycode == KEY_R:
            _restart_race()


func _build_environment() -> void:
    var world := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var sky_mat := ProceduralSkyMaterial.new()
    sky_mat.sky_top_color = Color(0.10, 0.27, 0.53)
    sky_mat.sky_horizon_color = Color(0.64, 0.79, 0.93)
    sky_mat.ground_bottom_color = Color(0.15, 0.20, 0.18)
    sky_mat.ground_horizon_color = Color(0.56, 0.63, 0.61)
    sky.sky_material = sky_mat
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_energy = 0.65
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.fog_enabled = true
    env.fog_light_color = Color(0.65, 0.77, 0.88)
    env.fog_density = 0.0018
    world.environment = env
    add_child(world)

    var sun := DirectionalLight3D.new()
    sun.name = "Sun"
    sun.rotation_degrees = Vector3(-43.0, -28.0, 0.0)
    sun.light_energy = 1.25
    sun.shadow_enabled = true
    add_child(sun)


func _mat(color: Color, roughness := 0.75, metallic := 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
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


func _build_track() -> void:
    var asphalt := _mat(Color(0.075, 0.085, 0.095), 0.94)
    var grass := _mat(Color(0.15, 0.34, 0.17), 1.0)
    _add_box(self, Vector3(500.0, 0.15, ROAD_LENGTH), Vector3(0.0, -0.28, ROAD_START_Z - ROAD_LENGTH * 0.5), grass, "Terrain")
    _add_box(self, Vector3(ROAD_WIDTH, 0.24, ROAD_LENGTH), Vector3(0.0, -0.14, ROAD_START_Z - ROAD_LENGTH * 0.5), asphalt, "Road")

    var stripe_mat := _mat(Color(0.96, 0.94, 0.80), 0.65)
    var stripe_mesh := BoxMesh.new()
    stripe_mesh.size = Vector3(0.105, 0.012, 4.2)
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.mesh = stripe_mesh
    var dash_count := int(ceil(ROAD_LENGTH / 18.0))
    mm.instance_count = dash_count * 2
    var index := 0
    for i in range(dash_count):
        var z := ROAD_START_Z - 7.0 - float(i) * 18.0
        for x in [-2.0, 2.0]:
            mm.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3(x, 0.0, z)))
            index += 1
    var stripes := MultiMeshInstance3D.new()
    stripes.name = "InstancedLaneMarkings"
    stripes.multimesh = mm
    stripes.material_override = stripe_mat
    add_child(stripes)

    var edge_mat := _mat(Color(0.91, 0.91, 0.84), 0.58)
    var rail_mat := _mat(Color(0.45, 0.51, 0.55), 0.34, 0.55)
    for x in [-5.7, 5.7]:
        _add_box(self, Vector3(0.12, 0.02, ROAD_LENGTH), Vector3(x, 0.0, ROAD_START_Z - ROAD_LENGTH * 0.5), edge_mat, "RoadEdgeLine")
    for x in [-7.0, 7.0]:
        _add_box(self, Vector3(0.17, 0.62, ROAD_LENGTH), Vector3(x, 0.34, ROAD_START_Z - ROAD_LENGTH * 0.5), rail_mat, "GuardRail")
        for i in range(0, int(ROAD_LENGTH / 20.0)):
            _add_box(self, Vector3(0.22, 0.82, 0.20), Vector3(x, 0.34, ROAD_START_Z - float(i) * 20.0), rail_mat, "RailPost")


func _build_scenery() -> void:
    var trunk_mesh := CylinderMesh.new()
    trunk_mesh.top_radius = 0.16
    trunk_mesh.bottom_radius = 0.24
    trunk_mesh.height = 2.8
    trunk_mesh.radial_segments = 7
    var leaves_mesh := SphereMesh.new()
    leaves_mesh.radius = 1.32
    leaves_mesh.height = 2.7
    leaves_mesh.radial_segments = 8
    leaves_mesh.rings = 5

    var trunk_multi := MultiMesh.new()
    trunk_multi.transform_format = MultiMesh.TRANSFORM_3D
    trunk_multi.mesh = trunk_mesh
    var leaves_multi := MultiMesh.new()
    leaves_multi.transform_format = MultiMesh.TRANSFORM_3D
    leaves_multi.mesh = leaves_mesh

    var per_side := int(ROAD_LENGTH / 24.0)
    var count := per_side * 2
    trunk_multi.instance_count = count
    leaves_multi.instance_count = count
    var idx := 0
    for side in [-1.0, 1.0]:
        for i in range(per_side):
            var z := ROAD_START_Z - float(i) * 24.0 - 5.0
            var x := side * randf_range(9.0, 17.5)
            var scale := randf_range(0.72, 1.28)
            var tree_basis := Basis.from_scale(Vector3(scale, scale, scale))
            trunk_multi.set_instance_transform(idx, Transform3D(tree_basis, Vector3(x, 1.4 * scale, z)))
            leaves_multi.set_instance_transform(idx, Transform3(tree_basis, Vector3(x, 3.1 * scale, z)))
            idx += 1
    var trunks := MultiMeshInstance3D.new()
    trunks.name = "InstancedTreeTrunks"
    trunks.multimesh = trunk_multi
    trunks.material_override = _mat(Color(0.25, 0.14, 0.07), 1.0)
    add_child(trunks)
    var leaves := MultiMeshInstance3D.new()
    leaves.name = "InstancedTreeCanopies"
    leaves.multimesh = leaves_multi
    leaves.material_override = _mat(Color(0.10, 0.32, 0.12), 0.95)
    add_child(leaves)


func _build_player() -> void:
    car_root = Node3D.new()
    car_root.name = "PlayerCar"
    car_root.position = Vector3(0.0, 0.025, 0.0)
    add_child(car_root)
    var chase := Camera3D.new()
    chase.name = "ChaseCamera"
    chase.current = true
    chase.fov = 72.0
    chase.near = 0.08
    chase.far = 450.0
    chase.position = Vector3(0.0, 3.4, 7.8)
    car_root.add_child(chase)
    chase.look_at(Vector3(0.0, 1.0, -8.5), Vector3.UP)


func _collect_bounds(node: Node, transform_to_root: Transform3D, points: Array) -> void:
    var local_transform := transform_to_root * node.transform if node is Node3D else transform_to_root
    if node is MeshInstance3D and node.mesh != null:
        var box: AABB = node.mesh.get_aabb()
        for bits in range(8):
            var corner := box.position + Vector3(
                box.size.x if (bits & 1) != 0 else 0.0,
                box.size.y if (bits & 2) != 0 else 0.0,
                box.size.z if (bits & 4) != 0 else 0.0
            )
            points.append(local_transform * corner)
    for child in node.get_children():
        _collect_bounds(child, local_transform, points)


func _load_selected_car() -> void:
    if is_instance_valid(car_visual):
        car_visual.queue_free()
        car_visual = null
    var entry: Dictionary = CARS[car_index]
    var packed := load(entry["file"]) as PackedScene
    if packed == null:
        _make_fallback_car()
        car_label.text = "%s  •  waiting for source model import" % entry["name"]
        return
    var instance := packed.instantiate()
    if not instance is Node3D:
        instance.free()
        _make_fallback_car()
        return
    car_visual = instance as Node3D
    car_root.add_child(car_visual)
    var points: Array = []
    _collect_bounds(car_visual, Transform3D.IDENTITY, points)
    if points.is_empty():
        car_visual.scale = Vector3.ONE * 0.5
        car_visual.position.y = 0.12
    else:
        var low := Vector3(INF, INF, INF)
        var high := Vector3(-INF, -INF, -INF)
        for point in points:
            low = low.min(point)
            high = high.max(point)
        var dimensions := high - low
        var longest := maxf(dimensions.x, dimensions.z)
        var factor := 4.35 / maxf(longest, 0.001)
        var yaw := PI * 0.5 if dimensions.x > dimensions.z else 0.0
        car_visual.rotation.y = yaw
        car_visual.scale = Vector3.ONE * factor
        var center := (low + high) * 0.5
        var offset := -(Basis(Vector3.UP, yaw) * Vector3(center.x * factor, 0.0, center.z * factor))
        offset.y = -low.y * factor
        car_visual.position = offset
    car_label.text = "%02d / %02d  •  %s" % [car_index + 1, CARS.size(), entry["name"]]


func _make_fallback_car() -> void:
    if is_instance_valid(car_visual):
        car_visual.queue_free()
    car_visual = Node3D.new()
    car_visual.name = "FallbackSportsCar"
    car_root.add_child(car_visual)
    _add_box(car_visual, Vector3(1.7, 0.58, 3.8), Vector3(0, 0.58, 0), _mat(Color(0.02, 0.42, 0.95), 0.24, 0.62), "Body")
    _add_box(car_visual, Vector3(1.22, 0.52, 1.45), Vector3(0, 1.03, 0.12), _mat(Color(0.055, 0.085, 0.12), 0.12, 0.18), "GlassCabin")
    for x in [-0.91, 0.91]:
        for z in [-1.22, 1.22]:
            var wheel_mesh := CylinderMesh.new()
            wheel_mesh.top_radius = 0.38
            wheel_mesh.bottom_radius = 0.38
            wheel_mesh.height = 0.24
            wheel_mesh.radial_segments = 16
            var wheel := MeshInstance3D.new()
            wheel.mesh = wheel_mesh
            wheel.rotation.z = PI * 0.5
            wheel.position = Vector3(x, 0.37, z)
            wheel.material_override = _mat(Color(0.025, 0.03, 0.035), 0.9)
            car_visual.add_child(wheel)


func _build_pickups_and_traffic() -> void:
    var gold := _mat(Color(1.0, 0.69, 0.06), 0.23, 0.75)
    var coin_mesh := CylinderMesh.new()
    coin_mesh.top_radius = 0.48
    coin_mesh.bottom_radius = 0.48
    coin_mesh.height = 0.12
    coin_mesh.radial_segments = 20
    for i in range(1, 105):
        var z := -float(i) * 61.0 - 35.0
        var coin := MeshInstance3D.new()
        coin.name = "Coin"
        coin.mesh = coin_mesh
        coin.material_override = gold
        coin.rotation.x = PI * 0.5
        coin.position = Vector3([-3.6, 0.0, 3.6][randi_range(0, 2)], 1.0, z)
        add_child(coin)
        coin_nodes.append(coin)
    for i in range(1, 82):
        var z := -float(i) * 76.0 - 80.0
        var lane_x: float = [-3.55, 0.0, 3.55][randi_range(0, 2)]
        if i % 3 == 0:
            _create_traffic_car(Vector3(lane_x, 0.0, z), i)
        else:
            _create_barrier(Vector3(lane_x, 0.0, z), i)


func _create_traffic_car(position_3d: Vector3, seed_id: int) -> void:
    var root := Node3D.new()
    root.name = "TrafficCar_%02d" % seed_id
    root.position = position_3d
    add_child(root)
    var colors := [Color(0.78, 0.12, 0.09), Color(0.86, 0.81, 0.66), Color(0.08, 0.28, 0.68), Color(0.12, 0.14, 0.16), Color(0.78, 0.45, 0.08)]
    _add_box(root, Vector3(1.75, 0.66, 3.55), Vector3(0, 0.58, 0), _mat(colors[seed_id % colors.size()], 0.3, 0.25), "TrafficBody")
    _add_box(root, Vector3(1.27, 0.46, 1.55), Vector3(0, 1.06, 0.1), _mat(Color(0.06, 0.10, 0.14), 0.13, 0.12), "TrafficGlass")
    for x in [-0.94, 0.94]:
        for z in [-1.12, 1.12]:
            var wheel_mesh := CylinderMesh.new()
            wheel_mesh.top_radius = 0.34
            wheel_mesh.bottom_radius = 0.34
            wheel_mesh.height = 0.22
            wheel_mesh.radial_segments = 12
            var wheel := MeshInstance3D.new()
            wheel.mesh = wheel_mesh
            wheel.rotation.z = PI * 0.5
            wheel.position = Vector3(x, 0.34, z)
            wheel.material_override = _mat(Color(0.02, 0.025, 0.03), 0.92)
            root.add_child(wheel)
    obstacle_nodes.append({"root": root, "x": position_3d.x, "z": position_3d.z, "kind": "car"})


func _create_barrier(position_3d: Vector3, seed_id: int) -> void:
    var root := Node3D.new()
    root.name = "Barrier_%02d" % seed_id
    root.position = position_3d
    add_child(root)
    _add_box(root, Vector3(1.25, 0.82, 0.75), Vector3(0, 0.42, 0), _mat(Color(0.95, 0.33, 0.045), 0.52), "BarrierBody")
    _add_box(root, Vector3(1.3, 0.16, 0.79), Vector3(0, 0.56, 0), _mat(Color(0.96, 0.88, 0.68), 0.6), "ReflectiveStripe")
    obstacle_nodes.append({"root": root, "x": position_3d.x, "z": position_3d.z, "kind": "barrier"})


func _check_pickups_and_collisions() -> void:
    var player_pos: Vector3 = car_root.position
    for coin in coin_nodes:
        if is_instance_valid(coin) and not coin.is_queued_for_deletion():
            if absf(coin.position.z - player_pos.z) < 2.1 and absf(coin.position.x - player_pos.x) < 1.35:
                coins_collected += 1
                coin.queue_free()
    for obstacle in obstacle_nodes:
        var root: Node3D = obstacle["root"]
        if is_instance_valid(root):
            var dz: float = absf(float(obstacle["z"]) - player_pos.z)
            var dx: float = absf(float(obstacle["x"]) - player_pos.x)
            if dz < 2.15 and dx < (1.55 if obstacle["kind"] == "car" else 1.1):
                game_over = true
                current_speed = 0.0
                message_label.text = "CRASH!  •  Tap RESTART to race again"
                return


func _update_camera(delta: float) -> void:
    var camera := car_root.get_node_or_null("ChaseCamera") as Camera3D
    if camera == null:
        return
    var target_pos := car_root.position + Vector3(0.0, 3.3, 8.4)
    camera.global_position = camera.global_position.lerp(target_pos, clampf(delta * 4.0, 0.0, 1.0))
    camera.look_at(car_root.global_position + Vector3(0.0, 0.7, -9.5), Vector3.UP)


func _build_hud() -> void:
    var layer := CanvasLayer.new()
    layer.name = "HUD"
    add_child(layer)
    var overlay := Control.new()
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    layer.add_child(overlay)

    score_label = Label.new()
    score_label.position = Vector2(26, 19)
    score_label.size = Vector2(450, 46)
    score_label.add_theme_font_size_override("font_size", 30)
    score_label.add_theme_color_override("font_color", Color.WHITE)
    overlay.add_child(score_label)
    speed_label = Label.new()
    speed_label.position = Vector2(28, 63)
    speed_label.size = Vector2(340, 32)
    speed_label.add_theme_font_size_override("font_size", 19)
    speed_label.add_theme_color_override("font_color", Color(0.82, 0.92, 1.0))
    overlay.add_child(speed_label)
    car_label = Label.new()
    car_label.position = Vector2(28, 101)
    car_label.size = Vector2(650, 30)
    car_label.add_theme_font_size_override("font_size", 18)
    car_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.38))
    overlay.add_child(car_label)
    message_label = Label.new()
    message_label.position = Vector2(0, 150)
    message_label.size = Vector2(1280, 42)
    message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    message_label.add_theme_font_size_override("font_size", 23)
    message_label.add_theme_color_override("font_color", Color.WHITE)
    overlay.add_child(message_label)

    var left := _make_button(overlay, "◀", Vector2(26, 566), Vector2(94, 112), 34)
    left.button_down.connect(func(): steering_touch = -1.0)
    left.button_up.connect(func(): steering_touch = 0.0)
    var right := _make_button(overlay, "▶", Vector2(132, 566), Vector2(94, 112), 34)
    right.button_down.connect(func(): steering_touch = 1.0)
    right.button_up.connect(func(): steering_touch = 0.0)
    var brake := _make_button(overlay, "BRAKE", Vector2(1000, 578), Vector2(112, 92), 18)
    brake.button_down.connect(func(): brake_touch = true)
    brake.button_up.connect(func(): brake_touch = false)
    var boost := _make_button(overlay, "BOOST", Vector2(1120, 578), Vector2(126, 92), 18)
    boost.button_down.connect(func(): boost_touch = true)
    boost.button_up.connect(func(): boost_touch = false)
    var swap := _make_button(overlay, "CHANGE CAR", Vector2(1040, 25), Vector2(204, 56), 17)
    swap.pressed.connect(_change_car)
    var restart := _make_button(overlay, "RESTART", Vector2(1040, 88), Vector2(204, 50), 17)
    restart.pressed.connect(_restart_race)


func _make_button(parent: Control, label_text: String, button_pos: Vector2, button_size: Vector2, font_size: int) -> Button:
    var button := Button.new()
    button.text = label_text
    button.position = button_pos
    button.size = button_size
    button.focus_mode = Control.FOCUS_NONE
    button.add_theme_font_size_override("font_size", font_size)
    button.add_theme_color_override("font_color", Color.WHITE)
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.025, 0.065, 0.11, 0.76)
    style.border_color = Color(0.35, 0.78, 1.0, 0.92)
    style.set_border_width_all(2)
    style.set_corner_radius_all(15)
    style.content_margin_left = 8.0
    style.content_margin_right = 8.0
    button.add_theme_stylebox_override("normal", style)
    var hover := style.duplicate() as StyleBoxFlat
    hover.bg_color = Color(0.06, 0.22, 0.34, 0.93)
    button.add_theme_stylebox_override("hover", hover)
    var pressed := style.duplicate() as StyleBoxFlat
    pressed.bg_color = Color(0.02, 0.42, 0.68, 0.96)
    button.add_theme_stylebox_override("pressed", pressed)
    parent.add_child(button)
    return button


func _change_car() -> void:
    car_index = (car_index + 1) % CARS.size()
    _load_selected_car()


func _restart_race() -> void:
    car_root.position = Vector3(0.0, 0.025, 0.0)
    current_speed = CRUISE_SPEED
    coins_collected = 0
    game_over = false
    steering_touch = 0.0
    brake_touch = false
    boost_touch = false
    for coin in coin_nodes:
        if is_instance_valid(coin):
            coin.queue_free()
    for obstacle in obstacle_nodes:
        var root: Node3D = obstacle["root"]
        if is_instance_valid(root):
            root.queue_free()
    coin_nodes.clear()
    obstacle_nodes.clear()
    _build_pickups_and_traffic()
    message_label.text = "GO!  •  Collect coins and avoid traffic"


func _update_hud() -> void:
    if not is_instance_valid(score_label):
        return
    var distance := int(maxf(0.0, -car_root.position.z))
    var score := distance * 2 + coins_collected * 100
    score_label.text = "SCORE  %07d" % score
    speed_label.text = "SPEED  %03d km/h    COINS  %03d" % [int(current_speed * 3.6), coins_collected]
