extends Node
## Autoload: keeps one copy of the game running.
##
## The first copy listens on a local-only TCP port. A second copy finds the
## port taken, checks with a short handshake that the owner really is this
## game, asks it to come to the front, and quits. The port is released by
## the OS even if the game crashes, so a stale lock cannot block the next
## start. If some other program owns the port, the game runs anyway rather
## than refusing to start.
##
## Command line: --allow-multiple skips the check (development previews);
## --instance-port N uses another port (testing).

signal show_requested

const DEFAULT_PORT := 47817
const HELLO := "caramelo-hello"
const REPLY := "caramelo-here"
const HANDSHAKE_MS := 1500

var port := DEFAULT_PORT
var _server: TCPServer
var _clients: Array[StreamPeerTCP] = []


func _ready() -> void:
	show_requested.connect(func() -> void:
		print("SingleInstance: another copy tried to start; showing this one instead")
		bring_to_front())


## Returns true when this copy may run: nobody else holds the port, or the
## port belongs to some other program. Returns false when another copy of
## the game is already running; it has been asked to show itself.
func claim(argv: PackedStringArray = OS.get_cmdline_user_args()) -> bool:
	if argv.has("--allow-multiple"):
		return true
	var i := argv.find("--instance-port")
	if i >= 0 and i + 1 < argv.size() and argv[i + 1].is_valid_int():
		port = int(argv[i + 1])
	_server = TCPServer.new()
	if _server.listen(port, "127.0.0.1") == OK:
		return true
	_server = null
	if ask_existing_to_show(port):
		return false
	push_warning("SingleInstance: port %d is used by another program; running without the check" % port)
	return true


## True if a copy of this game answered on the port (and was asked to show).
static func ask_existing_to_show(on_port: int) -> bool:
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", on_port) != OK:
		return false
	var deadline := Time.get_ticks_msec() + HANDSHAKE_MS
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < deadline:
		peer.poll()
		OS.delay_msec(10)
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false
	peer.put_data((HELLO + "\n").to_utf8_buffer())
	var reply := ""
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		var available := peer.get_available_bytes()
		if available > 0:
			reply += peer.get_utf8_string(available)
			if reply.contains("\n"):
				break
		OS.delay_msec(10)
	peer.disconnect_from_host()
	return reply.strip_edges() == REPLY


func _process(_delta: float) -> void:
	poll()


## Answers copies that start up while this one runs. Called every frame.
func poll() -> void:
	if _server == null:
		return
	while _server.is_connection_available():
		_clients.append(_server.take_connection())
	for client: StreamPeerTCP in _clients.duplicate():
		client.poll()
		if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.erase(client)
			continue
		var available := client.get_available_bytes()
		if available <= 0:
			continue
		if client.get_utf8_string(available).strip_edges() == HELLO:
			client.put_data((REPLY + "\n").to_utf8_buffer())
			show_requested.emit()
		client.disconnect_from_host()
		_clients.erase(client)


func release() -> void:
	if _server != null:
		_server.stop()
		_server = null


## Brings this game's window to the front (another copy tried to start).
static func bring_to_front() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_move_to_foreground()
