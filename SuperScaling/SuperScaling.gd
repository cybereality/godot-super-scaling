# [Godot Super Scaling]
# created by Andres Hernandez
extends Node

export (float, 0.1, 2.0) var scale_factor = 1.0 setget change_scale_factor
export (bool) var enable_on_play = false
export (NodePath) var game_world
export (int, "3D", "2D") var usage = 0
export (int, "Disabled", "2X", "4X", "8X", "16X") var msaa = 0 setget change_msaa
export (bool) var fxaa = false setget change_fxaa
export (int, 1, 4096) var shadow_atlas = 4096 setget change_shadow_atlas
onready var averaging_shader = load(get_script().resource_path.get_base_dir() + "/Averaging.tres")
onready var super_shader = load(get_script().resource_path.get_base_dir() + "/Super.tres")
var averaging_material
var super_material
var game_node
var averaging_overlay
var super_overlay
var viewport
var super_viewport
var viewport_size
var root_viewport
var native_resolution
var original_resolution
var native_aspect_ratio
var original_aspect_ratio
enum {USAGE_3D, USAGE_2D}
const epsilon = 0.01

func _ready():
	if (enable_on_play):
		game_node = get_node(game_world)
		if game_node:
			get_parent().call_deferred("remove_child", game_node)
			get_screen_size()
			create_sampler()
			create_super()
			create_viewport()
			create_super_viewport()
			set_shader_texture()
			viewport.call_deferred("add_child", game_node)
			super_viewport.call_deferred("add_child", viewport)
			get_parent().call_deferred("add_child", super_viewport)
			original_resolution = native_resolution
			original_aspect_ratio = native_aspect_ratio
			root_viewport = get_viewport()
			#warning-ignore:RETURN_VALUE_DISCARDED
			viewport.connect("size_changed", self, "on_window_resize")
			#warning-ignore:RETURN_VALUE_DISCARDED
			root_viewport.connect("size_changed", self, "on_window_resize")
			on_window_resize()
			change_msaa(msaa)
			change_fxaa(fxaa)
			set_process_input(false)
			set_process_unhandled_input(false)
		else:
			print("ERROR [Godot Super Scaling] Game World must be set in inspector.")
	
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
	
func create_super_viewport():
	super_viewport = Viewport.new()
	super_viewport.name = "SuperViewport"
	super_viewport.size = native_resolution
	super_viewport.usage = Viewport.USAGE_3D if usage == USAGE_3D else Viewport.USAGE_2D
	super_viewport.render_target_clear_mode = Viewport.CLEAR_MODE_NEVER
	super_viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
	super_viewport.render_target_v_flip = true
	super_viewport.size_override_stretch = true
	super_viewport.msaa = Viewport.MSAA_DISABLED
	super_viewport.shadow_atlas_size = shadow_atlas
	
func create_sampler():
	averaging_overlay = ColorRect.new()
	averaging_overlay.name = "AveragingOverlay"
	averaging_material = ShaderMaterial.new()
	averaging_material.shader = averaging_shader
	averaging_overlay.material = averaging_material
	averaging_overlay.visible = false
	add_child(averaging_overlay)
	
func create_super():
	super_overlay = ColorRect.new()
	super_overlay.name = "SuperOverlay"
	super_material = ShaderMaterial.new()
	super_material.shader = super_shader
	super_overlay.material = super_material
	add_child(super_overlay)

func set_shader_texture():
	yield(VisualServer, "frame_post_draw")
	var view_texture = viewport.get_texture()
	view_texture.flags = 0
	view_texture.viewport_path = viewport.get_path()
	averaging_material.set_shader_param("viewport", view_texture)
	super_material.set_shader_param("viewport", view_texture)
	change_scale_factor(scale_factor)
	set_process_input(true)
	set_process_unhandled_input(true)
	
func set_shader_resolution():
	if averaging_material:
		averaging_material.set_shader_param("view_resolution", viewport_size)
	if super_material:
		super_material.set_shader_param("view_resolution", viewport_size)
	
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
	if super_viewport:
		super_viewport.size = viewport_size
			
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
		super_viewport.set_size_override(true, viewport.size)
			
func set_sampler_size():
	if averaging_overlay:
		var stretch_setting = get_stretch_setting()
		var aspect_setting = get_aspect_setting()
		var aspect_diff = native_aspect_ratio / original_aspect_ratio
		if usage == USAGE_2D:
			if aspect_diff < 1.0 - epsilon and aspect_setting == "keep_width":
				averaging_overlay.rect_size = Vector2(round(original_resolution.x), round(original_resolution.x / native_aspect_ratio))
			elif aspect_diff > 1.0 + epsilon and aspect_setting == "keep_height":
				averaging_overlay.rect_size = Vector2(round(original_resolution.y * native_aspect_ratio), round(original_resolution.y))
			else:
				averaging_overlay.rect_size = Vector2(round(original_resolution.x), round(original_resolution.y))
		elif usage == USAGE_3D:
			averaging_overlay.rect_size = Vector2(round(native_resolution.x), round(native_resolution.y))
			if aspect_diff > 1.0 + epsilon:
				averaging_overlay.rect_size.x = round(native_resolution.y * original_aspect_ratio)
			elif aspect_diff < 1.0 - epsilon:
				averaging_overlay.rect_size.y = round(native_resolution.x / original_aspect_ratio)
		var overlay_size = averaging_overlay.rect_size
		var screen_size = Vector2(0.0, 0.0)
		if usage == USAGE_2D:
			screen_size = original_resolution
		elif usage == USAGE_3D:
			screen_size = native_resolution
		if stretch_setting == "disabled" or usage == USAGE_2D:
			if aspect_setting == "keep":
				averaging_overlay.rect_position.x = 0
				averaging_overlay.rect_position.y = 0
			elif aspect_setting == "keep_width" or aspect_setting == "keep_height":
				averaging_overlay.rect_position.x = 0
				averaging_overlay.rect_position.y = 0
				if usage == USAGE_3D:
					if aspect_diff > 1.0 + epsilon:
						averaging_overlay.rect_position.x = round((screen_size.x * aspect_diff - overlay_size.x) * 0.5)
					elif aspect_diff < 1.0 - epsilon:
						averaging_overlay.rect_position.y = round((screen_size.y / aspect_diff - overlay_size.y) * 0.5)
			elif aspect_setting == "expand":
				if usage == USAGE_3D:
					averaging_overlay.rect_size = screen_size
				elif aspect_diff > 1.0 + epsilon:
					averaging_overlay.rect_size = Vector2(round(screen_size.x * aspect_diff), round(screen_size.y))
				elif aspect_diff < 1.0 - epsilon:
					averaging_overlay.rect_size = Vector2(round(screen_size.x), round(screen_size.y / aspect_diff))
				else:
					averaging_overlay.rect_size = screen_size
			elif aspect_setting == "ignore":
				if usage == USAGE_3D:
					averaging_overlay.rect_size = screen_size
		elif stretch_setting == "viewport":
			averaging_overlay.rect_size = native_resolution
		elif stretch_setting == "2d":
			averaging_overlay.rect_size = original_resolution
			overlay_size = averaging_overlay.rect_size
			averaging_overlay.rect_position.x = 0
			averaging_overlay.rect_position.y = 0
			if aspect_setting == "expand":
				if aspect_diff > 1.0 + epsilon:
					averaging_overlay.rect_size = Vector2(round(original_resolution.y * native_aspect_ratio), round(original_resolution.y))
				elif aspect_diff < 1.0 - epsilon:
					averaging_overlay.rect_size = Vector2(round(original_resolution.x), round(original_resolution.x / native_aspect_ratio))
			elif aspect_setting == "keep_width":
				averaging_overlay.rect_position.x = 0.0
				if aspect_diff < 1.0 - epsilon:
					averaging_overlay.rect_position.y = round((overlay_size.y / aspect_diff - overlay_size.y) * 0.5)
			elif aspect_setting == "keep_height":
				averaging_overlay.rect_position.y = 0.0
				if aspect_diff > 1.0 + epsilon:
					averaging_overlay.rect_position.x = round((overlay_size.x * aspect_diff - overlay_size.x) * 0.5)
		super_overlay.rect_size = averaging_overlay.rect_size
		super_overlay.rect_position = averaging_overlay.rect_position
				
func change_scale_factor(val):
	scale_factor = val
	on_window_resize()
		
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
