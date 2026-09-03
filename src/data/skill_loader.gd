class_name SkillLoader
extends RefCounted

# ============================================================
# 加载 res://src/data/skills/*.tsv → skill_db: Dictionary(id -> 技能字典)
#
# 格式约定：
#   - tab 分隔；首行表头；"#" 开头为注释行；空行跳过
#   - effects / augment_effects 列写成 "key=value;key2=value2"
#   - tags 列写成 "a,b,c"
#
# 新增技能 = 在对应 tsv 加一行，无需改任何代码。
# ============================================================

const SkillSchema = preload("res://src/data/skill_schema.gd")
const SKILL_DIR := "res://src/data/skills/"

static var _db: Dictionary = {}
static var _loaded := false

static func get_all_skills() -> Dictionary:
	_ensure_loaded()
	return _db

static func get_skill(id: String) -> Dictionary:
	_ensure_loaded()
	return _db.get(id, {})

static func get_skill_ids() -> Array:
	_ensure_loaded()
	return _db.keys()

static func get_by_cast_mode(mode: String) -> Array:
	_ensure_loaded()
	var out: Array = []
	for id in _db.keys():
		if String(_db[id].get("cast_mode", "")) == mode:
			out.append(id)
	return out

static func get_by_subtype(subtype: String) -> Array:
	_ensure_loaded()
	var out: Array = []
	for id in _db.keys():
		if String(_db[id].get("subtype", "")) == subtype:
			out.append(id)
	return out

static func _ensure_loaded() -> void:
	if not _loaded:
		reload()

# 热重载：改完表在运行中调用即可生效
static func reload() -> void:
	_db = {}
	var files: Array = []
	var dir := DirAccess.open(SKILL_DIR)
	if dir == null:
		push_error("SkillLoader: cannot open %s" % SKILL_DIR)
		_loaded = true
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tsv"):
			files.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	files.sort()
	for fn in files:
		_load_file(SKILL_DIR + fn)
	_loaded = true
	print("[SkillLoader] loaded %d skills from %d tables" % [_db.size(), files.size()])

static func _load_file(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("SkillLoader: cannot open %s" % path)
		return
	var fileName := path.get_file()
	var header: PackedStringArray = []
	var lineNo := 0
	while not f.eof_reached():
		var line := f.get_line()
		lineNo += 1
		if line.begins_with("#") or line.strip_edges() == "":
			continue
		var parts := line.split("\t")
		if header.is_empty():
			header = parts
			if header.size() != SkillSchema.COLUMNS.size():
				push_error("SkillLoader: %s header has %d cols, expect %d" % [fileName, header.size(), SkillSchema.COLUMNS.size()])
			continue
		if parts.size() != header.size():
			push_error("SkillLoader: %s line %d has %d fields, expect %d (skipped)" % [fileName, lineNo, parts.size(), header.size()])
			continue
		var def := {}
		for i in header.size():
			def[header[i]] = _coerce(header[i], parts[i])
		_finalize(def, fileName)
		var errs := SkillSchema.validate(def)
		if not errs.is_empty():
			push_error("SkillLoader: %s (%s) -> %s" % [def.get("id", "?"), fileName, errs])
			continue
		if _db.has(def["id"]):
			push_error("SkillLoader: duplicated skill id '%s' in %s" % [def["id"], fileName])
			continue
		_db[def["id"]] = def
	f.close()

# 补齐缺省列 + 派生 legacy 字段
static func _finalize(def: Dictionary, source: String) -> void:
	for col in SkillSchema.COLUMNS:
		if not def.has(col):
			def[col] = SkillSchema.DEFAULTS.get(col, "")
	def["source"] = source
	def["subtype"] = SkillSchema.derive_subtype(def)
	def["target_mode"] = SkillSchema.derive_target_mode(def)
	var aug: Dictionary = def.get("augment_effects", {})
	if not aug.is_empty():
		def["augment"] = {"effects": aug}

static func _coerce(col: String, raw: String) -> Variant:
	raw = raw.strip_edges()
	var t := String(SkillSchema.COL_TYPES.get(col, "string"))
	match t:
		"bool":
			if raw == "":
				return bool(SkillSchema.DEFAULTS.get(col, false))
			return raw == "true" or raw == "1"
		"int":
			if raw == "":
				return int(SkillSchema.DEFAULTS.get(col, 0))
			return raw.to_int()
		"float":
			if raw == "":
				return float(SkillSchema.DEFAULTS.get(col, 0.0))
			return raw.to_float()
		"kv":
			return _parse_kv(raw)
		"list":
			if raw == "":
				return []
			var out: Array = []
			for t2 in raw.split(","):
				var s := t2.strip_edges()
				if s != "":
					out.append(s)
			return out
		_:
			if raw == "":
				return SkillSchema.DEFAULTS.get(col, "")
			return raw

static func _parse_kv(s: String) -> Dictionary:
	var out := {}
	if s == "":
		return out
	for pair in s.split(";"):
		var p := pair.strip_edges()
		if p == "":
			continue
		var kv := p.split("=", true, 1)
		if kv.size() < 2:
			continue
		out[kv[0].strip_edges()] = _kv_value(kv[1].strip_edges())
	return out

static func _kv_value(v: String) -> Variant:
	if v == "true":
		return true
	if v == "false":
		return false
	if v.is_valid_int():
		return v.to_int()
	if v.is_valid_float():
		return v.to_float()
	return v
