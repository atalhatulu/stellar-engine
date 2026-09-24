class_name DiscoveryCatalogPanel
extends PanelContainer

var title_label: Label
var summary_label: Label
var records_label: RichTextLabel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	position = Vector2(-290, -230)
	size = Vector2(580, 460)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.035, 0.07, 0.96)
	style.border_color = Color(0.12, 0.72, 1.0, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(18)
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	title_label = Label.new()
	title_label.text = "KEŞİF KATALOĞU"
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color(0.4, 0.86, 1.0))
	column.add_child(title_label)
	summary_label = Label.new()
	summary_label.add_theme_color_override("font_color", Color(0.68, 0.78, 0.9))
	column.add_child(summary_label)
	var separator := HSeparator.new()
	column.add_child(separator)
	records_label = RichTextLabel.new()
	records_label.bbcode_enabled = true
	records_label.fit_content = false
	records_label.scroll_active = true
	records_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	records_label.add_theme_font_size_override("normal_font_size", 14)
	column.add_child(records_label)
	var hint := Label.new()
	hint.text = "[K] Kapat"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_color_override("font_color", Color(0.5, 0.62, 0.72))
	column.add_child(hint)
	visible = false


func toggle(catalog: DiscoveryCatalog) -> void:
	visible = not visible
	if visible:
		refresh(catalog)


func refresh(catalog: DiscoveryCatalog) -> void:
	var counts := {"STAR": 0, "PLANET": 0, "MOON": 0}
	var lines: Array[String] = []
	var ids := catalog.get_ids()
	for identifier in ids:
		var record := catalog.get_record(identifier)
		var kind := str(record.get("kind", "BİLİNMİYOR"))
		counts[kind] = int(counts.get(kind, 0)) + 1
		lines.append("[color=#70d8ff]%s[/color]  [color=#91a4ba]%s[/color]" % [str(record.get("name", identifier)), _kind_name(kind)])
	summary_label.text = "%d yıldız  •  %d gezegen  •  %d uydu  •  toplam %d" % [counts.STAR, counts.PLANET, counts.MOON, ids.size()]
	records_label.text = "[color=#718196]Henüz kayıt yok. Tarama sistemi daha sonra açılabilir.[/color]" if lines.is_empty() else "\n\n".join(lines)


static func _kind_name(kind: String) -> String:
	return {"STAR": "Yıldız", "PLANET": "Gezegen", "MOON": "Uydu"}.get(kind, kind.capitalize())
