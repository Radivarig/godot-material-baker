# Godot Material Baker
<p align="center"><img src="https://raw.githubusercontent.com/Radivarig/godot-material-baker/refs/heads/main/images/material_baker_icon.png" width="64"/></p>

A Godot 4.4+ tool for automatic baking of shader materials into images and packing them into `Texture2DArray` resources **live in the editor** (re-baking on every resource change) **and optionally at runtime** (generating arrays on scene play in build).


## How It Works

Baker nodes render shader parameters through a sub-viewport, store the resulting images, and notify the manager script.  

Multiple categories (e.g. *Albedo & Height*, *Normal & Roughness*) can be defined in the manager, each using its own channel packing visual shader.  

Baking is automatic — any change to shader parameters, including texture resources, triggers a re-bake only for the affected category.  

Generated arrays are synced to a shader, and pre/post save hooks prevent in-memory resources (not saved to a .res file) from being serialized into the scene.

## How to Use
1. Copy `material-baker` into your `res://addons/`, enable under `Project > Project Settings > Plugins`.
2. Add a **MaterialBakerArrays** node to the scene and quick load the categories, otherwise give them a unique `baker_category_uid`.
3. Use the **Create Material Baker** button to add and auto-configure category configs and image settings, or duplicate existing baker nodes.
4. Save arrays to `.res` files and assign them as references to your shaders or use `RuntimeShaderArrays` to auto generate and sync arrays to the shader at runtime.
5. Upon editing arrays are decompressed for performance, for `.res` file arrays press **Compress** when done editing to reduce the file size.

Each `MaterialBaker` shows the shader parameters for every category directly in the Inspector.

> In the screenshot albedo and height are packed to the same texture so the channel is set to 3 which is Alpha (0123 => RGBA).

|Material Baker|Material Baker Arrays|
|---|---|
| ![Material Baker](https://raw.githubusercontent.com/Radivarig/godot-material-baker/refs/heads/main/images/docs/material_baker.png) | ![Material Baker Arrays](https://raw.githubusercontent.com/Radivarig/godot-material-baker/refs/heads/main/images/docs/material_baker_arrays.png) |

## Bake Shaders
> When using your own shaders note that the blend mode must be set to `premul_alpha` in order for alpha to not dim the color output.

Duplicate one of the examples and adapt it to fit your texture inputs or add custom image processing logic.

Examples included:
- `albedo_height_packer.tres` — packs albedo (RGB) + height (A)
- `normal_roughness_packer.tres` — packs normal (RGB) + roughness (A)
- `albedo_height_process_advanced.tres` — showcases more complex tinting and contrast

| Basic | Advanced |
|---|---|
| ![Channel Packer Visual Shader](https://raw.githubusercontent.com/Radivarig/godot-material-baker/refs/heads/main/images/docs/channel_packer_visual_shader.png) | ![Saturation Tint Advanced](https://raw.githubusercontent.com/Radivarig/godot-material-baker/refs/heads/main/images/docs/saturated_tint_advanced.png) |

### Compression

Compression is ignored during editing for performance and arrays are decompressed.  
Clicking the **Compress** button on the `MaterialBakerArrays` will apply the configured formats to the arrays.
Compression will persist if you saved the arrays to a `.res` file.

## Settings

| Material Baker Image Settings | Material Baker Category Configs |
|---|---|
| ![Image Settings](https://raw.githubusercontent.com/Radivarig/godot-material-baker/refs/heads/main/images/docs/material_baker_image_settings.png) | ![Baker Category Config](https://raw.githubusercontent.com/Radivarig/godot-material-baker/refs/heads/main/images/docs/material_baker_category_configs.png) |

## Warnings

![Warnings](https://raw.githubusercontent.com/Radivarig/godot-material-baker/refs/heads/main/images/docs/warnings.png)

## Examples

### Texture2DArray Preview

Mesh preview to inspect individual layers of the generated `Texture2DArray`s.  

### Terrain3D (WIP)

`Terrain3DMaterialBaker` extends `MaterialBakerManager` and writes baked images into the `Terrain3D` texture list.

> Note that you have to comment this out or focus loss breaks usage `asset_dock.gd:668 # plugin.select_terrain()`

## Classes

| Class | Extends | Role |
|---|---|---|
| `MaterialBakerArrays` | `MaterialBakerManager` | Collects baked images from all bakers into one `Texture2DArray` per category. <br>Has a `↓ Compress` button to apply the configured compression format when ready. |
| `RuntimeShaderArrays` | `Node` | Bridges a `MaterialBakerArrays` node to a `ShaderMaterial` at runtime. <br>Maps each `baker_category_uid` to a configurable shader parameter name. <br>Tracks when arrays are ready and updates the material parameters automatically. <br>On editor save, temporarily swaps live arrays for their saved `.res` counterparts to avoid serializing them into the scene file.|
| `MaterialBakerManager` | `Node` | Owns `category_configs` and `image_settings`, propagates them to `MaterialBaker` nodes. <br> Has a `+ Create Material Baker` button that adds a new baker with all the configs preconfigured. <br>Override: `baker_rendered`, `bakers_structure_changed`, and `regenerate`. |
| `MaterialBaker` | `ResourceWatcher` | Exposes all shader parameters for each category directly in the Inspector. <br>Re-bakes automatically when resources change, and emits `baker_rendered`. <br> Uses `texture_hot_reload` to swap external texture changes while Godot is not focused.|
| `MaterialBakerCategory` | `Node` | Internal renderer per category. Owns a `SubViewport + ColorRect`. <br> Uses the category's shader, triggers a single-frame render, and returns the `Image` result. |
| Configs | | |
| `MaterialBakerCategoryConfig` | `Resource` | Shared definition for one baker category. <br> A unique `config_id`, a `bake_category` name, a `default_shader`, and a `MaterialBakerImageSettings`. <br>All bakers under the same manager reference the same config instances. |
| `MaterialBakerCategoryState` | `Resource` | Per-baker, per-category mutable state. <br>The active `Shader`, its auto-managed `ShaderMaterial`, and a cache of the last baked `Image`. |
| `MaterialBakerImageSettings` | `Resource` | Output `size`, `is_size_square`, `use_mipmaps` toggle, and `compress_mode` format. <br>Can be shared across all categories or set individually per category. |
| Utilities | | |
| `ResourceWatcher` | `Node` | Recursively connects to `changed` signal on all `Resource` properties (and their sub-resources). <br>Batches notifications and calls `on_resource_changed` once per deferred frame. |
| `TextureHotReloader` | `Node` | Watches `Texture2D` parameters of registered `ShaderMaterial`s for external file changes. <br>Reloads textures via the reimport signal and also polls file modification times as a fallback. |
| `ShaderToPNG` | `MaterialBakerCategory` | Bakes the shader material into a .png file, e.g., for channel packing after which you can discard originals. <br>Optionally specify an existing .png whose import settings will be used for the generated one.|

### Generating Arrays at Runtime

- Arrays that are not saved to `.res` files are auto generated upon entering the scene play.
- This allows a game to ship with raw base textures and generate the rest asynchronously on the fly.
- Use `RuntimeShaderArrays` to auto sync arrays to shader parameters and have it prevent Godot from serializing references to scene.

## Future Research

- Compression in build?

## Contribution
If you find an issue or have a use case that could be covered by this project, please open a new ticket or a PR.
