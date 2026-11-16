extends Node
## Runs all Tests/unit/test_*.gd suites inside the real project (autoloads on).
## Usage (deterministic, faster than real time):
##   godot --headless --fixed-fps 60 --path . res://Tests/TestRunner.tscn
##   optional:  -- --suite=test_track  (run one suite)
## Exit code = number of failed checks. Writes Tests/output/test_results.json.

func _ready() -> void:
	GameFlow.test_mode = true
	SaveSettings.path = "user://test_settings.cfg"
	SaveSettings.reset_to_defaults()
	SaveSettings.set_value("graphics_quality", "low", false)
	_run.call_deferred()


func _run() -> void:
	var only: String = GameFlow.cmdline.get("suite", "")
	var dir := DirAccess.open("res://Tests/unit")
	var files := Array(dir.get_files()).filter(func(f: String): return f.begins_with("test_") and f.ends_with(".gd"))
	files.sort()
	var total_fail := 0
	var total_checks := 0
	var report := []
	var t0 := Time.get_ticks_msec()
	for f in files:
		if only != "" and not f.begins_with(only):
			continue
		var script: GDScript = load("res://Tests/unit/" + f)
		var suite: TestCase = script.new()
		suite.runner = self
		var methods: Array = []
		for m in script.get_script_method_list():
			var mn: String = m["name"]
			if mn.begins_with("test_") and not methods.has(mn):
				methods.append(mn)
		for mn in methods:
			suite.current = "%s.%s" % [f.get_basename(), mn]
			var before := suite.failures.size()
			var st := Time.get_ticks_msec()
			suite.before_each()
			await suite.call(mn)
			suite.cleanup()
			await get_tree().process_frame
			var ok := suite.failures.size() == before
			var line := "%s %s (%d ms)" % ["PASS" if ok else "FAIL", suite.current, Time.get_ticks_msec() - st]
			print(line)
			for i in range(before, suite.failures.size()):
				print("    ✗ ", suite.failures[i])
			report.append({"test": suite.current, "ok": ok, "failures": suite.failures.slice(before)})
		total_fail += suite.failures.size()
		total_checks += suite.checks
	var summary := "TESTS DONE: %d tests, %d checks, %d failures, %.1f s" % [report.size(), total_checks, total_fail, (Time.get_ticks_msec() - t0) / 1000.0]
	print(summary)
	var out_dir := ProjectSettings.globalize_path("res://Tests/output")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var fh := FileAccess.open(out_dir.path_join("test_results.json"), FileAccess.WRITE)
	if fh:
		fh.store_string(JSON.stringify({"summary": summary, "tests": report}, "  "))
	get_tree().quit(mini(total_fail, 125))
