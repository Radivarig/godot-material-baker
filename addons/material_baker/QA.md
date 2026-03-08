# QA

## Arrays
- changes made to a baker category parameters
	- should update only that baker and only that category

- changes made to any of the image_settings or share_image_settings
	- should rebake everything
	- should make each category use the right settings based on share bool

- duplicating baker node
	- should keep shader params state independent of each other

- compressing .res arrays
	- should only compress what's not compressed
    - should reuse compression cache

	- and reopening the scene
    	- should not rebake and should not show yellow warning about it

- no .res arrays assigned and reopen scene
    - should render and only render those arrays that are not saved to .res

- adding or removing bakers
    - should recreate the arrays

- deleting arrays or undoing
    - should not throw errors

- building with .res arrays
    - should render instantly

- building without .res and generated
    - should have a small build size
    - should render, small delay ~0.5s expected

### Baker Categories
- deleting and undoing categories
    - should preserve all baker shader states
        - losing state on scene reopen is expected

### Texture Hot Reloader
- when updating a texture file externally
    - it should detect a file has changed while Godot is in the background

    - it should how swap shader image values with the fresh version
        - it should not have a popup while updates take place

    - it should update all resources pointing to the same file the same

- when refocusing Godot
    - it should restore the references to the file path
        - saving the scene should not save reasources locally

## ShaderToPNG
- should render to file and reimport on save button
- should inherit import settings if `use_import_settings_from` is set

## Terrain3D
- on baker change
    - should update only the changed texture index
    - should update only the changed category
