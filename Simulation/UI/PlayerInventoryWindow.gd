extends CanvasLayer
class_name PlayerInventoryWindow

## Modal popup window for the player's inventory and shop browsing.
##
## Two modes:
##   * "player" — read-only display of the player's owned slots.
##   * "shop"   — adds category tabs (e.g. Essen / Kleidung) listing buyable
##                items in the current shop building, with their stock, price
##                and an action button per item.
##
## The window is mode-driven: external code calls show_for_state(state) where
## `state` is the Dictionary produced by Citizen.get_player_inventory_ui_state().
## Re-calling show_for_state replaces the contents in-place without rebuilding
## the popup chrome.

const UiThemeScript = preload("res://Simulation/UI/UiTheme.gd")
const PlayerInventoryCatalogScript = preload("res://Simulation/UI/PlayerInventoryCatalog.gd")

signal action_pressed(action_id: String)
signal closed
signal ui_interacted

var _dim_background: ColorRect = null
var _window_panel: PanelContainer = null
var _title_label: Label = null
var _close_button: Button = null
var _status_label: RichTextLabel = null
var _tab_row: HBoxContainer = null
var _item_grid: GridContainer = null
var _empty_label: Label = null

var _current_mode: String = ""
var _current_category: String = ""
var _last_categories: Array = []
var _tab_buttons: Dictionary = {}  # category id -> Button


func _ready() -> void:
	layer = 64  # above HUD overlays
	_build_ui()
	hide_window()


func _unhandled_input(event: InputEvent) -> void:
	if not _window_panel.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_emit_close()
			get_viewport().set_input_as_handled()


## Renders the given UI state. Picks player- or shop-layout based on the
## state's "mode" field. Pass an empty / "visible": false state to hide.
func show_for_state(state: Dictionary) -> void:
	if not bool(state.get("visible", false)):
		hide_window()
		return
	var mode := str(state.get("mode", "player"))
	_current_mode = mode
	_window_panel.visible = true
	_dim_background.visible = true

	_title_label.text = str(state.get("title", "Inventar"))
	_status_label.clear()
	_status_label.append_text(str(state.get("status_text", "")))

	var categories: Array = state.get("categories", [])
	var player_slots: Array = state.get("player_slots", [])
	_last_categories = categories
	_tab_row.visible = mode == "shop" and categories.size() > 1
	_rebuild_tabs(categories)

	if mode == "shop":
		var active_category := _resolve_active_category(categories)
		_current_category = active_category
		_apply_tab_active_state(active_category)
		_render_category_items(categories, active_category)
	else:
		_current_category = ""
		_render_player_slots(player_slots)


func hide_window() -> void:
	_window_panel.visible = false
	_dim_background.visible = false


func is_open() -> bool:
	return _window_panel != null and _window_panel.visible


func _build_ui() -> void:
	_dim_background = ColorRect.new()
	_dim_background.color = Color(0.0, 0.0, 0.0, 0.55)
	_dim_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim_background.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim_background.gui_input.connect(_on_dim_background_gui_input)
	add_child(_dim_background)

	_window_panel = PanelContainer.new()
	_window_panel.theme = UiThemeScript.get_or_build()
	_window_panel.custom_minimum_size = Vector2(560, 420)
	_window_panel.set_anchors_preset(Control.PRESET_CENTER)
	_window_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_window_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_window_panel.pivot_offset = Vector2(280, 210)
	# Centering: PRESET_CENTER aligns to the center anchor; we offset back by
	# half the minimum size so the panel renders centered before children
	# stretch it further.
	_window_panel.offset_left = -280
	_window_panel.offset_top = -210
	_window_panel.offset_right = 280
	_window_panel.offset_bottom = 210
	_window_panel.gui_input.connect(_on_inventory_gui_input)
	add_child(_window_panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	_window_panel.add_child(root_vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UiThemeScript.SEPARATION_NORMAL)
	root_vbox.add_child(header)

	_title_label = Label.new()
	_title_label.text = "Inventar"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_HEADING)
	_title_label.add_theme_color_override("font_color", UiThemeScript.TEXT_PRIMARY)
	header.add_child(_title_label)

	_close_button = Button.new()
	_close_button.text = "X"
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.custom_minimum_size = Vector2(36, 32)
	_close_button.gui_input.connect(_on_inventory_gui_input)
	_close_button.pressed.connect(_emit_close)
	header.add_child(_close_button)

	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.fit_content = true
	_status_label.scroll_active = false
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.custom_minimum_size = Vector2(520, 48)
	_status_label.add_theme_color_override("default_color", UiThemeScript.TEXT_SECONDARY)
	_status_label.add_theme_font_size_override("normal_font_size", UiThemeScript.FONT_SIZE_BODY)
	root_vbox.add_child(_status_label)

	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)
	_tab_row.visible = false
	root_vbox.add_child(_tab_row)

	var content_scroll := ScrollContainer.new()
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_scroll.custom_minimum_size = Vector2(520, 260)
	root_vbox.add_child(content_scroll)

	_item_grid = GridContainer.new()
	_item_grid.columns = 3
	_item_grid.add_theme_constant_override("h_separation", UiThemeScript.SEPARATION_NORMAL)
	_item_grid.add_theme_constant_override("v_separation", UiThemeScript.SEPARATION_NORMAL)
	_item_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.add_child(_item_grid)

	_empty_label = Label.new()
	_empty_label.text = "Keine Eintraege."
	_empty_label.add_theme_color_override("font_color", UiThemeScript.TEXT_MUTED)
	_empty_label.visible = false
	root_vbox.add_child(_empty_label)


func _rebuild_tabs(categories: Array) -> void:
	for child in _tab_row.get_children():
		child.queue_free()
	_tab_buttons.clear()
	if categories.size() <= 1:
		return
	for cat_var in categories:
		if cat_var is not Dictionary:
			continue
		var cat := cat_var as Dictionary
		var cat_id := str(cat.get("id", ""))
		if cat_id.is_empty():
			continue
		var btn := Button.new()
		var icon_text := str(cat.get("icon", ""))
		var label_text := str(cat.get("label", cat_id))
		btn.text = ("%s  %s" % [icon_text, label_text]) if not icon_text.is_empty() else label_text
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(128, 34)
		btn.gui_input.connect(_on_inventory_gui_input)
		btn.pressed.connect(_on_tab_pressed.bind(cat_id))
		_tab_row.add_child(btn)
		_tab_buttons[cat_id] = btn


func _resolve_active_category(categories: Array) -> String:
	if _current_category.is_empty() == false:
		for cat_var in categories:
			if cat_var is Dictionary and str((cat_var as Dictionary).get("id", "")) == _current_category:
				return _current_category
	for cat_var in categories:
		if cat_var is Dictionary:
			var id := str((cat_var as Dictionary).get("id", ""))
			if not id.is_empty():
				return id
	return ""


func _apply_tab_active_state(active_id: String) -> void:
	for cat_id_var in _tab_buttons.keys():
		var cat_id := str(cat_id_var)
		var btn: Button = _tab_buttons[cat_id]
		UiThemeScript.apply_accent_state(btn, cat_id == active_id)


func _render_category_items(categories: Array, active_id: String) -> void:
	_clear_item_grid()
	var items: Array = []
	for cat_var in categories:
		if cat_var is not Dictionary:
			continue
		var cat := cat_var as Dictionary
		if str(cat.get("id", "")) == active_id:
			items = cat.get("items", [])
			break
	_empty_label.visible = items.is_empty()
	for item_var in items:
		if item_var is not Dictionary:
			continue
		_item_grid.add_child(_build_shop_item_card(item_var as Dictionary))


func _render_player_slots(slots: Array) -> void:
	_clear_item_grid()
	_empty_label.visible = slots.is_empty()
	for slot_var in slots:
		if slot_var is not Dictionary:
			continue
		_item_grid.add_child(_build_player_slot_card(slot_var as Dictionary))


func _build_player_slot_card(slot: Dictionary) -> Control:
	var card := _make_card_container()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)
	card.add_child(vbox)

	vbox.add_child(_make_icon_block(str(slot.get("icon", ""))))

	var name_label := Label.new()
	name_label.text = str(slot.get("label", ""))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_BODY)
	vbox.add_child(name_label)

	var count := int(slot.get("count", 0))
	var count_label := Label.new()
	count_label.text = "x %d" % count
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_LABEL)
	var count_color := UiThemeScript.TEXT_PRIMARY if count > 0 else UiThemeScript.TEXT_MUTED
	count_label.add_theme_color_override("font_color", count_color)
	vbox.add_child(count_label)
	return card


func _build_shop_item_card(item: Dictionary) -> Control:
	var card := _make_card_container()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UiThemeScript.SEPARATION_DENSE)
	card.add_child(vbox)

	vbox.add_child(_make_icon_block(str(item.get("icon", ""))))

	var name_label := Label.new()
	name_label.text = str(item.get("label", ""))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_BODY)
	vbox.add_child(name_label)

	var price := int(item.get("price", 0))
	var price_label := Label.new()
	price_label.text = "%d EUR" % price
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.add_theme_color_override("font_color", UiThemeScript.TEXT_SECONDARY)
	price_label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_SMALL)
	vbox.add_child(price_label)

	var info_label := Label.new()
	var stock := int(item.get("stock", -1))
	var owned := int(item.get("owned", 0))
	var info_parts: PackedStringArray = []
	if stock >= 0:
		info_parts.append("Lager %d" % stock)
	info_parts.append("Du: %d" % owned)
	info_label.text = "  ·  ".join(info_parts)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_color_override("font_color", UiThemeScript.TEXT_MUTED)
	info_label.add_theme_font_size_override("font_size", UiThemeScript.FONT_SIZE_SMALL)
	vbox.add_child(info_label)

	var action_id := str(item.get("action_id", ""))
	if not action_id.is_empty():
		var buy_btn := Button.new()
		buy_btn.text = str(item.get("button_text", "Kaufen"))
		buy_btn.disabled = not bool(item.get("enabled", true))
		buy_btn.tooltip_text = str(item.get("tooltip", ""))
		buy_btn.focus_mode = Control.FOCUS_NONE
		buy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buy_btn.gui_input.connect(_on_inventory_gui_input)
		buy_btn.pressed.connect(_on_action_button_pressed.bind(action_id))
		vbox.add_child(buy_btn)
	return card


func _make_card_container() -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(150, 160)
	var box := StyleBoxFlat.new()
	box.bg_color = UiThemeScript.BG_800
	box.border_color = UiThemeScript.BORDER
	box.border_width_left = UiThemeScript.BORDER_WIDTH
	box.border_width_top = UiThemeScript.BORDER_WIDTH
	box.border_width_right = UiThemeScript.BORDER_WIDTH
	box.border_width_bottom = UiThemeScript.BORDER_WIDTH
	box.corner_radius_top_left = UiThemeScript.RADIUS_PANEL
	box.corner_radius_top_right = UiThemeScript.RADIUS_PANEL
	box.corner_radius_bottom_left = UiThemeScript.RADIUS_PANEL
	box.corner_radius_bottom_right = UiThemeScript.RADIUS_PANEL
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", box)
	return card


# Square icon "tile" — placeholder visuals until real textures replace it.
# A colored rect with the catalog glyph (emoji or letters) centered on top.
func _make_icon_block(glyph: String) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(96, 72)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bg := ColorRect.new()
	bg.color = UiThemeScript.BG_700
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(bg)

	var glyph_label := Label.new()
	glyph_label.text = glyph
	glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	glyph_label.add_theme_font_size_override("font_size", 36)
	holder.add_child(glyph_label)
	return holder


func _clear_item_grid() -> void:
	for child in _item_grid.get_children():
		child.queue_free()


func _on_tab_pressed(category_id: String) -> void:
	ui_interacted.emit()
	_current_category = category_id
	_apply_tab_active_state(category_id)
	_render_category_items(_last_categories, category_id)


func _on_action_button_pressed(action_id: String) -> void:
	ui_interacted.emit()
	action_pressed.emit(action_id)


func _on_dim_background_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		ui_interacted.emit()
		_emit_close()


func _on_inventory_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		ui_interacted.emit()


func _emit_close() -> void:
	hide_window()
	closed.emit()
