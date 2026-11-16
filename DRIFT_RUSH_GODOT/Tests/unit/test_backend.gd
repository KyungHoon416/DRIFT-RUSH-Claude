extends TestCase
## Mock backend room rules (mirrors Backend/functions/lib/rooms.js) and the
## Firebase REST request builders (no network).


func _mock() -> MockBackend:
	var m := MockBackend.new()
	m.latency_sec = 0.0
	spawn(m)
	return m


func test_guest_sign_in_and_nickname() -> void:
	var m := _mock()
	var r: Dictionary = await m.sign_in_guest()
	check(r["ok"], "guest sign-in")
	check(String(r["user"]["uid"]).begins_with("mock_"), "mock uid")
	eq((await m.set_nickname("A"))["error"], "INVALID_NICKNAME", "nickname too short")
	check((await m.set_nickname("Racer"))["ok"], "valid nickname")
	m.fail_next = "NETWORK"
	eq((await m.sign_in_guest())["error"], "NETWORK", "simulated network failure")


func test_room_codes_and_errors() -> void:
	var host := _mock()
	await host.sign_in_guest()
	var c: Dictionary = await host.create_room({"capacity": 2, "public": false})
	check(c["ok"], "room created")
	var code: String = c["code"]
	check(MockBackend.is_valid_code(code), "6-char unambiguous code (%s)" % code)
	eq((await host.create_room({}))["error"], "ALREADY_IN_ROOM", "duplicate room creation blocked")
	var guest := _mock()
	await guest.sign_in_guest()
	guest.rooms = host.rooms   # same "server"
	eq((await guest.join_room("abc"))["error"], "INVALID_CODE", "malformed code")
	eq((await guest.join_room("ZZZZZZ"))["error"], "ROOM_NOT_FOUND", "unknown code")
	check((await guest.join_room(code.to_lower()))["ok"], "join (case-insensitive)")
	eq((await guest.join_room(code))["error"], "ALREADY_IN_ROOM", "double join blocked")
	var third := _mock()
	await third.sign_in_guest()
	third.rooms = host.rooms
	eq((await third.join_room(code))["error"], "ROOM_FULL", "capacity enforced")
	host.rooms[code]["started"] = true
	host.rooms[code]["capacity"] = 8
	eq((await third.join_room(code))["error"], "RACE_STARTED", "cannot join a started race")
	await host.leave_room()
	eq(host.rooms[code]["host"], guest.user["uid"], "host migrates when host leaves")


func test_firebase_request_builders() -> void:
	var fb := FirebaseAdapter.new()
	fb.configure({"apiKey": "TEST_KEY", "projectId": "demo-proj", "functionsRegion": "asia-northeast3"})
	var s := fb.build_signup_request()
	check(String(s["url"]).begins_with("https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=TEST_KEY"), "anonymous sign-up endpoint")
	eq(JSON.parse_string(s["body"])["returnSecureToken"], true, "returnSecureToken")
	fb.id_token = "ID"
	var c := fb.build_callable("joinRoom", {"code": "ABCDEF"})
	eq(c["url"], "https://asia-northeast3-demo-proj.cloudfunctions.net/joinRoom", "callable URL")
	check((c["headers"] as Array).has("Authorization: Bearer ID"), "ID token sent as bearer")
	eq(JSON.parse_string(c["body"])["data"]["code"], "ABCDEF", "callable data envelope")
	var p := fb.build_profile_patch("uid1", "Nick")
	check(String(p["url"]).contains("/documents/users/uid1?updateMask.fieldPaths=nickname"), "profile patch only nickname")
	eq(fb.submit_race_result({})["error"], "SERVER_ONLY", "clients cannot write results")
	fb.free()


func test_backend_uses_mock_without_config() -> void:
	eq(Backend.mode, "mock", "no firebase_config.json → mock (never claims real connection)")
