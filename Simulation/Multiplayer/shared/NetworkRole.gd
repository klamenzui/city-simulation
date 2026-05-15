extends RefCounted
class_name NetworkRole

const OFFLINE := "offline"
const HOST := "host"
const CLIENT := "client"

static func is_server_authority(role: String) -> bool:
	return role == OFFLINE or role == HOST

static func is_network_client(role: String) -> bool:
	return role == CLIENT

static func normalize(role: String) -> String:
	match role:
		HOST:
			return HOST
		CLIENT:
			return CLIENT
		_:
			return OFFLINE
