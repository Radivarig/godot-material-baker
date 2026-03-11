# Godot Material Baker

<p align="center"><img src="https://raw.githubusercontent.com/Radivarig/godot-material-baker/refs/heads/main/images/material_baker_icon.png" width="128"/></p>

A Godot 4.4+ tool for automatic baking of shader materials into images and packing them into `Texture2DArray` resources **live in the editor** (re-baking on every resource change), **and optionally at runtime** (generating arrays on scene play in build).

## How It Works

Baker nodes render shader parameters through a sub-viewport, store the resulting images, and notify the manager script.  

Multiple categories (e.g. *Albedo & Height*, *Normal & Roughness*) can be defined in the manager, each using its own channel packing visual shader.  

Baking is automatic — any change to shader parameters, including texture resources, triggers a re-bake only for the affected categories.  

Generated arrays are synced to a shader, and pre/post-save hooks prevent in-memory resources (not saved to a `.res` file) from being serialized into the scene.

## How to Use

1. Copy `material-baker` into your `res://addons/`, enable under `Project > Project Settings > Plugins`.
2. Add a **MaterialBakerArrays** node to the scene, load configs from `addons/material_baker/categories`, otherwise give them a unique `baker_category_uid`.
3. Use the **Create Material Baker** button to add and auto-configure category configs and image settings, or duplicate existing baker nodes.
4. Save arrays to `.res` files and assign them as references to your shaders or use `RuntimeShaderArrays` to auto generate and sync arrays to the shader at runtime.
5. Upon editing, the arrays are decompressed for performance, press **Compress** when done editing to reduce the `.res` file size.

Each `MaterialBaker` shows the shader parameters for every category directly in the Inspector.

> NOTE: In the screenshot, albedo and height are packed to the same texture, so the channel is set to 3 which is Alpha (0123 => RGBA).

|Material Baker|Material Baker Arrays|
|---|---|
| ![Material Baker](https://raw.githubusercontent.com/Radivarig/godot-material-baker/refs/heads/main/images/docs/material_baker.png) | ![Material Baker Arrays](https://raw.githubusercontent.com/Radivarig/godot-material-baker/refs/heads/main/images/docs/material_baker_arrays.png) |

## Bake Shaders

You can override each baker and each category with your own shader, see `Bake Shaders` section of the `MaterialBaker` node inspector.
> NOTE: When using your own shaders note that the blend mode must be set to `premul_alpha` so that alpha does not dim the color output.

Examples included under `addons/material_baker/shaders/`:
- `albedo_height_packer.tres` — packs albedo (RGB) + height (A)
- `normal_roughness_packer.tres` — packs normal (RGB) + roughness (A)
- `albedo_height_process_advanced.tres` — showcases more complex tinting and contrast

Duplicate one of these and adapt to fit your texture inputs or to add custom image processing logic.

| Basic `albedo_height_packer.tres` | Advanced `albedo_height_process_advanced.tres` |
|---|---|
| ![Channel Packer Visual Shader](https://raw.githubusercontent.com/Radivarig/godot-material-baker/refs/heads/main/images/docs/channel_packer_visual_shader.png) | ![Saturation Tint Advanced](https://raw.githubusercontent.com/Radivarig/godot-material-baker/refs/heads/main/images/docs/saturated_tint_advanced.png) |

### Compression

Compression is ignored during editing for performance and arrays are decompressed when bakers re-render on inspector changes.  
Clicking the **Compress** button on the `MaterialBakerArrays` will apply the configured formats to the arrays.
Compression will persist if you save the arrays to a `.res` file, otherwise compression in build is not yet supported in Godot.

## Settings

| Material Baker Image Settings | Material Baker Category Configs |
|---|---|
| ![Image Settings](https://raw.githubusercontent.com/Radivarig/godot-material-baker/refs/heads/main/images/docs/material_baker_image_settings.png) | ![Baker Category Config](https://raw.githubusercontent.com/Radivarig/godot-material-baker/refs/heads/main/images/docs/material_baker_category_configs.png) |

## Warnings

![Warnings](https://raw.githubusercontent.com/Radivarig/godot-material-baker/refs/heads/main/images/docs/warnings.png)

## Examples

### Texture2DArrays Preview

Mesh preview to inspect individual layers of the generated `Texture2DArray`s.  
> NOTE: In the demo scene the preview script has a signal connected to `arrays_node.arrays_applied` that recreates the mesh when the arrays layer count changes.

### Terrain3D (WIP)

`Terrain3DMaterialBaker` extends `MaterialBakerManager` and writes baked images into the `Terrain3D` texture list.

> NOTE: You have to comment this out or focus loss breaks usage `asset_dock.gd:668 # plugin.select_terrain()`

## Classes

| Core | |
|---|---|
| `MaterialBakerArrays`<br>extends&nbsp;MaterialBakerManager | Collects baked images from all bakers into one `Texture2DArray` per category. <br>Has a `↓ Compress` button to apply the configured compression format when ready. |
| `RuntimeShaderArrays`<br>extends&nbsp;Node | Bridges a `MaterialBakerArrays` node to a `ShaderMaterial` at runtime. <br>Maps each `baker_category_uid` to a configurable shader parameter name. <br>Tracks when arrays are ready and updates the material parameters automatically. <br>On editor save, temporarily swaps live arrays for their saved `.res` counterparts to avoid serializing them into the scene file.|
| `MaterialBakerManager`<br>extends&nbsp;Node | Owns `category_configs` and `image_settings`, propagates them to `MaterialBaker` nodes. <br> Has a `+ Create Material Baker` button that adds a new baker with all the configs preconfigured. <br>Override: `baker_rendered`, `bakers_structure_changed`, and `regenerate`. |
| `MaterialBaker`<br>extends&nbsp;ResourceWatcher | Exposes all shader parameters for each category directly in the Inspector. <br>Re-bakes automatically when resources change, and emits `baker_rendered`. <br> Uses `texture_hot_reload` to swap external texture changes while Godot is not focused.|
| `MaterialBakerCategory`<br>extends&nbsp;Node | Internal renderer per category. Owns a `SubViewport + ColorRect`. <br> Uses the category's shader, triggers a single-frame render, and returns the `Image` result. |

| Configs | |
|---|---|
| `MaterialBakerCategoryConfig`<br>extends&nbsp;Resource | Shared definition for one baker category, e.g. `Albedo & Height`, `Normal & Roughness`.<br> A unique `baker_category_uid`, a `baker_category_label` name and a `default_shader`. <br>All bakers under the same manager reference the same config instances. |
| `MaterialBakerCategoryState`<br>extends&nbsp;Resource | Per-baker, per-category mutable state. See `Bake Shaders` to override with your own. <br>The active `Shader`, its auto-managed `ShaderMaterial`, and a cache of the last baked `Image`. |
| `MaterialBakerImageSettings`<br>extends&nbsp;Resource | Output `size`, `is_size_square`, `use_mipmaps` toggle, and `compress_mode` format. <br>Can be shared across all categories or set individually per category. |

| Utilities | |
|---|---|
| `ResourceWatcher`<br>extends&nbsp;Node | Recursively connects to `changed` signal on all `Resource` properties (and their sub-resources). <br>Batches notifications and calls `on_resource_changed` once per deferred frame. |
| `TextureHotReloader`<br>extends&nbsp;Node | Watches `Texture2D` parameters of registered `ShaderMaterial`s for external file changes. <br>Reloads textures via the reimport signal and also polls file modification times as a fallback. |
| `ShaderToPNG`<br>extends&nbsp;MaterialBakerCategory | Bakes the shader material into a .png file, e.g., for channel packing after which you can discard originals. <br>Optionally specify an existing .png whose import settings will be used for the generated one.|

### Generating Arrays at Runtime

- Arrays that are not saved to `.res` files are auto generated upon entering the scene play.
- This allows a game to ship with raw base textures and generate the rest asynchronously on the fly.
- Use `RuntimeShaderArrays` to auto sync arrays to shader parameters and have it prevent Godot from serializing references to scene.
- Uncheck `generate_at_runtime` to disable and to also show warnings when `.res` file array references are missing.

## TODO

- Add `RuntimeShaderTextures`, like arrays with a single layer, a PBR example that syncs to a shader and can save categories to `.res`.
- Add more image processing examples, like auto generating a normalmap from a heightmap, or roughness from albedo
- Add example for caching runtime-generated arrays to .res files in build, e.g. ship without, generate once then reuse.

### Future Research

- Compression in build?

## Contribution

If you find an issue or have a use case that could be covered by this project, please open a new ticket or a PR.
