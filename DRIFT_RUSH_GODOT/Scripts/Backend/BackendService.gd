extends Node
## Facade over the account/room backend. Autoload name: Backend.
## Uses FirebaseAdapter when a valid Config/firebase_config.json exists,
## otherwise MockBackend. `Backend.mode` tells the UI which one is active so it
## never claims a real connection when running on the mock.

signal session_changed(user: Dictionary)

var impl: Node
var mode := "mock"
var user: Dictionary = {}
var offline_practice := false


func _ready() -> void:
	var cfg := FirebaseAdapter.load_config()
	if not cfg.is_empty():
		var fb := FirebaseAdapter.new()
		fb.configure(cfg)
		impl = fb
		mode = "firebase"
	else:
		impl = MockBackend.new()
		mode = "mock"
	impl.name = "Impl"
	add_child(impl)


func is_signed_in() -> bool:
	return not user.is_empty()


func restore_session() -> Dictionary:
	var r: Dictionary = await impl.restore_session()
	if r.get("ok", false):
		_set_user(r["user"])
	return r


func sign_in_guest() -> Dictionary:
	var r: Dictionary = await impl.sign_in_guest()
	if r.get("ok", false):
		_set_user(r["user"])
	return r


func start_offline() -> void:
	offline_practice = true
	_set_user({"uid": "offline", "nickname": SaveSettings.get_value("nickname"), "anonymous": true, "provider": "offline"})


func sign_out() -> void:
	impl.sign_out()
	user = {}
	session_changed.emit(user)


func set_nickname(n: String) -> Dictionary:
	SaveSettings.set_value("nickname", n.strip_edges().substr(0, 12))
	if offline_practice:
		return {"ok": true}
	var r: Dictionary = await impl.set_nickname(n)
	if r.get("ok", false):
		user["nickname"] = n
	return r


func create_room(opts: Dictionary) -> Dictionary:
	return await impl.create_room(opts)


func join_room(code: String) -> Dictionary:
	return await impl.join_room(code)


func leave_room() -> Dictionary:
	return await impl.leave_room()


func set_ready(r: bool) -> Dictionary:
	return await impl.set_ready(r)


func submit_race_result(result: Dictionary) -> Dictionary:
	return impl.submit_race_result(result)


func get_friends() -> Dictionary:
	return await impl.get_friends()


func _set_user(u: Dictionary) -> void:
	user = u
	session_changed.emit(user)


static func error_text(code: String) -> String:
	return {
		"NETWORK": "네트워크 연결을 확인해 주세요.",
		"NO_SESSION": "저장된 로그인 정보가 없습니다.",
		"SESSION_EXPIRED": "로그인이 만료되었습니다. 다시 시작해 주세요.",
		"UNAUTHENTICATED": "로그인이 필요합니다.",
		"INVALID_CODE": "초대 코드는 6자리(영문/숫자)입니다.",
		"ROOM_NOT_FOUND": "존재하지 않는 방 코드입니다.",
		"ROOM_FULL": "방 인원이 가득 찼습니다.",
		"RACE_STARTED": "이미 경기가 시작된 방입니다.",
		"ALREADY_IN_ROOM": "이미 방에 참가 중입니다.",
		"INVALID_NICKNAME": "닉네임은 2~12자로 입력해 주세요.",
		"SERVER_ONLY": "기록은 게임 서버만 저장할 수 있습니다.",
	}.get(code, "오류가 발생했습니다 (%s)" % code)
