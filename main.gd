extends Node3D

class Ray:
	var origin: Vector3
	var direction: Vector3
	
	func _init(orig: Vector3, dir: Vector3):
		origin = orig
		direction = dir.normalized()
	
	func __to_string() -> String:
		return "Ray(origin: %s, direction: %s)" % [origin, direction]

class Triangle:
	var v0: Vector3
	var v1: Vector3
	var v2: Vector3
	var normal: Vector3
	
	func _init(vertex0: Vector3, vertex1: Vector3, vertex2: Vector3):
		v0 = vertex0
		v1 = vertex1
		v2 = vertex2
		normal = (v1 - v0).cross(v2 - v0).normalized()
	
	func intersect(ray: Ray) -> Dictionary:
		var epsilon = 0.0000001
		var edge1 = v1 - v0
		var edge2 = v2 - v0
		var h = ray.direction.cross(edge2)
		var a = edge1.dot(h)
		
		if a > -epsilon and a < epsilon:
			return {"hit": false}
		
		var f = 1.0 / a
		var s = ray.origin - v0
		var u = f * s.dot(h)
		
		if u < 0.0 or u > 1.0:
			return {"hit": false}
		
		var q = s.cross(edge1)
		var v = f * ray.direction.dot(q)
		
		if v < 0.0 or u + v > 1.0:
			return {"hit": false}
		
		var t = f * edge2.dot(q)
		
		if t > epsilon:
			return {
				"hit": true,
				"distance": t,
				"point": ray.origin + ray.direction * t,
				"normal": normal
			}
		
		return {"hit": false}

class Traceable:
	var transform: Transform3D
	var color: Color
	var triangles: Array
	
	func _init(mesh_transform: Transform3D, mesh_color: Color):
		self.transform = mesh_transform
		self.color = mesh_color
		self.triangles = []
	
	func add_triangle(v0: Vector3, v1: Vector3, v2: Vector3):
		var t = self.transform
		triangles.append(Triangle.new(t * v0, t * v1, t * v2))
	
	func intersect(ray: Ray) -> Dictionary:
		var closest_hit = {"hit": false, "distance": INF}
		for triangle in triangles:
			var hit = triangle.intersect(ray)
			if hit["hit"] and hit["distance"] < closest_hit["distance"]:
				closest_hit = hit
		return closest_hit

func extract_mesh_triangles(mesh_instance: MeshInstance3D) -> Array:
	var triangles = []
	var mesh = mesh_instance.mesh
	
	if mesh is ArrayMesh:
		for surface in range(mesh.get_surface_count()):
			var arrays = mesh.surface_get_arrays(surface)
			var vertices = arrays[Mesh.ARRAY_VERTEX]
			var indices = arrays[Mesh.ARRAY_INDEX]
			
			if indices:
				for i in range(0, indices.size(), 3):
					triangles.append([
						vertices[indices[i]],
						vertices[indices[i+1]],
						vertices[indices[i+2]]
					])
			else:
				for i in range(0, vertices.size(), 3):
					triangles.append([
						vertices[i],
						vertices[i+1],
						vertices[i+2]
					])
	return triangles

func generate_traceable_objects() -> Array:
	var traceable_objects = []
	var mesh_instances = []
	
	# Nowa implementacja z użyciem kolejki
	var queue = [self]
	while not queue.is_empty():
		var node = queue.pop_front()
		if node is MeshInstance3D:
			mesh_instances.append(node)
		for child in node.get_children():
			queue.append(child)
	
	for mesh_instance in mesh_instances:
		var color = Color.WHITE
		if mesh_instance.material_override:
			color = mesh_instance.material_override.albedo_color
		elif mesh_instance.mesh.get_surface_count() > 0:
			var material = mesh_instance.mesh.surface_get_material(0)
			if material:
				color = material.albedo_color
		
		var traceable = Traceable.new(
			mesh_instance.global_transform,
			color
		)
		
		var triangles = extract_mesh_triangles(mesh_instance)
		for triangle in triangles:
			traceable.add_triangle(triangle[0], triangle[1], triangle[2])
		
		traceable_objects.append(traceable)
	
	return traceable_objects

func raytrace(width: int, height: int, camera_pos: Vector3, look_at: Vector3) -> Image:
	var image = Image.create(width, height, false, Image.FORMAT_RGB8)
	var traceable_objects = generate_traceable_objects()
	var light_dir = Vector3(0.6, -1, 0.8).normalized()
	var ambient_light = Color(0.2, 0.2, 0.2)
	
	var forward = (look_at - camera_pos).normalized()
	var right = forward.cross(Vector3.UP).normalized()
	var camera_up = right.cross(forward)
	
	var aspect_ratio = float(width) / height
	var fov = deg_to_rad(60)
	var screen_width = tan(fov / 2) * 2
	var screen_height = screen_width / aspect_ratio
	
	for y in range(height):
		for x in range(width):
			var nx = (x + 0.5) / width * 2 - 1
			var ny = 1 - (y + 0.5) / height * 2
			
			var ray_dir = (
				forward +
				right * (nx * screen_width / 2) +
				camera_up * (ny * screen_height / 2)
			).normalized()
			
			var ray = Ray.new(camera_pos, ray_dir)
			var closest_hit = {"hit": false, "distance": INF}
			
			for obj in traceable_objects:
				var hit = obj.intersect(ray)
				if hit["hit"] and hit["distance"] < closest_hit["distance"]:
					closest_hit = hit
					closest_hit["obj"] = obj
			
			var pixel_color = ambient_light
			if closest_hit["hit"]:
				var diffuse = max(0, -light_dir.dot(closest_hit["normal"]))
				pixel_color = closest_hit["obj"].color * (ambient_light + Color.WHITE * diffuse)
				
				# Proste odbicia
				var reflect_dir = ray_dir - 2 * ray_dir.dot(closest_hit["normal"]) * closest_hit["normal"]
				var reflect_ray = Ray.new(closest_hit["point"] + closest_hit["normal"] * 0.001, reflect_dir)
				var reflect_color = Color.BLACK
				
				for obj in traceable_objects:
					var hit = obj.intersect(reflect_ray)
					if hit["hit"]:
						reflect_color = obj.color * 0.5
						break
				
				pixel_color = pixel_color * 0.8 + reflect_color * 0.2
			
			image.set_pixel(x, y, pixel_color.clamp())
	
	return image

func _ready():
	# Debug: Informacja o rozpoczęciu ładowania sceny
	print("Testowa wiadomość")
	print("Rozpoczynam ładowanie sceny...")
	
	# Ładowanie sceny GLB z obsługą błędów
	var scene
	var instance
	var use_test_scene = false
	
	if ResourceLoader.exists("res://scena2.glb"):
		scene = load("res://sciana_podloga.glb")
		instance = scene.instantiate()
		add_child(instance)
		print("Scena GLB załadowana pomyślnie")
	else:
		print("Błąd: Nie znaleziono pliku GLB! Tworzę testową scenę...")
		create_test_scene()
		use_test_scene = true
	
	# Konfiguracja kamery
	var camera = Camera3D.new()
	camera.position = Vector3(10, 10, -20)
	camera.look_at(Vector3.ZERO)
	add_child(camera)
	
	# Testowa scena z podstawowymi obiektami
	if use_test_scene:
		create_test_objects()
	
	# Weryfikacja danych przed renderowaniem
	var traceable_objects = generate_traceable_objects()
	print("Znaleziono obiektów do renderowania: ", traceable_objects.size())
	
	if traceable_objects.is_empty():
		printerr("Błąd: Brak obiektów do renderowania!")
		return
	
	# Renderowanie z niską rozdzielczością do testów
	print("Rozpoczynam renderowanie testowe...")
	var image = raytrace(2000, 2000, camera.position, Vector3.ZERO)
	
	# Zapis i weryfikacja wyniku
	if image.save_png("res://raytraced_resultpodlogaprzesunieta.png") == OK:
		print("Renderowanie zakończone! Obraz zapisany jako 'raytraced_result.png'")
		
		# Wyświetl przykładowe piksele
		print("Przykładowe piksele:")
		for i in range(3):
			var pixel = image.get_pixel(i * 4, i * 2)
			print("Piksel (%d, %d): %s" % [i * 4, i * 2, pixel])
	else:
		printerr("Błąd zapisu obrazu!")

func create_test_scene():
	# Tworzenie podstawowych obiektów testowych
	var test_sphere = MeshInstance3D.new()
	test_sphere.mesh = SphereMesh.new()
	test_sphere.mesh.radius = 1.0
	test_sphere.position = Vector3(0, 1, 0)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.RED
	test_sphere.material_override = material
	
	add_child(test_sphere)
	print("Utworzono testową kulę")

func create_test_objects():
	# Dodatkowe obiekty testowe
	var floor = MeshInstance3D.new()
	floor.mesh = BoxMesh.new()
	floor.mesh.size = Vector3(5, 0.1, 5)
	floor.position = Vector3(0, 0, 0)
	
	var floor_material = StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.8, 0.8, 0.8)
	floor.material_override = floor_material
	
	add_child(floor)
	print("Utworzono podłogę testową")
