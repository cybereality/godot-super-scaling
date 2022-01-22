# [Godot Super Scaling]
# created by Andres Hernandez
extends Node

export (float, 0.1, 2.0) var scale_factor = 1.0 setget change_scale_factor
export (float, 0.0, 1.0) var smoothness = 0.5 setget change_smoothness
export (bool) var enable_on_play = false
export (Array, NodePath) var ui_nodes
export (int, "3D", "2D") var usage = 0
export (int, "Disabled", "2X", "4X", "8X", "16X") var msaa = 0 setget change_msaa
export (bool) var fxaa = false setget change_fxaa
export (int, 1, 4096) var shadow_atlas = 4096 setget change_shadow_atlas
onready var sampler_shader = load(get_script().resource_path.get_base_dir() + "/SuperScaling.tres")
var sampler_material
var game_nodes
var overlay
var viewport
var viewport_size
var root_viewport
var native_resolution
var original_resolution
var native_aspect_ratio
var original_aspect_ratio
enum {USAGE_3D, USAGE_2D}
const epsilon = 0.01
var finish_timer 

func _ready():
	if (enable_on_play):
		finish_setup()
	
func finish_setup():
	remove_all_nodes()
	get_screen_size()
	create_viewport()
	set_shader_texture()
	add_all_nodes()
	get_parent().call_deferred("add_child", viewport)
	original_resolution = native_resolution
	original_aspect_ratio = native_aspect_ratio
	root_viewport = get_viewport()
	#warning-ignore:RETURN_VALUE_DISCARDED
	viewport.connect("size_changed", self, "on_window_resize")
	#warning-ignore:RETURN_VALUE_DISCARDED
	root_viewport.connect("size_changed", self, "on_window_resize")
	on_window_resize()
	create_sampler()
	change_msaa(msaa)
	change_fxaa(fxaa)
	change_smoothness(smoothness)
	set_process_input(false)
	set_process_unhandled_input(false)
			
func remove_all_nodes():
	game_nodes = get_parent().get_children()
	var ui_count = ui_nodes.size()
	var done = false
	while not done:
		for i in range(game_nodes.size()):
			if ui_nodes.has(get_path_to(game_nodes[i])):
				game_nodes.remove(i)
				break
		ui_count -= 1
		if ui_count <= 0:
			done = true
	game_nodes.erase(self)
	for node in game_nodes:
		if node != self:
			get_parent().call_deferred("remove_child", node)
	
func add_all_nodes():
	for node in game_nodes:
		viewport.call_deferred("add_child", node)
	
func create_viewport():
	viewport = Viewport.new()
	viewport.name = "Viewport"
	viewport.size = native_resolution
	viewport.usage = Viewport.USAGE_3D if usage == USAGE_3D else Viewport.USAGE_2D
	viewport.render_target_clear_mode = Viewport.CLEAR_MODE_NEVER
	viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
	viewport.render_target_v_flip = true
	viewport.size_override_stretch = true
	viewport.msaa = Viewport.MSAA_DISABLED
	viewport.shadow_atlas_size = shadow_atlas
	
func create_sampler():
	overlay = ColorRect.new()
	overlay.name = "SamplerOverlay"
	sampler_material = ShaderMaterial.new()
	sampler_material.shader = sampler_shader
	overlay.material = sampler_material
	overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(overlay)

func set_shader_texture():
	yield(VisualServer, "frame_post_draw")
	var view_texture = viewport.get_texture()
	view_texture.flags = 0
	view_texture.viewport_path = viewport.get_path()
	sampler_material.set_shader_param("viewport", view_texture)
	change_scale_factor(scale_factor)
	set_process_input(true)
	set_process_unhandled_input(true)
	
func set_shader_resolution():
	if sampler_material:
		sampler_material.set_shader_param("view_resolution", viewport_size)
	
func get_screen_size():
	var window = OS.window_size
	native_resolution = window
	native_aspect_ratio = native_resolution.x / native_resolution.y

func set_viewport_size():
	var res_float = native_resolution * scale_factor
	viewport_size = Vector2(round(res_float.x), round(res_float.y))
	var aspect_setting = get_aspect_setting()
	if native_aspect_ratio and original_aspect_ratio and (aspect_setting != "ignore" and aspect_setting != "expand"):
		var aspect_diff = native_aspect_ratio / original_aspect_ratio
		if usage == USAGE_2D:
			if aspect_diff > 1.0 + epsilon and aspect_setting == "keep_width":
				viewport_size = Vector2(round(res_float.y * native_aspect_ratio), round(res_float.y))
			elif aspect_diff < 1.0 - epsilon and aspect_setting == "keep_height":
				viewport_size = Vector2(round(res_float.x), round(res_float.y / native_aspect_ratio))	
		elif usage == USAGE_3D:
			if aspect_diff > 1.0 + epsilon:
				viewport_size = Vector2(round(res_float.x / aspect_diff), round(res_float.y))
			elif aspect_diff < 1.0 - epsilon:
				viewport_size = Vector2(round(res_float.x), round(res_float.y * aspect_diff))
	
func resize_viewport():
	if viewport:
		viewport.size = viewport_size
			
func scale_viewport_canvas():
	if viewport:
		var aspect_setting = get_aspect_setting()
		var aspect_diff = native_aspect_ratio / original_aspect_ratio
		if aspect_setting == "ignore":
			viewport.set_size_override(true, original_resolution)
		elif aspect_setting == "expand":
			viewport.set_size_override(true, native_resolution)
		else:
			if usage == USAGE_2D:
				if aspect_diff < 1.0 - epsilon and aspect_setting == "keep_width":
					viewport.set_size_override(true, Vector2(round(original_resolution.x), round(original_resolution.x / native_aspect_ratio)))
				elif aspect_diff > 1.0 + epsilon and aspect_setting == "keep_height":
					viewport.set_size_override(true, Vector2(round(original_resolution.y * native_aspect_ratio), round(original_resolution.y)))
				else:
					viewport.set_size_override(true, original_resolution)
			elif usage == USAGE_3D:
				if aspect_diff > 1.0 + epsilon:
					viewport.set_size_override(true, Vector2(round(original_resolution.x * aspect_diff), round(original_resolution.y)))
				elif aspect_diff < 1.0 - epsilon:
					viewport.set_size_override(true, Vector2(round(original_resolution.x), round(original_resolution.y / aspect_diff)))
			
func set_sampler_size():
	if overlay:
		var stretch_setting = get_stretch_setting()
		var aspect_setting = get_aspect_setting()
		var aspect_diff = native_aspect_ratio / original_aspect_ratio
		if usage == USAGE_2D:
			if aspect_diff < 1.0 - epsilon and aspect_setting == "keep_width":
				overlay.rect_size = Vector2(round(original_resolution.x), round(original_resolution.x / native_aspect_ratio))
			elif aspect_diff > 1.0 + epsilon and aspect_setting == "keep_height":
				overlay.rect_size = Vector2(round(original_resolution.y * native_aspect_ratio), round(original_resolution.y))
			else:
				overlay.rect_size = Vector2(round(original_resolution.x), round(original_resolution.y))
		elif usage == USAGE_3D:
			overlay.rect_size = Vector2(round(native_resolution.x), round(native_resolution.y))
			if aspect_diff > 1.0 + epsilon:
				overlay.rect_size.x = round(native_resolution.y * original_aspect_ratio)
			elif aspect_diff < 1.0 - epsilon:
				overlay.rect_size.y = round(native_resolution.x / original_aspect_ratio)
		var overlay_size = overlay.rect_size
		var screen_size = Vector2(0.0, 0.0)
		if usage == USAGE_2D:
			screen_size = original_resolution
		elif usage == USAGE_3D:
			screen_size = native_resolution
		if stretch_setting == "disabled" or usage == USAGE_2D:
			if aspect_setting == "keep":
				overlay.rect_position.x = 0
				overlay.rect_position.y = 0
			elif aspect_setting == "keep_width" or aspect_setting == "keep_height":
				overlay.rect_position.x = 0
				overlay.rect_position.y = 0
				if usage == USAGE_3D:
					if aspect_diff > 1.0 + epsilon:
						overlay.rect_position.x = round((screen_size.x * aspect_diff - overlay_size.x) * 0.5)
					elif aspect_diff < 1.0 - epsilon:
						overlay.rect_position.y = round((screen_size.y / aspect_diff - overlay_size.y) * 0.5)
			elif aspect_setting == "expand":
				if usage == USAGE_3D:
					overlay.rect_size = screen_size
				elif aspect_diff > 1.0 + epsilon:
					overlay.rect_size = Vector2(round(screen_size.x * aspect_diff), round(screen_size.y))
				elif aspect_diff < 1.0 - epsilon:
					overlay.rect_size = Vector2(round(screen_size.x), round(screen_size.y / aspect_diff))
				else:
					overlay.rect_size = screen_size
			elif aspect_setting == "ignore":
				if usage == USAGE_3D:
					overlay.rect_size = screen_size
		elif stretch_setting == "viewport":
			overlay.rect_size = native_resolution
		elif stretch_setting == "2d":
			overlay.rect_size = original_resolution
			overlay_size = overlay.rect_size
			overlay.rect_position.x = 0
			overlay.rect_position.y = 0
			if aspect_setting == "expand":
				if aspect_diff > 1.0 + epsilon:
					overlay.rect_size = Vector2(round(original_resolution.y * native_aspect_ratio), round(original_resolution.y))
				elif aspect_diff < 1.0 - epsilon:
					overlay.rect_size = Vector2(round(original_resolution.x), round(original_resolution.x / native_aspect_ratio))
			elif aspect_setting == "keep_width":
				overlay.rect_position.x = 0.0
				if aspect_diff < 1.0 - epsilon:
					overlay.rect_position.y = round((overlay_size.y / aspect_diff - overlay_size.y) * 0.5)
			elif aspect_setting == "keep_height":
				overlay.rect_position.y = 0.0
				if aspect_diff > 1.0 + epsilon:
					overlay.rect_position.x = round((overlay_size.x * aspect_diff - overlay_size.x) * 0.5)
				
func change_scale_factor(val):
	scale_factor = val
	on_window_resize()
	
func change_smoothness(val):
	smoothness = val
	if sampler_material:
		sampler_material.set_shader_param("smoothness", smoothness)
		
func change_msaa(val):
	msaa = val
	if viewport:
		viewport.msaa = msaa
		
func change_fxaa(val):
	fxaa = val
	if viewport:
		viewport.fxaa = fxaa
		
func change_shadow_atlas(val):
	shadow_atlas = val
	
func on_window_resize():
	get_screen_size()
	set_viewport_size()
	resize_viewport()
	scale_viewport_canvas()
	set_shader_resolution()
	set_sampler_size()
	
func get_aspect_setting():
	return ProjectSettings.get_setting("display/window/stretch/aspect")
	
func get_stretch_setting():
	return ProjectSettings.get_setting("display/window/stretch/mode")
	
func _input(event):
	if viewport and is_inside_tree():
		viewport.input(event)
		
func _unhandled_input(event):
	if viewport and is_inside_tree():
		viewport.unhandled_input(event)
