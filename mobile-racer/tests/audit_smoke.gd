extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run_audit")

func _expect(condition: bool, detail: String) -> void:
    if condition:
        print("AUDIT_TEST_PASS: " + detail)
    else:
        failures.append(detail)
        push_error("AUDIT_TEST_FAIL: " + detail)

func _run_audit() -> void:
    var packed := load("res://scenes/main.tscn") as PackedScene
    _expect(packed != null, "main scene loads")
    if packed == null:
        quit(1)
        return
    var game := packed.instantiate()
    game.process_mode = Node.PROCESS_MODE_DISABLED
    root.add_child(game)
    await process_frame

    var player := game.get("player_root") as Node3D
    var camera := game.get("chase_camera") as Camera3D
    var course := game.get("course_root") as Node3D
    _expect(is_instance_valid(player), "player node created")
    _expect(is_instance_valid(camera), "chase camera created")
    _expect(course != null and course.has_node("PBRAsphaltRoad"), "PBR road created")
    _expect(course != null and course.has_node("ContouredPBRLandscape"), "contoured terrain created")
    _expect(course != null and course.has_node("InstancedTreeTrunks"), "3D trees created")
    _expect(course != null and course.has_node("LeftGravelShoulder") and course.has_node("RightGravelShoulder"), "separate gravel shoulders flank the road")
    _expect(course != null and course.has_node("UpperCrashBarrierRails") and course.has_node("LowerCrashBarrierRails") and course.has_node("CrashBarrierPosts"), "upright 3D crash barrier rails and posts created")
    if course == null or not is_instance_valid(player) or not is_instance_valid(camera):
        print("AUDIT_TEST_RESULT: %d failure(s)" % failures.size())
        quit(1)
        return

    for texture_path in [
        "res://assets/environment/asphalt_track_diff_1k.jpg",
        "res://assets/environment/asphalt_track_nor_gl_1k.jpg",
        "res://assets/environment/asphalt_track_rough_1k.jpg",
        "res://assets/environment/gravel_road_diff_1k.jpg",
        "res://assets/environment/forrest_ground_01_diff_1k.jpg"
    ]:
        _expect(ResourceLoader.exists(texture_path), "PBR asset exists: " + texture_path)
    var road := course.get_node("PBRAsphaltRoad") as MeshInstance3D
    var road_material := road.material_override as StandardMaterial3D
    _expect(road_material.albedo_texture != null, "road uses diffuse texture")
    _expect(road_material.normal_enabled and road_material.normal_texture != null, "road uses normal map")
    _expect(road_material.albedo_texture.resource_path.find("asphalt_track_diff_1k.jpg") != -1, "road uses race-track tarmac PBR texture")
    var road_arrays: Array = (road.mesh as ArrayMesh).surface_get_arrays(0)
    var road_vertices: PackedVector3Array = road_arrays[Mesh.ARRAY_VERTEX]
    _expect(road_vertices.size() >= int(float(game.get("route_length"))), "road curve is sampled finely for smoother bends")
    var roadbed_offset := float(game.call("_terrain_height_offset", 0.0, 0.0, "coast"))
    _expect(roadbed_offset >= -0.06 and roadbed_offset <= -0.02, "roadbed terrain sits within 6 cm of the pavement")

    var traffic = game.get("traffic_nodes")
    _expect(traffic is Array and traffic.size() >= 10, "moving traffic generated")

    game.call("_on_left_button_down")
    _expect(is_equal_approx(float(game.get("steering_touch")), -1.0), "left touch steers left")
    game.call("_on_right_button_down")
    _expect(is_zero_approx(float(game.get("steering_touch"))), "opposing touch inputs cancel")
    game.call("_on_left_button_up")
    _expect(is_equal_approx(float(game.get("steering_touch")), 1.0), "other steering touch remains held")
    game.set("brake_touch", true)
    game.set("throttle_touch", true)
    game.call("_notification", Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    _expect(is_zero_approx(float(game.get("steering_touch"))) and not game.get("brake_touch") and not game.get("throttle_touch"), "focus loss releases controls")

    game.call("_restart_race", false)
    game.set("travel_distance", 5.0)
    game.set("throttle_touch", true)
    game.call("_process", 0.05)
    _expect(float(game.get("current_speed")) > 0.0, "throttle accelerates")
    game.call("_process", 0.05)
    game.call("_process", 0.05)
    _expect(bool(game.get("drive_started")), "timer starts once the car is rolling")
    var speed_after_throttle := float(game.get("current_speed"))
    game.set("throttle_touch", false)
    game.call("_process", 0.05)
    _expect(float(game.get("current_speed")) < speed_after_throttle, "released throttle applies drag")
    game.set("current_speed", 22.0)
    game.set("steering_touch", 1.0)
    var old_heading := float(game.get("vehicle_heading"))
    game.call("_process", 0.05)
    _expect(absf(wrapf(float(game.get("vehicle_heading")) - old_heading, -PI, PI)) > 0.001, "steering changes vehicle heading")

    var car_paths := [
        "res://assets/cars/zenith_x1.glb", "res://assets/cars/apex_v12r.glb",
        "res://assets/cars/titan_gt.glb", "res://assets/cars/rallyfox_x.glb",
        "res://assets/cars/volt_e_rs.glb", "res://assets/cars/phantom_blackline.glb",
        "res://assets/cars/tempest_roadster.glb", "res://assets/cars/monarch_svr.glb",
        "res://assets/cars/viper_street_rs.glb"
    ]
    for car_path in car_paths:
        _expect(ResourceLoader.exists(car_path), "car resource resolves: " + car_path)
    for i in range(9):
        game.call("_change_car", 1)
        await process_frame
        var car := game.get("car_visual") as Node3D
        var label := game.get("car_label") as Label
        _expect(is_instance_valid(car), "garage car %d instantiates" % (i + 1))
        _expect(label != null and label.text.find("fallback model") == -1, "garage car %d uses real model" % (i + 1))
        if is_instance_valid(car):
            var points: Array = []
            game.call("_collect_bounds", car, Transform3D.IDENTITY, points)
            var lowest := INF
            for point in points:
                lowest = minf(lowest, (point as Vector3).y)
            _expect(not points.is_empty() and lowest >= -0.003 and lowest <= 0.025, "garage car %d tyre/body bounds meet road plane" % (i + 1))

    var routes_seen: Dictionary = {}
    for i in range(3):
        var old_course := game.get("course_root") as Node3D
        game.call("_change_route", 1)
        await process_frame
        course = game.get("course_root") as Node3D
        _expect(course != null and course.has_node("PBRAsphaltRoad"), "route %d rebuilds road" % (i + 1))
        _expect(course != null and course.has_node("ContouredPBRLandscape"), "route %d rebuilds terrain" % (i + 1))
        _expect(not is_instance_valid(old_course), "route %d releases old course" % (i + 1))
        var route_label := game.get("route_label") as Label
        if route_label != null:
            routes_seen[route_label.text] = true
        var route_traffic = game.get("traffic_nodes")
        _expect(route_traffic is Array and route_traffic.size() >= 10, "route %d creates traffic" % (i + 1))
    _expect(routes_seen.size() == 3, "all three courses are selectable")

    game.set("throttle_touch", true)
    game.set("brake_touch", true)
    game.set("current_speed", 24.0)
    game.call("_restart_race", false)
    _expect(is_zero_approx(float(game.get("current_speed"))), "restart stops vehicle")
    _expect(not game.get("throttle_touch") and not game.get("brake_touch"), "restart releases pedals")
    var reset_traffic = game.get("traffic_nodes")
    var traffic_reset_ok := true
    for item in reset_traffic:
        if not is_equal_approx(float(item["distance"]), float(item["original_distance"])):
            traffic_reset_ok = false
    _expect(traffic_reset_ok, "restart restores traffic positions")

    if reset_traffic.size() > 0:
        var first: Dictionary = reset_traffic[0]
        var d := float(first["original_distance"])
        var lane := float(first["lane"])
        game.set("travel_distance", d)
        game.set("lateral_offset", lane)
        first["previous_distance"] = d + 5.0
        first["distance"] = d - 1.0
        game.call("_check_traffic_collisions", d - 5.0, lane)
        _expect(bool(game.get("race_over")), "traffic collision ends drive")
        var collision_label := game.get("message_label") as Label
        _expect(collision_label != null and collision_label.text.begins_with("COLLISION"), "collision message is displayed")

    game.call("_restart_race", false)
    var finish_distance := float(game.get("route_length")) - 1.0
    var tangent: Vector3 = game.call("_forward_at", finish_distance)
    game.set("travel_distance", finish_distance)
    game.set("vehicle_heading", atan2(tangent.x, -tangent.z))
    game.set("current_speed", 32.0)
    game.set("drive_started", true)
    game.call("_process", 0.05)
    _expect(bool(game.get("race_over")), "finish line ends drive")
    var finish_label := game.get("message_label") as Label
    _expect(finish_label != null and finish_label.text.begins_with("STAGE COMPLETE"), "stage completion is displayed")
    _expect(String(game.call("_format_time", 59.999)) == "01:00.00", "timer rounds at minute boundary")
    _expect(String(game.call("_format_time", 0.0)) == "00:00.00", "timer formats zero")

    print("AUDIT_TEST_RESULT: %d failure(s)" % failures.size())
    quit(1 if not failures.is_empty() else 0)
