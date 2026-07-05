## Fetches styled art (enemy portraits + boon icons) from the local art daemon and
## hands back textures.
##
## Async (HTTPRequest), caches textures by request URL so repeats are instant, and
## can prefetch (the next chapter's portrait, the run's boon icons) ahead of need.
##
## Also owns the daemon's lifecycle for convenience:
##  - polls /health every few seconds and emits `daemon_status_changed`,
##  - launches the daemon itself (via art/.venv) if it's down, and kills that
##    instance on exit (only the one we started).
## If the daemon is unreachable, portrait requests fail quietly and the caller
## keeps its emoji fallback.
class_name Art
extends Node

const HOST := "127.0.0.1"
const PORT := 7770
const BASE := "http://127.0.0.1:7770"
const HEALTH_URL := "http://127.0.0.1:7770/health"
const _HEALTH_EVERY := 3.0        # seconds between health pings
const _RELAUNCH_COOLDOWN := 8000  # ms; don't spam launches

signal daemon_status_changed(online: bool)

var _ready_tex: Dictionary = {}   # key -> ImageTexture
var _waiting: Dictionary = {}     # key -> Array[Callable]
var _online := false
var _health: HTTPRequest
var _health_busy := false
var _launched_pid := -1
var _last_launch_ms := -100000


func _ready() -> void:
	_health = HTTPRequest.new()
	add_child(_health)
	_health.request_completed.connect(_on_health)
	var timer := Timer.new()
	timer.wait_time = _HEALTH_EVERY
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(_check_health)
	_check_health()  # don't wait for the first tick


func is_online() -> bool:
	return _online


# --- image requests ----------------------------------------------------------
# One call for every kind of art: creature / weapon / boon / tombstone. `subject`
# is the noun or id (e.g. "dragon", "axe", "tough"). `on_ready` gets an ImageTexture
# when available (synchronously if already cached); duplicate requests share a fetch.

func request(kind: String, subject: String, style: String, model: String, on_ready: Callable) -> void:
	_request(_image_url(kind, subject, style, model), on_ready)

## Warm an image we'll need soon (no callback).
func prefetch(kind: String, subject: String, style: String, model: String) -> void:
	_request(_image_url(kind, subject, style, model), Callable())


func _image_url(kind: String, subject: String, style: String, model: String) -> String:
	return _url("image", {"kind": kind, "subject": subject, "style": style, "model": model})


## Build "BASE/path?k=v&..." with every value URL-encoded.
func _url(path: String, params: Dictionary) -> String:
	var q: Array = []
	for k in params:
		q.append("%s=%s" % [k, str(params[k]).uri_encode()])
	return "%s/%s?%s" % [BASE, path, "&".join(q)]


## The URL is the cache key. A valid `on_ready` gets the texture (now if cached, or
## when it arrives); an invalid Callable means prefetch-only. Duplicate in-flight
## requests share one fetch.
func _request(url: String, on_ready: Callable) -> void:
	if _ready_tex.has(url):
		if on_ready.is_valid():
			on_ready.call(_ready_tex[url])
		return
	if _waiting.has(url):
		if on_ready.is_valid():
			_waiting[url].append(on_ready)
		return
	_waiting[url] = [on_ready] if on_ready.is_valid() else []
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(result, code, _headers, body): _on_image(url, http, result, code, body))
	if http.request(url) != OK:
		http.queue_free()
		_finish(url, null)


func _on_image(k: String, http: HTTPRequest, result: int, code: int, body: PackedByteArray) -> void:
	http.queue_free()
	var tex: ImageTexture = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and body.size() > 0:
		var img := Image.new()
		if img.load_png_from_buffer(body) == OK:
			img.generate_mipmaps()  # so consumers can downscale without aliasing
			tex = ImageTexture.create_from_image(img)
	_finish(k, tex)


func _finish(k: String, tex) -> void:
	var callbacks: Array = _waiting.get(k, [])
	_waiting.erase(k)
	if tex != null:
		_ready_tex[k] = tex
		for cb in callbacks:
			cb.call(tex)
	# On failure we drop it silently; the caller keeps its emoji fallback.


# --- daemon health + lifecycle -----------------------------------------------

func _check_health() -> void:
	if _health_busy:
		return
	_health_busy = true
	if _health.request(HEALTH_URL) != OK:
		_health_busy = false
		_set_online(false)


func _on_health(result: int, code: int, _headers, _body) -> void:
	_health_busy = false
	_set_online(result == HTTPRequest.RESULT_SUCCESS and code == 200)


func _set_online(up: bool) -> void:
	if up != _online:
		_online = up
		daemon_status_changed.emit(up)
	if not up:
		_maybe_launch()


## Launch the daemon ourselves if it's down (throttled), remembering the pid so we
## can clean it up on exit.
func _maybe_launch() -> void:
	if Time.get_ticks_msec() - _last_launch_ms < _RELAUNCH_COOLDOWN:
		return
	var py := _venv_python()
	if not FileAccess.file_exists(py):
		return  # no venv -> stay offline, callers use emoji
	_last_launch_ms = Time.get_ticks_msec()
	var pid := OS.create_process(py, ["-m", "wordplay_art.server", "--port", str(PORT)])
	if pid > 0:
		_launched_pid = pid


func _venv_python() -> String:
	var repo := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	return repo.path_join("art/.venv/bin/python")


func _exit_tree() -> void:
	if _launched_pid > 0:
		OS.kill(_launched_pid)  # only the instance we started
