## Read a JSON file into a Dictionary — one place for the open/parse/validate dance
## that every data loader (Rules, WordBank, Lexicon, IconBank, the CLI save) shared.
class_name JsonFile
extends RefCounted


## The file parsed as a Dictionary, or {} if it's missing, unreadable, or not a
## JSON object. Callers that require the file warn on an empty result.
static func load_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
