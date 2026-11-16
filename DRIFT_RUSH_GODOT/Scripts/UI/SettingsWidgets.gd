class_name SettingsWidgets
extends RefCounted
## Rows bound directly to SaveSettings keys (change → live apply + save).


static func slider_row(label_text: String, key: String, mn: float, mx: float, step: float) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := UITheme.label(label_text, 19, UITheme.TEXT, true)
	l.custom_minimum_size = Vector2(130, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.name = "Slider_" + key
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = float(SaveSettings.get_value(key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	var v := UITheme.label("%.2f" % s.value, 18, UITheme.CYAN, true)
	v.custom_minimum_size = Vector2(60, 0)
	h.add_child(v)
	s.value_changed.connect(func(val: float):
		v.text = "%.2f" % val
		SaveSettings.set_value(key, val))
	return h


static func check_row(label_text: String, key: String) -> CheckButton:
	var c := CheckButton.new()
	c.name = "Check_" + key
	c.text = label_text
	c.add_theme_font_size_override("font_size", 20)
	c.button_pressed = bool(SaveSettings.get_value(key))
	c.toggled.connect(func(on: bool): SaveSettings.set_value(key, on))
	return c


static func option_row(label_text: String, key: String, values: Array, labels: Array = []) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := UITheme.label(label_text, 19, UITheme.TEXT, true)
	l.custom_minimum_size = Vector2(130, 0)
	h.add_child(l)
	var o := OptionButton.new()
	o.name = "Option_" + key
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cur: Variant = SaveSettings.get_value(key)
	for i in values.size():
		o.add_item(str(labels[i]) if i < labels.size() else str(values[i]))
		if str(values[i]) == str(cur):
			o.select(i)
	o.item_selected.connect(func(i: int):
		var val: Variant = values[i]
		SaveSettings.set_value(key, val))
	h.add_child(o)
	return h
