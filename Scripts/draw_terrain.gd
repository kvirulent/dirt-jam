@tool
class_name DrawTerrainMesh extends CompositorEffect

@export var regenerate: bool = false
@export var wireframe: bool = true
@export var debug: bool = false
@export var noise_seed : int = 0
@export var offset : Vector3 = Vector3.ZERO
@export_range(2, 1000, 1, "or_greater") var side_length: int = 10
@export_range(0.01, 1.0, 0.01, "or_greater") var mesh_scale: float = 1.0
@export_range(0.1, 400, 0.1, "or_greater") var zoom : float = 100.0
@export_range(-180.0, 180.0) var gradient_rotation : float = 0.0
@export_range(0.0, 300.0, 0.1, "or_greater") var height_scale : float = 50.0

var transform: Transform3D
var light: DirectionalLight3D

var rd: RenderingDevice
var p_framebuffer: RID
var p_render_pipeline: RID
var p_render_pipeline_uniform_set: RID
var p_wire_render_pipeline: RID
var p_vertex_buffer: RID
var p_vertex_array: RID
var p_index_buffer: RID
var p_index_array: RID
var p_wire_index_buffer: RID
var p_wire_index_array: RID
var vertex_format: int
var p_shader: RID
var p_wire_shader: RID
var clear_colors := PackedColorArray([Color.DARK_BLUE])
var shader_accessor: ShaderAccessor

# Shader code
# Vertex shader
var source_vertex: String
var source_fragment: String
var source_wire_fragment: String

func _init():
	shader_accessor = ShaderAccessor.new()
	source_vertex = shader_accessor.get_vertex_shader_by_name("shader");
	source_fragment = shader_accessor.get_fragment_shader_by_name("shader");
	source_wire_fragment = shader_accessor.get_fragment_shader_by_name("wireframe");
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	rd = RenderingServer.get_rendering_device()
	
	var tree := Engine.get_main_loop() as SceneTree
	var root: Node = tree.edited_scene_root if Engine.is_editor_hint() else tree.current_scene
	if root: light = root.get_node_or_null('DirectionalLight3D')

# Compile the shader
func compile_shader(vertex_shader: String, fragment_shader: String) -> RID:
	var src := RDShaderSource.new() # Initialize a shader source object
	src.source_vertex = vertex_shader # Add shader source code for the vertex shader
	src.source_fragment = fragment_shader # Add shader source code for the fragment shader
	
	# Compile the shader
	var shader_spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(src)
	var err = shader_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_VERTEX)
	if err: push_error(err) # Display errors with vertex shader compilation
	err = shader_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_FRAGMENT)
	if err: push_error(err) # Display errors with fragment shader compilation
	
	# Convert the compiled SPIRV shader to a shader RID
	var shader: RID = rd.shader_create_from_spirv(shader_spirv)
	return shader

# Creates a buffer of vertices
func create_mesh_buffers(framebuffer_format: int):
	p_shader = compile_shader(source_vertex, source_fragment)
	p_wire_shader = compile_shader(source_vertex, source_wire_fragment)
	
	var vertex_buffer := PackedFloat32Array([]) # Initialize a buffer
	var half_length = (side_length - 1) / 2.0 # ?
	
	# Iterate through each vertex we should make in x & z axes.
	# We should make a side_length * side_length plane of vertices.
	# If size_length = 10, we will make 10 * 10 vertices, 100.
	var t: int = 1 # Used to cycle the color for each vertex
	for x in side_length:
		for z in side_length:
			t += 1
			if t > 3: t = 1
			var xz: Vector2 = Vector2(x - half_length, z - half_length) * mesh_scale
			var pos: Vector3 = Vector3(xz.x, 0, xz.y)
			var color: Vector4 = Vector4(randf(), randf(), randf(), 1)
			
			# Each vertex will take 7 indexes in the buffer.
			# 0-2 are the position (0:x, 1:y, 2:z), 3-6 are the color (3:r, 4:g, 5:b, 6:a).
			for i in 3: vertex_buffer.push_back(pos[i])
			for i in 4: vertex_buffer.push_back(color[i])
	
	# Index buffers store how vertices are strung together into triangles.
	# They store the relations between vertices making up triangles.
	var index_buffer := PackedInt32Array([])
	var wire_index_buffer := PackedInt32Array([])
	
	for row in range(0, side_length * side_length - side_length, side_length):
		for i in side_length - 1:
			var v = i + row
			
			var v0 = v
			var v1 = v + side_length
			var v2 = v + side_length + 1
			var v3 = v + 1
			
			index_buffer.append_array([v0, v1, v3, v1, v2, v3])
			wire_index_buffer.append_array([v0, v1, v0, v3, v1, v3, v1, v2, v2, v3])
			
	print("Triangle Count %d" % (index_buffer.size() / 3))
	
	# Don't enable with side_length > 10
	# Print how many vertexes we created. Divide by 7, since each vertex takes up 7 indexes in the buffer.

	if debug:
		var vertex_count = vertex_buffer.size() / 7
		print("Vertex Count: %d" % vertex_count)

		#Dump vertex data
		for i in vertex_count:
			var j = i * 7
			var pos = Vector3(vertex_buffer[j], vertex_buffer[j + 1], vertex_buffer[j + 2])
			var color = Vector4(vertex_buffer[j + 3], vertex_buffer[j + 4], vertex_buffer[j + 5], vertex_buffer[j + 6])
			
			print("Vertex %d" % i)
			print("Position: %v" % pos)
			print("Color: %v" % color)

	# Pack the vertex data into a byte array
	var vertex_buffer_bytes: PackedByteArray = vertex_buffer.to_byte_array()
	p_vertex_buffer = rd.vertex_buffer_create(vertex_buffer_bytes.size(), vertex_buffer_bytes)
	var vertex_buffers := [p_vertex_buffer, p_vertex_buffer]
	
	var sizeof_float := 4
	var stride := 7
	
	# Tell the GPU the structure of the vertex data
	var vertex_attrs = [RDVertexAttribute.new(), RDVertexAttribute.new()]
	vertex_attrs[0].format = rd.DATA_FORMAT_R32G32B32_SFLOAT # Format of data, specifically a 3 32-bit component vector
	vertex_attrs[0].location = 0 # The location of the data
	vertex_attrs[0].offset = 0 # The offset of the data
	vertex_attrs[0].stride = stride * sizeof_float # How many bytes apart each index is (7 indexes for each vertex, 4 bytes for each index)
	
	vertex_attrs[1].format = rd.DATA_FORMAT_R32G32B32A32_SFLOAT # Format of data, specifically a 4 32-bit component vector
	vertex_attrs[1].location = 1 # The location of the data
	vertex_attrs[1].offset = 3 * sizeof_float # The offset of the data. 3 indexes of 4 bytes for the position vector that precedes this color vector
	vertex_attrs[1].stride = stride * sizeof_float # How many bytes apart each index is (7 indexes for each vertex, 4 bytes for each index)
	
	var index_buffer_bytes: PackedByteArray = index_buffer.to_byte_array()
	var wire_index_buffer_bytes: PackedByteArray = wire_index_buffer.to_byte_array()
	
	# Convert data to RIDs
	vertex_format = rd.vertex_format_create(vertex_attrs)
	p_vertex_array = rd.vertex_array_create(vertex_buffer.size() / stride, vertex_format, vertex_buffers)
	p_index_buffer = rd.index_buffer_create(index_buffer.size(), rd.INDEX_BUFFER_FORMAT_UINT32, index_buffer_bytes)
	p_wire_index_buffer = rd.index_buffer_create(wire_index_buffer.size(), rd.INDEX_BUFFER_FORMAT_UINT32, wire_index_buffer_bytes)
	p_index_array = rd.index_array_create(p_index_buffer, 0, index_buffer.size())
	p_wire_index_array = rd.index_array_create(p_wire_index_buffer, 0, wire_index_buffer.size())
	
	initialize_render_pipelines(framebuffer_format)
	
# Setup of the render pipeline objects
func initialize_render_pipelines(framebuffer_format: int) -> void:
	# Define some settings for the render pipeline
	# The back of triangles should not be rendered
	var raster_state = RDPipelineRasterizationState.new()
	raster_state.cull_mode = RenderingDevice.POLYGON_CULL_BACK
	
	# How the depth shader will compare triangles
	var depth_state = RDPipelineDepthStencilState.new()
	depth_state.enable_depth_write = true
	depth_state.enable_depth_test = true
	depth_state.depth_compare_operator = RenderingDevice.COMPARE_OP_GREATER
	
	# This required to create the pipeline, so set it to default
	var blend = RDPipelineColorBlendState.new()
	blend.attachments.push_back(RDPipelineColorBlendStateAttachment.new())
	
	# Create the pipeline object
	p_render_pipeline = rd.render_pipeline_create(
		p_shader, # Use the normal shader source
		framebuffer_format, # The format for the frame buffer
		vertex_format, # The format of the vertex buffer
		rd.RENDER_PRIMITIVE_TRIANGLES, # What render primitive should be used
		raster_state, # Raster configuration
		RDPipelineMultisampleState.new(), # ?
		depth_state, # Depth shader configuration
		blend # Color blend configuration
	)
	
	# Create the wireframe render pipeline
	p_wire_render_pipeline = rd.render_pipeline_create(
		p_wire_shader, # Use the wireframe shader source
		framebuffer_format, # The format for the frame buffer
		vertex_format, # The format of the vertex buffer
		rd.RENDER_PRIMITIVE_LINES, # What render primitive should be used
		raster_state, # Raster configuration
		RDPipelineMultisampleState.new(), # ?
		depth_state, # Depth shader configuration
		blend # Color blend configuration
	)
	
# Attach a function to be run each frame to render the scene
func _render_callback(_effect_callback_type: int, render_data: RenderData):
	if not enabled: return # If this tool is not enabled, do nothing
	if _effect_callback_type != effect_callback_type: return # ?
	
	# ?
	var render_scene_buffers: RenderSceneBuffersRD = render_data.get_render_scene_buffers()
	var render_scene_data: RenderSceneData = render_data.get_render_scene_data()
	if not render_scene_buffers: return
	
	# Regenerate the frame buffer and mesh buffer when asked
	if regenerate or not p_render_pipeline.is_valid():
		source_vertex = shader_accessor.get_vertex_shader_by_name("shader");
		source_fragment = shader_accessor.get_fragment_shader_by_name("shader");
		source_wire_fragment = shader_accessor.get_fragment_shader_by_name("wireframe");
		_notification(NOTIFICATION_PREDELETE)
		p_framebuffer = FramebufferCacheRD.get_cache_multipass([render_scene_buffers.get_color_texture(), render_scene_buffers.get_depth_texture()], [], 1)
		create_mesh_buffers(rd.framebuffer_get_format(p_framebuffer))
		regenerate = false
		
	# Get the current frame buffer from cache
	var current_framebuffer = FramebufferCacheRD.get_cache_multipass([render_scene_buffers.get_color_texture(), render_scene_buffers.get_depth_texture()], [], 1)
	
	# If the frame buffer has changed then reinitialize the render pipeline objects
	# This happens when the editor/game window changes (size/resolution)
	if p_framebuffer != current_framebuffer:
		p_framebuffer = current_framebuffer
		initialize_render_pipelines(rd.framebuffer_get_format(p_framebuffer))
		
	var buffer = Array()
	var model = transform
	var view = render_scene_data.get_cam_transform().inverse()
	var projection = render_scene_data.get_view_projection(0)
	
	var model_view = Projection(view * model)
	var MVP = projection * model_view
	
	# Write the GPU buffer
	for i in range(0, 16):
		buffer.push_back(MVP[i / 4][i % 4])

	buffer.push_back(gradient_rotation)
	buffer.push_back(height_scale)
	buffer.push_back(zoom)
	buffer.push_back(noise_seed)
	buffer.push_back(offset.x)
	buffer.push_back(offset.y)
	buffer.push_back(offset.z)
	buffer.push_back(1.0)
	
		
	# Pack all our buffer data to send to the GPU
	var buffer_bytes: PackedByteArray = PackedFloat32Array(buffer).to_byte_array()
	# Convert the buffer to a RID
	var p_uniform_buffer: RID = rd.uniform_buffer_create(buffer_bytes.size(), buffer_bytes)
	
	# Define an array to hold the format of uniform variables for the GPU
	var uniforms = []
	
	# We only have one buffer, so we only need to define one uniform format
	var uniform := RDUniform.new()
	uniform.binding = 0
	uniform.uniform_type = rd.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform.add_id(p_uniform_buffer)
	uniforms.push_back(uniform)
	
	# Delete the old uniform set and define a new one
	if p_render_pipeline_uniform_set.is_valid():
		rd.free_rid(p_render_pipeline_uniform_set)
		
	p_render_pipeline_uniform_set = rd.uniform_set_create(uniforms, p_shader, 0)
	
	# Add a label for frame capturing programs
	rd.draw_command_begin_label("Terrain Mesh", Color(1.0, 1.0, 1.0, 1.0))
	# Construct the draw call
	# Initialize the object which holds the draw commands
	var draw_list = rd.draw_list_begin(p_framebuffer, rd.DRAW_IGNORE_ALL, clear_colors, 1.0, 0, Rect2(), 0)

	# Add our render pipeline and index array to the draw call
	if wireframe:
		rd.draw_list_bind_render_pipeline(draw_list, p_wire_render_pipeline)
		rd.draw_list_bind_index_array(draw_list, p_wire_index_array)
	else:
		rd.draw_list_bind_render_pipeline(draw_list, p_render_pipeline)
		rd.draw_list_bind_index_array(draw_list, p_index_array)
		
	# Add our vertex data & data format information to the draw call
	rd.draw_list_bind_vertex_array(draw_list, p_vertex_array)
	rd.draw_list_bind_uniform_set(draw_list, p_render_pipeline_uniform_set, 0)
	rd.draw_list_draw(draw_list, true, 1) # Send the draw call
	rd.draw_list_end()
	rd.draw_command_end_label() # Close the draw call
	
# Cleanup function
func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if p_render_pipeline.is_valid():
			rd.free_rid(p_render_pipeline)
		if p_wire_render_pipeline.is_valid():
			rd.free_rid(p_wire_render_pipeline)
		if p_vertex_array.is_valid():
			rd.free_rid(p_vertex_array)
		if p_vertex_buffer.is_valid():
			rd.free_rid(p_vertex_buffer)
		if p_index_array.is_valid():
			rd.free_rid(p_index_array)
		if p_index_buffer.is_valid():
			rd.free_rid(p_index_buffer)
		if p_wire_index_array.is_valid():
			rd.free_rid(p_wire_index_array)
		if p_wire_index_buffer.is_valid():
			rd.free_rid(p_wire_index_buffer)
