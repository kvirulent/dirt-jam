class_name ShaderAccessor extends Node

func get_fragment_shader_by_name(name):
	var file = FileAccess.open("res://shaders/%s.frag" % name, FileAccess.READ);
	var out = file.get_as_text();
	file.close();
	return out;
	
func get_vertex_shader_by_name(name):
	var file = FileAccess.open("res://shaders/%s.vert" % name, FileAccess.READ);
	var out = file.get_as_text();
	file.close();
	return out;
