extends SceneTree
## Placeholder app icon until the client delivers one (plan §13): a square
## crop of Caramelo's face from the Form 1 idle frame, found from the frame's
## own attachment points. A crop of existing art, not new art.
##
## Writes assets/app_icon/app_icon.png (window and taskbar icon) and
## build/windows/app_icon.ico (installer and shortcuts; PNG-in-ICO, Vista+).
##
## Usage: godot --headless --path caramelo-game --script res://tools/make_app_icon.gd

const ContentData := preload("res://scripts/systems/content_data.gd")
const FRAME := "character.f01.s03"
const SIZES := [256, 64, 48, 32, 16]
const PNG_OUT := "res://assets/app_icon/app_icon.png"
const ICO_OUT := "res://build/windows/app_icon.ico"


func _init() -> void:
	var content := ContentData.new()
	content.load_from("res://data")
	var asset: Dictionary = content.asset(FRAME)
	var points: Dictionary = content.attachment_points(1, 3)
	var image := Image.load_from_file(ProjectSettings.globalize_path(asset["runtime_path"]))
	if image == null or not points.has("head_top") or not points.has("neck"):
		printerr("cannot read the frame or its attachment points")
		quit(1)
		return
	var head: Array = points["head_top"]
	var neck: Array = points["neck"]
	# Centre on the head's full width at eye level (ear to ear), not on the
	# eyes, which sit off-centre when the head is turned.
	var eyes_y := int(points["eyes"][1])
	var left := int(points["eyes"][0])
	var right := left
	while left > 0 and image.get_pixel(left - 1, eyes_y).a > 0.12:
		left -= 1
	while right < image.get_width() - 1 and image.get_pixel(right + 1, eyes_y).a > 0.12:
		right += 1
	var side := int(maxf((neck[1] - head[1]) * 1.25, (right - left) * 1.12))
	var centre := Vector2i((left + right) / 2, int(head[1] + side * 0.47))
	var crop := Rect2i(centre - Vector2i(side / 2, side / 2), Vector2i(side, side)).intersection(
			Rect2i(Vector2i.ZERO, image.get_size()))
	var face := image.get_region(crop)
	face.convert(Image.FORMAT_RGBA8)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PNG_OUT).get_base_dir())
	var big := face.duplicate() as Image
	big.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	big.save_png(ProjectSettings.globalize_path(PNG_OUT))

	var entries: Array[PackedByteArray] = []
	for s in SIZES:
		var img := face.duplicate() as Image
		img.resize(s, s, Image.INTERPOLATE_LANCZOS)
		entries.append(img.save_png_to_buffer())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ICO_OUT).get_base_dir())
	var f := FileAccess.open(ProjectSettings.globalize_path(ICO_OUT), FileAccess.WRITE)
	f.store_buffer(ico_bytes(SIZES, entries))
	f.close()
	print("wrote ", PNG_OUT, " and ", ICO_OUT)
	quit(0)


## ICO container holding PNG images: 6-byte header, 16 bytes per entry, data.
static func ico_bytes(sizes: Array, pngs: Array[PackedByteArray]) -> PackedByteArray:
	var out := PackedByteArray()
	var header := StreamPeerBuffer.new()
	header.put_u16(0)
	header.put_u16(1)
	header.put_u16(sizes.size())
	var offset := 6 + 16 * sizes.size()
	for i in sizes.size():
		var s: int = sizes[i]
		header.put_u8(0 if s >= 256 else s)
		header.put_u8(0 if s >= 256 else s)
		header.put_u8(0)
		header.put_u8(0)
		header.put_u16(1)
		header.put_u16(32)
		header.put_u32(pngs[i].size())
		header.put_u32(offset)
		offset += pngs[i].size()
	out.append_array(header.data_array)
	for png in pngs:
		out.append_array(png)
	return out
