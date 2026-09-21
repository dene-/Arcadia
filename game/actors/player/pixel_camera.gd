extends Camera2D

## Align the interpolated view to display pixels, not the coarser artwork grid.
## Integer canvas scaling and nearest filtering keep the original texels sharp.
func _ready() -> void:
	RenderingServer.frame_pre_draw.connect(_align_to_display_pixels)

func _align_to_display_pixels() -> void:
	if not is_current():
		return
	var viewport: Viewport = get_viewport()
	var stretch: Transform2D = viewport.get_stretch_transform()
	var view: Transform2D = viewport.canvas_transform
	view.origin = stretch.affine_inverse() * (stretch * view.origin).round()
	viewport.canvas_transform = view
