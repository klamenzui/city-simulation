extends RefCounted
class_name MultiplayerLaunchOptions

const NetworkRoleScript = preload("res://Simulation/Multiplayer/shared/NetworkRole.gd")

const DEFAULT_ADDRESS := "127.0.0.1"
const DEFAULT_PORT := 24567
const DEFAULT_MAX_CLIENTS := 3

static func from_command_line() -> Dictionary:
	return from_args(OS.get_cmdline_user_args())

static func from_args(args: PackedStringArray) -> Dictionary:
	var options := {
		"role": NetworkRoleScript.OFFLINE,
		"address": DEFAULT_ADDRESS,
		"port": DEFAULT_PORT,
		"max_clients": DEFAULT_MAX_CLIENTS,
	}

	var index := 0
	while index < args.size():
		var arg := str(args[index])
		match arg:
			"--mp-host", "--host":
				options["role"] = NetworkRoleScript.HOST
			"--mp-client", "--join":
				options["role"] = NetworkRoleScript.CLIENT
			"--mp-address", "--address", "--ip":
				if index + 1 < args.size():
					index += 1
					options["address"] = str(args[index]).strip_edges()
			"--mp-port", "--port":
				if index + 1 < args.size():
					index += 1
					options["port"] = _parse_port(str(args[index]), DEFAULT_PORT)
			"--mp-max-clients", "--max-clients":
				if index + 1 < args.size():
					index += 1
					options["max_clients"] = maxi(int(str(args[index])), 1)
			_:
				if arg.begins_with("--mp-address=") or arg.begins_with("--address=") or arg.begins_with("--ip="):
					options["address"] = _value_after_equals(arg).strip_edges()
				elif arg.begins_with("--mp-port=") or arg.begins_with("--port="):
					options["port"] = _parse_port(_value_after_equals(arg), DEFAULT_PORT)
				elif arg.begins_with("--mp-max-clients=") or arg.begins_with("--max-clients="):
					options["max_clients"] = maxi(int(_value_after_equals(arg)), 1)
		index += 1

	options["role"] = NetworkRoleScript.normalize(str(options["role"]))
	options["port"] = _parse_port(str(options["port"]), DEFAULT_PORT)
	options["max_clients"] = clampi(int(options["max_clients"]), 1, 32)
	if str(options["address"]).strip_edges().is_empty():
		options["address"] = DEFAULT_ADDRESS
	return options

static func _value_after_equals(arg: String) -> String:
	var eq := arg.find("=")
	if eq < 0:
		return ""
	return arg.substr(eq + 1)

static func _parse_port(raw_value: String, fallback: int) -> int:
	if not raw_value.is_valid_int():
		return fallback
	return clampi(int(raw_value), 1024, 65535)
