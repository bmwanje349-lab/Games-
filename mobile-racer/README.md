# Turbo Trails: 3D Driving Simulator

A mobile-focused Godot 4.7.2 3D driving project for Android, with nine imported sports cars and three distinct courses. The driving model uses throttle, brakes, speed-sensitive steering, rolling drag, road-edge slowdown, moving traffic, and collision handling rather than fixed lateral lane movement.

## Visuals and environment

- Tiled PBR asphalt with diffuse, normal, and roughness maps.
- PBR gravel shoulders, contoured 3D landscape, and a coastal water mesh.
- Instanced broadleaf trees and tiered conifers with varied sizes/colours, plus city buildings and street lighting.
- Lower road-following chase camera, speed/gear/RPM/trip HUD, and a restartable drive.
- The Android project uses Godot's OpenGL Compatibility renderer for broader mobile-driver compatibility.

PBR surfaces are downloaded by `tools/download_environment_textures.py` from Poly Haven's CC0 texture collection during the Android build. The script validates each downloaded JPEG before the project imports it. These assets improve surface detail while limiting texture memory for mobile hardware.

## Cars and attribution

The nine vehicle models and original creator credits are documented in `assets-lock.json` and `ASSET_CREDITS.md`. The checked source collection identifies these models as CC BY 4.0. Manufacturer marks remain the property of their respective owners.

## Build and test

The GitHub Actions Android workflow downloads and validates the CC0 PBR texture maps, imports the car and environment assets in Godot 4.7.2, runs a headless audit for routes/controls/vehicle dynamics/car grounding/traffic/PBR resources, exports an ARM64 debug APK, then checks that the models, textures, and compiled game script are packaged.

Open this directory in Godot 4.7.2 or newer, allow imported assets to finish processing, and run `scenes/main.tscn`.

## Controls

- Hold left/right to steer.
- Hold **THROTTLE** to accelerate; hold **BRAKE** to slow down.
- **NEXT CAR** / **CAR** changes the selected sports car.
- **NEXT COURSE** / **COURSE** changes the environment.
- **RESTART** resets the drive.
- Keyboard: A/D or arrows steer, W/up accelerates, S/down brakes, C changes car, R restarts.

## Mobile performance

Generated meshes and MultiMesh instancing avoid a separate scene node for every tree or road segment. Nearby traffic uses a small selection of the car models, while distant traffic is hidden. Texture maps are 1K to balance material detail with mobile memory requirements.

This is a realistic-leaning mobile 3D driving foundation, not a claim of photorealism or finished commercial racing-game polish. Visual quality and frame rate still need testing on physical target phones.
