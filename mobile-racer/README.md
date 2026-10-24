# Turbo Trails: Mobile Racer

A Godot 4 mobile arcade-racing prototype targeting Android phones, including modest hardware. First milestone: controllable 3D road course, chase camera, touch controls, score, traffic and coin pickups, and nine selectable cars.

## Cars and attribution

The nine models are defined in assets-lock.json. Source GLBs and original licence notices are imported by the GitHub Actions asset-import workflow. Source metadata identifies the checked models as Creative Commons Attribution 4.0 (CC BY 4.0). Required attribution is preserved in ASSET_CREDITS.md and assets/cars/licenses. See the upstream collection: https://github.com/supercar3d/supercar_3D_asssets.

Vehicle manufacturer trademarks and logos remain the property of their respective owners. The garage names in this game are internal fictional names.

## Run locally

Open this directory in Godot 4.4 or newer, let the editor import the GLB assets, and run scenes/main.tscn. Before the asset-import workflow finishes, the scene uses a fallback sports-car model.

## Controls

- Touch: hold left/right to steer; use Brake and Boost; Change Car cycles through the nine models.
- Keyboard: A/D or arrow keys to steer, S/down to brake, Space to boost, C to change car, R to restart.
- Forward driving is arcade-style. This is the first playable foundation, not a claim of finished Asphalt Nitro-level quality.

## Mobile performance

Only the selected player car is instantiated at one time. Road markings and roadside vegetation use MultiMesh instancing. The project uses Godot's mobile renderer. Car GLBs remain separate so they can be inspected and individually optimized or given LODs after visual and triangle-count validation.
