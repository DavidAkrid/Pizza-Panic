class_name SaveGame
## The host's town on disk, plus this PC's player name. Only the host ever reads or writes the
## town; friends' stuff lives in the host's save, by name (see GameState.snapshot/restore).
##
## Town file: {"version", "night", "money", "players": {name: {"upgrades": {...}, "items": [...]}}}
## Stored with store_var so ints stay ints.

const VERSION := 1


## Dev tests (`-- --test=...`) use their own files so they never touch a real save.
static func _path(file: String) -> String:
	var testing := false
	for a in OS.get_cmdline_user_args():
		testing = testing or a.begins_with("--test=")
	return "user://" + ("test_" if testing else "") + file


static func town_path() -> String:
	return _path("town.save")


## Start over: the next save writes a brand new town.
static func delete_town() -> void:
	if has_town():
		DirAccess.remove_absolute(town_path())


static func has_town() -> bool:
	return FileAccess.file_exists(town_path())


## The saved town, or {} if there isn't one (or it's unreadable).
static func load_town() -> Dictionary:
	if not has_town():
		return {}
	var f := FileAccess.open(town_path(), FileAccess.READ)
	if f == null:
		return {}
	var data = f.get_var()
	if not data is Dictionary or data.get("version", 0) != VERSION:
		return {}
	return data


static func save_town(data: Dictionary) -> bool:
	data["version"] = VERSION
	var f := FileAccess.open(town_path(), FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(data)
	return true


## One line for the menu: "Night 3 - $240", or "" with no save.
static func summary() -> String:
	var data := load_town()
	if data.is_empty():
		return ""
	return "Night %d - $%d" % [data.get("night", 1), data.get("money", 0)]


# --- This PC's player name ------------------------------------------------------------

static func player_name() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(_path("settings.cfg")) != OK:
		return ""
	return str(cfg.get_value("player", "name", ""))


static func set_player_name(value: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(_path("settings.cfg")) # fine if it doesn't exist yet
	cfg.set_value("player", "name", value)
	cfg.save(_path("settings.cfg"))


## Names are how the host recognizes you, so keep them short and plain.
static func clean_name(value: String) -> String:
	var s := value.strip_edges().replace("\n", " ")
	return s.substr(0, 16)
