# Turbo Trails: Mobile Racer

A Godot 4.7 3D arcade racing game built for landscape Android phones, with a focus on road presentation, multiple distinct routes, detailed car models, and mobile-friendly rendering.

## Play and development

- **Game project:** [mobile-racer/](mobile-racer/)
- **Main racing scene:** [scenes/main.tscn](mobile-racer/scenes/main.tscn)
- **Route and driving code:** [scripts/main.gd](mobile-racer/scripts/main.gd)
- **Nine-car roster and pinned sources:** [assets-lock.json](mobile-racer/assets-lock.json)
- **Third-party model credits:** [ASSET_CREDITS.md](mobile-racer/ASSET_CREDITS.md)

## Routes

1. **Coastal Sprint** — ocean-side road, rock formations and wide sweepers.
2. **Alpine Pass** — mountain bends, terrain elevation changes and snow/rock scenery.
3. **Neon City GP** — night circuit with emissive windows, streetlights and neon gates.

Each route has its own road shape, environment palette and scenery. The race includes a 3-second start, distance progression, six checkpoints, traffic and barrier hazards, coin pickups, nitro pickups/boost, collision/finish states, a score, and saved personal-best times per route.

## Mobile controls

- Hold **◀ / ▶** to steer.
- Hold **NITRO** to boost while nitro charge remains; charge regenerates while not boosting.
- Hold **BRAKE** to slow down.
- Use **NEXT COURSE** to switch the route, **NEXT CAR** or **GARAGE** to change cars, and **RESTART** to race again.
- Keyboard: **A/D** or arrows to steer, **Space** for nitro, **S/Down** to brake, **Q/E** to change route, **C** to change car, and **R** to restart.

## Cars and licensing

The nine GLB models are pinned by upstream source hash, include original licence notices, and are listed in the generated asset manifest. The checked models are attributed under Creative Commons Attribution 4.0 (CC BY 4.0); keep the original credits when redistributing the game. See [ASSET_CREDITS.md](mobile-racer/ASSET_CREDITS.md).

The automated asset workflow decodes Draco geometry, simplifies the geometry conservatively and resizes textures to a maximum 1024-pixel edge. The current source pack totals about 61 MB before Godot's platform import/export processing. The game loads only the selected player vehicle at runtime; repeated roadside details, trees, kerbs and city facades use MultiMesh instancing.

## Build

Open the **mobile-racer/** directory in Godot 4.7.2 or newer and run the main scene. GitHub Actions builds an ARM64 Android debug APK and publishes it as a workflow artifact when the build succeeds:

- [Android APK build history](https://github.com/bmwanje349-lab/Games-/actions/workflows/build-android.yml)
- [Car asset import/optimization history](https://github.com/bmwanje349-lab/Games-/actions/workflows/import-car-assets.yml)

This is an evolving arcade-racer build. A successful CI export verifies that the project packages; performance and graphics should still be tested on the target Android device before claiming retail-game polish.
