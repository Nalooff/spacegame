class_name NatHelper
extends Node
## Makes a home PC reachable from the internet, with no server involved:
##   1. asks the router (UPnP) to forward the game's UDP port to this PC,
##   2. finds the public IP (small HTTPS lookups, several services tried in turn; the router's own answer is the last fallback),
##   3. finds this PC's LAN address (so players on the SAME network, who cannot use the public address, can still connect).
## Everything is best effort; `message` says in plain words what worked, so the host can see why a friend cannot join.
##
## The port mapping is NOT deleted when the lobby closes: it is leased for LEASE seconds and renewed while hosting,
## so it just expires afterwards (deleting from the main thread blocks and often fails on home routers).

signal finished(ok: bool)
signal ip_found   # the public address is known: the lobby can be listed even while UPnP is still working

const LEASE := 1800

var public_ip: String = ""
## Our own public IP, kept after stop() (used by the browser to notice lobbies on our own network).
var own_ip: String = ""
var lan_ip: String = ""
var port_open: bool = false      # the router agreed to forward the port
var message: String = ""
var _port: int = 0
var _upnp_external: String = ""
var _thread: Thread
var _pending: int = 0
var _service_index: int = 0
var _renew_in: float = 0.0
var _hosting: bool = false
var _upnp_first: bool = false   # the first UPnP run counts as a step of open(); later runs are renewals


func open(port: int) -> void:
	_port = port
	_pending = 2
	_hosting = true
	public_ip = ""
	lan_ip = _find_lan_ip()
	_upnp_first = true
	message = "Opening port %d on your router..." % port
	_start_upnp()
	_service_index = 0
	_lookup_public_ip()


## For players who only JOIN: find our own public IP (to know if a lobby is on our own network).
func detect_own_ip() -> void:
	_pending = 1
	_service_index = 0
	_lookup_public_ip()


## Stop renewing (the router drops the mapping by itself after the lease).
func stop() -> void:
	_hosting = false
	port_open = false
	public_ip = ""


func _process(dt: float) -> void:
	if _hosting and port_open and _thread == null:
		_renew_in -= dt
		if _renew_in <= 0.0:
			_start_upnp()   # same call again = renew


# ----------------------------------------------------------------- UPnP (blocking calls -> worker thread)
func _start_upnp() -> void:
	if _thread != null:
		return
	_renew_in = LEASE * 0.5
	_thread = Thread.new()
	_thread.start(_run_upnp)


func _run_upnp() -> void:
	var u := UPNP.new()
	var ok := false
	var external := ""
	if u.discover(2000) == UPNP.UPNP_RESULT_SUCCESS and u.get_gateway() != null and u.get_gateway().is_valid_gateway():
		ok = u.add_port_mapping(_port, _port, "Vertex Ships", "UDP", LEASE) == UPNP.UPNP_RESULT_SUCCESS
		external = u.query_external_address()
	call_deferred("_upnp_done", ok, external)


func _upnp_done(ok: bool, external: String) -> void:
	_thread.wait_to_finish()
	_thread = null
	var first := _upnp_first
	_upnp_first = false
	port_open = ok
	_upnp_external = external
	if public_ip == "" and external.is_valid_ip_address() and not _is_private(external):
		public_ip = external
		ip_found.emit()
	_update_message()
	if first:
		_step_done()


# ----------------------------------------------------------------- public IP
func _lookup_public_ip() -> void:
	if _service_index >= Data.PUBLIC_IP_URLS.size():
		_step_done()
		return
	var req := HTTPRequest.new()
	req.name = "PublicIpLookup%d" % _service_index
	req.timeout = 6.0
	add_child(req)
	req.request_completed.connect(func(_r, code, _h, body: PackedByteArray):
		req.queue_free()
		var ip := body.get_string_from_utf8().strip_edges()
		if code == 200 and ip.is_valid_ip_address():
			public_ip = ip
			own_ip = ip
			_update_message()
			ip_found.emit()
			_step_done()
		else:
			_service_index += 1
			_lookup_public_ip())   # try the next service
	if req.request(Data.PUBLIC_IP_URLS[_service_index]) != OK:
		req.queue_free()
		_service_index += 1
		_lookup_public_ip()


## `finished` fires when both the UPnP attempt and the public IP lookup are done.
func _step_done() -> void:
	_pending -= 1
	if _pending == 0:
		if _hosting:
			_update_message()
		finished.emit(port_open)


func _update_message() -> void:
	var parts: Array[String] = []
	parts.append("UPnP: port %d opened on your router." % _port if port_open else
		"UPnP: your router did not open port %d automatically - forward UDP port %d to this PC in the router settings." % [_port, _port])
	if public_ip == "":
		parts.append("Public IP: not found (no internet?), so the lobby is only listed on your local network.")
	else:
		parts.append("Public address: %s:%d" % [public_ip, _port])
		if _is_private(_upnp_external) and _upnp_external != "":
			parts.append("Your router reports a private address (%s): your provider shares one address between customers (CGNAT), so players outside your network cannot reach you." % _upnp_external)
	message = "\n".join(parts)


# ----------------------------------------------------------------- helpers
func _find_lan_ip() -> String:
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and _is_private(a) and not a.begins_with("169.254.") and not a.begins_with("127."):
			return a
	return ""


static func _is_private(ip: String) -> bool:
	if ip.begins_with("10.") or ip.begins_with("192.168.") or ip.begins_with("169.254."):
		return true
	if ip.begins_with("172."):
		var second := int(ip.split(".")[1])
		return second >= 16 and second <= 31
	return ip.begins_with("100.") and int(ip.split(".")[1]) >= 64 and int(ip.split(".")[1]) <= 127   # CGNAT range
