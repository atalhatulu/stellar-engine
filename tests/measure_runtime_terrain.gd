extends SceneTree

# Runtime Terrain Measurement Script
# Measures exact chunk sizes and vertex spacing across all LOD levels in Godot engine

const PlanetChunkSphere = preload("res://scripts/rendering/planet_chunk_sphere.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("--- RUNTIME ARAZI VE LOD METRİK ÖLÇÜMÜ BAŞLADI ---")
	var radius = 3477200.0 # 3477.2 km (Test gezegeni gerçek yarıçapı)
	var sphere = PlanetChunkSphere.new()
	root.add_child(sphere)
	sphere.initialize(null, radius)
	
	print("Gezegen Yarıçapı: %.1f km | Çevre: %.1f km" % [radius / 1000.0, (2.0 * PI * radius) / 1000.0])
	print("------------------------------------------------------------------------------------------------")
	print(String("%-8s | %-20s | %-16s | %-10s | %-18s") % ["LOD Seviye", "Parça Boyutu (km)", "Köşegen (km)", "Altbölüm", "Vertex Aralığı (m)"])
	print("------------------------------------------------------------------------------------------------")
	
	var nlon = PlanetChunkSphere.BASE_NLON
	var nlat = PlanetChunkSphere.BASE_NLAT
	var circum = 2.0 * PI * radius
	
	for lvl in range(12):
		var scale = pow(2.0, lvl)
		var cur_nlat = nlat * scale
		var cur_nlon = nlon * scale
		var dlat_rad = PI / cur_nlat
		var dlon_rad = (2.0 * PI) / cur_nlon
		var lat_size_km = (dlat_rad * radius) / 1000.0
		var lon_size_km = (dlon_rad * radius) / 1000.0
		var diag_km = sqrt(lat_size_km * lat_size_km + lon_size_km * lon_size_km)
		var subdiv = 56
		if lvl < PlanetChunkSphere.SUBDIV_LEVELS.size():
			subdiv = PlanetChunkSphere.SUBDIV_LEVELS[lvl]
		elif lvl >= 10:
			subdiv = 64
		var spacing_m = (lon_size_km * 1000.0) / subdiv
		print(String("LOD %-4d | %8.2f x %-8.2f km | %12.2f km | %-10d | %14.1f m") % [lvl, lon_size_km, lat_size_km, diag_km, subdiv, spacing_m])
	
	print("------------------------------------------------------------------------------------------------")
	sphere.queue_free()
	quit(0)
