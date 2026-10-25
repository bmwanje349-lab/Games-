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

    _expect(is_instance_valid(game.get("player_root")), "player root created")
    _expect(is_instance_valid(game.get("chase_camera")), "chase camera created")
    _expect(is_instance_valid(game.get("course_root")), "initial course created")
    var course := game.get("course_root") as Node3D
    _expect(course != null and course.has_node("MainRoadSurface"), "initial course has road surface")
    _expect(game.get("coin_nodes").size() > 20, "coin pickups generated")
    _expect(game.get("obstacle_nodes").size() > 10, "traffic and obstacles generated")
    _expect(String(game.call("_format_time", 59.999)) == "01:00.00", "timer rounds across minute boundary")
    _expect(String(game.call("_format_time", 0.0)) == "00:00.00", "timer formats zero correctly")

    # Cycle every model through the real garage loader. The audit is intended to
    # catch missing/broken imported scenes rather than merely count the manifest.
    for i in range(9):
        game.call("_change_car", 1)
        await process_frame
        var car := game.get("car_visual") as Node3D
        var car_label := game.get("car_label") as Label
        _expect(is_instance_valid(car), "garage model %d instantiates" % (i + 1))
        _expect(car_label != null and car_label.text.find("fallback model") == -1,
            "garage model %d loads without fallback" % (i + 1))

    # Exercise route teardown/rebuild and confirm all three routes are selectable.
    var seen_routes: Dictionary = {}
    for i in range(3):
        var old_course := game.get("course_root") as Node3D
        game.call("_change_route", 1)
        await process_frame
        course = game.get("course_root") as Node3D
        _expect(course != null and course.has_node("MainRoadSurface"), "route %d builds" % (i + 1))
        _expect(not is_instance_valid(old_course), "route %d releases previous course" % (i + 1))
        var route_label := game.get("route_label") as Label
        if route_label != null:
            seen_routes[route_label.text] = true
    _expect(seen_routes.size() == 3, "all three routes are reachable")

    # Test that pickup collection follows a short segment rather than requiring a
    # single frame to land exactly on the pickup coordinate.
    game.call("_restart_race", false)
    var coins = game.get("coin_nodes")
    var target_coin: Dictionary = {}
    for coin in coins:
        if not coin["taken"]:
            target_coin = coin
            break
    _expect(not target_coin.is_empty(), "a test coin is available")
    if not target_coin.is_empty():
        var coin_distance := float(target_coin["distance"])
        var coin_lane := float(target_coin["lane"])
        game.set("travel_distance", coin_distance + 0.5)
        game.set("lateral_offset", coin_lane)
        game.call("_check_pickups_and_collisions", coin_distance - 1.0, coin_lane)
        _expect(int(game.get("coins_collected")) == 1, "swept pickup collection works")

    # An obstacle impact must end the race and keep the crash message.
    game.call("_restart_race", false)
    _expect(int(game.get("coins_collected")) == 0, "restart resets coin score")
    if not target_coin.is_empty():
        _expect(not bool(target_coin["taken"]), "restart makes collected coin available again")
        var reset_coin_root := target_coin["root"] as Node3D
        _expect(is_instance_valid(reset_coin_root) and reset_coin_root.visible, "restart makes collected coin visible again")

    var obstacles = game.get("obstacle_nodes")
    var target_boost: Dictionary = {}
    for obstacle in obstacles:
        if obstacle["kind"] == "boost":
            target_boost = obstacle
            break
    _expect(not target_boost.is_empty(), "a test boost pad is available")
    if not target_boost.is_empty():
        var boost_distance := float(target_boost["original_distance"])
        var boost_lane := float(target_boost["lane"])
        game.set("travel_distance", boost_distance)
        game.set("lateral_offset", boost_lane)
        game.call("_check_pickups_and_collisions", boost_distance - 1.0, boost_lane)
        _expect(float(target_boost["distance"]) < 0.0, "boost pad is consumed on pickup")
        var boost_root := target_boost["root"] as Node3D
        _expect(is_instance_valid(boost_root) and not boost_root.visible, "used boost pad hides")
        game.call("_restart_race", false)
        _expect(is_equal_approx(float(target_boost["distance"]), boost_distance), "restart restores boost distance")
        _expect(is_instance_valid(boost_root) and boost_root.visible, "restart restores boost pad visibility")

    var target_obstacle: Dictionary = {}
    for obstacle in obstacles:
        if obstacle["kind"] != "boost":
            target_obstacle = obstacle
            break
    _expect(not target_obstacle.is_empty(), "a test obstacle is available")
    if not target_obstacle.is_empty():
        var obstacle_distance := float(target_obstacle["distance"])
        var obstacle_lane := float(target_obstacle["lane"])
        game.set("travel_distance", obstacle_distance)
        game.set("lateral_offset", obstacle_lane)
        game.call("_check_pickups_and_collisions", obstacle_distance - 1.0, obstacle_lane)
        var crash_label := game.get("message_label") as Label
        _expect(bool(game.get("race_over")), "obstacle impact ends race")
        _expect(crash_label != null and crash_label.text.begins_with("CRASH"), "crash state is not overwritten")

    # Verify a clean restart and finish path.
    game.call("_restart_race", false)
    _expect(not bool(game.get("race_over")), "restart clears terminal state")
    game.set("start_countdown", 0.0)
    game.set("travel_distance", float(game.get("route_length")) - 1.0)
    game.set("current_speed", 47.0)
    game.call("_process", 0.05)
    var finish_label := game.get("message_label") as Label
    _expect(bool(game.get("race_over")), "crossing the finish ends the race")
    _expect(finish_label != null and (finish_label.text.begins_with("FINISH") or finish_label.text.begins_with("NEW PERSONAL BEST")),
        "finish state is displayed")

    print("AUDIT_TEST_RESULT: %d failure(s)" % failures.size())
    quit(1 if not failures.is_empty() else 0)
