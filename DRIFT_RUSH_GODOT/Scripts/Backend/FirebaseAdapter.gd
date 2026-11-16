class_name FirebaseAdapter
extends Node
## Firebase over official REST endpoints (no Unity SDK, no unofficial plugin).
##   Auth:      Identity Toolkit REST (anonymous sign-up, token refresh)
##   Firestore: REST v1 (own profile document)
##   Rooms:     Cloud Functions callable over HTTPS (Backend/functions)
## Config: res://Config/firebase_config.json or user://firebase_config.json
##   {"apiKey": "...", "projectId": "...", "functionsRegion": "asia-northeast3"}
## The web API key is a public identifier, NOT a secret; never ship service
## account keys. Status: code paths written, NOT tested against a live project.

const CONFIG_PATHS := ["user://firebase_config.json", "res://Config/firebase_config.json"]
const SESSION := "user://firebase_session.cfg"

var config: Dictionary = {}
var user: Dictionary = {}
var id_token := ""
var refresh_token := ""
var token_expiry_unix := 0.0


static func load_config() -> Dictionary:
	for p in CONFIG_PATHS:
		if FileAccess.file_exists(p):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
			if parsed is Dictionary and String(parsed.get("apiKey", "")) != "" and String(parsed.get("projectId", "")) != "":
				return parsed
	return {}


func backend_name() -> String:
	return "firebase"


func configure(cfg: Dictionary) -> void:
	config = cfg


# ----------------------------------------------------------- request builders
func build_signup_request() -> Dictionary:
	return {"url": "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=%s" % config.get("apiKey", ""),
		"method": HTTPClient.METHOD_POST, "headers": ["Content-Type: application/json"],
		"body": JSON.stringify({"returnSecureToken": true})}


func build_refresh_request(token: String) -> Dictionary:
	return {"url": "https://securetoken.googleapis.com/v1/token?key=%s" % config.get("apiKey", ""),
		"method": HTTPClient.METHOD_POST, "headers": ["Content-Type: application/x-www-form-urlencoded"],
		"body": "grant_type=refresh_token&refresh_token=%s" % token.uri_encode()}


func build_profile_patch(uid: String, nickname: String) -> Dictionary:
	var url := "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents/users/%s?updateMask.fieldPaths=nickname" % [config.get("projectId", ""), uid]
	return {"url": url, "method": HTTPClient.METHOD_PATCH,
		"headers": ["Content-Type: application/json", "Authorization: Bearer %s" % id_token],
		"body": JSON.stringify({"fields": {"nickname": {"stringValue": nickname}}})}


func build_callable(fn_name: String, data: Dictionary) -> Dictionary:
	var region := String(config.get("functionsRegion", "asia-northeast3"))
	return {"url": "https://%s-%s.cloudfunctions.net/%s" % [region, config.get("projectId", ""), fn_name],
		"method": HTTPClient.METHOD_POST,
		"headers": ["Content-Type: application/json", "Authorization: Bearer %s" % id_token],
		"body": JSON.stringify({"data": data})}


# ----------------------------------------------------------- transport
func _send(req: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	var err := http.request(req["url"], PackedStringArray(req["headers"]), req["method"], req["body"])
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "NETWORK", "detail": err}
	var res: Array = await http.request_completed
	http.queue_free()
	var result: int = res[0]
	var code: int = res[1]
	var body: PackedByteArray = res[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "NETWORK", "detail": result}
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if code >= 400:
		var msg := "HTTP_%d" % code
		if parsed is Dictionary and parsed.has("error"):
			var e: Variant = parsed["error"]
			msg = String(e.get("message", e.get("status", msg))) if e is Dictionary else String(e)
		return {"ok": false, "error": msg, "http": code}
	return {"ok": true, "data": parsed if parsed is Dictionary else {}}


func _ensure_token() -> bool:
	if id_token != "" and Time.get_unix_time_from_system() < token_expiry_unix - 60.0:
		return true
	if refresh_token == "":
		return false
	var r := await _send(build_refresh_request(refresh_token))
	if not r["ok"]:
		return false
	var d: Dictionary = r["data"]
	id_token = String(d.get("id_token", ""))
	refresh_token = String(d.get("refresh_token", refresh_token))
	token_expiry_unix = Time.get_unix_time_from_system() + float(d.get("expires_in", "3600"))
	_save_session()
	return id_token != ""


func _save_session() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "refresh_token", refresh_token)
	cfg.set_value("auth", "uid", user.get("uid", ""))
	cfg.save(SESSION)


# ----------------------------------------------------------- public API
func restore_session() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(SESSION) != OK:
		return {"ok": false, "error": "NO_SESSION"}
	refresh_token = String(cfg.get_value("auth", "refresh_token", ""))
	user = {"uid": cfg.get_value("auth", "uid", ""), "anonymous": true, "provider": "anonymous", "nickname": ""}
	if not await _ensure_token():
		return {"ok": false, "error": "SESSION_EXPIRED"}
	return {"ok": true, "user": user}


func sign_in_guest() -> Dictionary:
	var r := await _send(build_signup_request())
	if not r["ok"]:
		return r
	var d: Dictionary = r["data"]
	id_token = String(d.get("idToken", ""))
	refresh_token = String(d.get("refreshToken", ""))
	token_expiry_unix = Time.get_unix_time_from_system() + float(d.get("expiresIn", "3600"))
	user = {"uid": d.get("localId", ""), "anonymous": true, "provider": "anonymous", "nickname": ""}
	_save_session()
	return {"ok": true, "user": user}


func sign_out() -> void:
	id_token = ""
	refresh_token = ""
	user = {}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION))


func set_nickname(n: String) -> Dictionary:
	if not await _ensure_token():
		return {"ok": false, "error": "UNAUTHENTICATED"}
	var r := await _send(build_profile_patch(String(user.get("uid")), n))
	if r["ok"]:
		user["nickname"] = n
	return r


func _call(fn_name: String, data: Dictionary) -> Dictionary:
	if not await _ensure_token():
		return {"ok": false, "error": "UNAUTHENTICATED"}
	var r := await _send(build_callable(fn_name, data))
	if not r["ok"]:
		return r
	var result: Variant = r["data"].get("result", {})
	if result is Dictionary:
		var out: Dictionary = result.duplicate()
		out["ok"] = true
		return out
	return {"ok": true, "result": result}


func create_room(opts: Dictionary) -> Dictionary:
	return await _call("createRoom", opts)


func join_room(code: String) -> Dictionary:
	return await _call("joinRoom", {"code": code.strip_edges().to_upper()})


func leave_room() -> Dictionary:
	return await _call("leaveRoom", {})


func set_ready(ready: bool) -> Dictionary:
	return await _call("setReady", {"ready": ready})


## Clients never write results. The dedicated game server reports them via a
## server-only function (see Backend/functions/index.js: reportRaceResult).
func submit_race_result(_result: Dictionary) -> Dictionary:
	return {"ok": false, "error": "SERVER_ONLY", "verified": false}


func get_friends() -> Dictionary:
	return await _call("listFriends", {})
