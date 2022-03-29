@tool
extends TBLoader
# move to suitable category.
@export_global_file("*.cfg") var game_config := "":
	get: return game_config
	set(value): 
		game_config = value
		notify_property_list_changed()

var update_entity_files = false:
	get: return update_entity_files
	set(value):
		update_entity_files = false
		refresh_entities()
var property_ignore_list : Array[String] = ["process_mode",
	"process_priority",
	"editor_description",
	"rotation_edit_mode",
	"rotation_order",
	"visibility_parent",
	"top_level"]	
var entity_list : Dictionary:
	get: return entity_list
	set(value):
		entity_list = value
var godot_types_to_trenchbroom : Dictionary = {
	1: "(string)", #bool
	2: "(integer)", #int
	3: "(float)", #float
	4: "(string)", #string
	5: "(string)", #vector2
	6: "(string)", #vector2i
	7: "(string)", #rect2
	8: "(string)", #rect2i
	9: "(string)", #vector3
	10: "(string)", #vector3i
	11: "(string)", #transform2d
	12: "(string)", #plane
	13: "(string)", #quaternion
	14: "(string)", #aabb
	15: "(string)", #basis
	16: "(string)", #transform3d
	17: "(color)", #color
	18: "(string)", #string_name
	19: "(string)", #node_path
	20: "(string)", #rid
	21: "(string)", #object
	22: "(string)", #callable
	23: "(string)", #signal
	24: "(string)", #dictionary
	25: "(string)", #array
	26: "(string)", #PackedByteArray
	27: "(string)", #PackedInt3dArray
	28: "(string)", #PackedInt64Array
	29: "(string)", #PackedFloat32Array
	30: "(string)", #PackedFloat64Array
	31: "(string)", #PackedStringArray
	32: "(string)", #PackedVector2Array
	33: "(string)", #PackedVector3Array
	34: "(string)", #PackedColorArray
}
		
func _get_property_list() -> Array:
	var ret := []
	# NOTE: exported vars will not show in the inspector if they're not added to a category.
	if not game_config.is_empty():
		ret.append({
			"name" : "Entities",
			"type" : TYPE_NIL,
			#"hint": PROPERTY_HINT_NONE,
			"usage": PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_SCRIPT_VARIABLE
			})
		ret.append({
			"name" : "entity_list",
			"hint": PROPERTY_HINT_ARRAY_TYPE,
			"type": TYPE_DICTIONARY
			})
		ret.append({
			"name" : "update_entity_files",
			"hint" : PROPERTY_HINT_TYPE_STRING,
			"type" : TYPE_BOOL
		})
		ret.append({
			"name" : "property_ignore_list",
			"hint" : PROPERTY_HINT_ARRAY_TYPE,
			"type" : TYPE_ARRAY
		})
	ret.append({
		"name" : "Create Config File",
		"type" : TYPE_NIL,
		#"hint": PROPERTY_HINT_NONE,
		"usage": PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_SCRIPT_VARIABLE
		})
	return ret

func get_file_paths_by_ext(directoryPath: String, extension: String, recursive: bool = true) -> Array:
	var dir := Directory.new()
	if dir.open(directoryPath) != OK:
		printerr("Warning: could not open directory: ", directoryPath)
		return []
	#dir.include_hidden = true
	#dir.include_navigational = true
	if dir.list_dir_begin() != OK:
		printerr("Warning: could not list contents of: ", directoryPath)
		return []
	dir.list_dir_begin()
	
	var filePaths := []
	var fileName := dir.get_next()
	
	while fileName != "":
		if dir.current_is_dir():
			if recursive:
				var dirPath = dir.get_current_dir() + "/" + fileName
				filePaths += get_file_paths_by_ext(dirPath, extension, recursive)
		else:
			if fileName.get_extension() == extension:				
				var filePath = dir.get_current_dir() + "/" + fileName
				filePaths.append(filePath)
		fileName = dir.get_next()
	return filePaths

func refresh_entities():
	entity_list = {}
	var custom_entities : Array = get_file_paths_by_ext("res://entities/", "tscn", true)
	for i in custom_entities:
		var entity_name = i.rsplit("/", true, 1)[1].trim_suffix(".tscn")
		var scene_resource = load(i)
		var entity = scene_resource.instantiate()
		add_child(entity)
		entity_list[entity_name] = get_entity_properties(entity, [7], property_ignore_list)
		remove_child(entity)
	# after creating the entity list, run fgd constructor
	create_fgd_files(game_config, entity_list)

func get_entity_properties(entity, usage_filter: Array, ignore_list: Array) -> Dictionary:
	var entity_properties := {}
	var filtered_properties := {}
	for i in entity.get_property_list():
	# 7 = PROPERTY_USAGE_DEFAULT: Storage, editor and network. 8199: user-created vars/properties.
		if i["usage"] in usage_filter:
			# ignore properties in property_ignore_list. not very graceful.
			if !ignore_list.has(i["name"]):
				filtered_properties[i["name"]] = i
				
	for i in filtered_properties.keys():
		var property_name = filtered_properties[i]["name"]		
		var property_type = godot_types_to_trenchbroom[filtered_properties[i]["type"]]
		var property_value : String = str(entity.get(property_name))
		if property_type == "(string)":
			property_value = "\"" + property_value + "\""
		if property_type == "(color)":
			property_value = property_value.trim_prefix("(").trim_suffix(", 1)")
			property_value = "".join(property_value.split(","))
			property_value = "\"" + property_value + "\""
		entity_properties[property_name] = [entity.get(property_name), property_type, property_value]
		entity_properties[property_name] = {"Value": entity.get(property_name), "Trenchbroom": {"Type": property_type, "Name": property_name, "Value": property_value}}
		
	return entity_properties

func create_fgd_files(path: String, entity_list: Dictionary):
	var dir = Directory.new()
	dir.open("res://entities")
	var file_path = path.trim_suffix("GameConfig.cfg")
	var fgd_default_content : String = """///

@SolidClass = worldspawn : "World entity" []

@baseclass size(-16 -16 -24, 16 16 32) color(0 255 0) = PlayerClass []

@PointClass base(PlayerClass) = info_player_start : "Player 1 start" []

///
"""
	var entities_arr = []
	for i in entity_list.keys():
		# entity header. perhaps this sort of stuff, including mdl paths, can be customized in a root helper node (like Qodot's PointClass/BaseClass nodes).
		var entity_size := "size(-4 -4 -4, 4 4 4)"
		var entity_color := "color(255 255 0)"
		var entity_body = "@PointClass " + entity_size + " " + entity_color + " = " + i + " : " + "\"" + i + "\"" + " [" + "%s" + "\n]"
		var property_list = entity_list[i]
		var property = ""
		for p in property_list:
			# entity body
			var property_name = property_list[p]["Trenchbroom"]["Name"]
			var property_type = property_list[p]["Trenchbroom"]["Type"]
			var property_value = property_list[p]["Trenchbroom"]["Value"]
			property += "\n	" + property_name+property_type + " : " + "\"" + property_name +"\"" + " : " + property_value			
		
		entity_body = entity_body % property
		entities_arr.append(entity_body)
#	for i in dir.get_directories():	
	for i in entities_arr:
		fgd_default_content += "\n" + i
	var file = File.new()
	file.open(file_path + "entity_file_name.fgd", File.WRITE_READ)
	file.store_string(fgd_default_content)
	file.close()
