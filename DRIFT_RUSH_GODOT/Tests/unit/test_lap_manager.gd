extends TestCase


func test_lap_counting_requires_order() -> void:
	var lm := LapManager.new(6, 2)
	eq(lm.on_checkpoint(0, 0.5), "start", "first line crossing arms lap 1")
	eq(lm.current_lap(), 1, "lap 1")
	eq(lm.on_checkpoint(3, 2.0), "ignored", "skipping checkpoints is ignored")
	for i in range(1, 6):
		eq(lm.on_checkpoint(i, 2.0 + i), "checkpoint", "cp %d" % i)
	eq(lm.on_checkpoint(0, 30.0), "lap", "lap complete")
	near(lm.lap_times[0], 30.0, 0.001, "lap time from race start")
	eq(lm.current_lap(), 2, "lap 2")
	eq(lm.on_checkpoint(0, 31.0), "ignored", "re-crossing the line without a lap is ignored")
	for i in range(1, 6):
		lm.on_checkpoint(i, 40.0 + i)
	eq(lm.on_checkpoint(0, 55.0), "finish", "finish after last lap")
	check(lm.finished, "finished flag")
	near(lm.best_lap, 25.0, 0.001, "best lap")


func test_min_lap_time_rejects_cheats() -> void:
	var lm := LapManager.new(4, 3)
	lm.min_lap_time = 20.0
	lm.on_checkpoint(0, 0.1)
	for i in range(1, 4):
		lm.on_checkpoint(i, 1.0 + i)
	eq(lm.on_checkpoint(0, 5.0), "invalid", "impossibly short lap rejected")
	eq(lm.laps_done, 0, "no lap counted")


func test_progress_wraps_around_start_line() -> void:
	var lm := LapManager.new(4, 3)
	var L := 1000.0
	check(lm.progress(990.0, L) < 0.0, "behind the line on the grid = negative progress")
	lm.on_checkpoint(0, 0.0)
	check(lm.progress(999.0, L) < 5.0, "just after crossing, unwrapped offset handled")
	lm.on_checkpoint(1, 1.0)
	lm.on_checkpoint(2, 2.0)
	lm.on_checkpoint(3, 3.0)
	check(lm.progress(5.0, L) > 990.0, "approaching the line from last sector counts as end of lap")
