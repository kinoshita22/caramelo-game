extends "res://tests/lib/test_case.gd"
## Alpha-threshold bounds used for frame geometry.

const AssetIO := preload("res://scripts/tools/asset_io.gd")


func _image() -> Image:
	var img := Image.create_empty(20, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(5, 2, 6, 5), Color(1, 1, 1, 1))  # solid body: x 5-10, y 2-6
	img.set_pixel(0, 9, Color(1, 1, 1, 3.0 / 255.0))  # invisible noise
	img.set_pixel(15, 7, Color(1, 1, 1, 20.0 / 255.0))  # faint haze
	return img


func test_threshold_ignores_faint_pixels() -> void:
	check_eq(AssetIO.visible_bounds(_image(), 32), Rect2i(5, 2, 6, 5), "alpha >= 32")


func test_low_threshold_includes_haze_but_not_noise() -> void:
	check_eq(AssetIO.visible_bounds(_image(), 8), Rect2i(5, 2, 11, 6), "alpha >= 8")


func test_threshold_one_matches_used_rect() -> void:
	check_eq(AssetIO.visible_bounds(_image(), 1), Rect2i(0, 2, 16, 8), "alpha >= 1")


func test_fully_transparent_image_is_empty() -> void:
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	check_eq(AssetIO.visible_bounds(img, 32), Rect2i(), "empty image")


func test_strip_sequence() -> void:
	check_eq(AssetIO.strip_sequence("01_floating_island_base.png"), "floating_island_base", "numbered")
	check_eq(AssetIO.strip_sequence("manifest.csv"), "manifest", "unnumbered")
