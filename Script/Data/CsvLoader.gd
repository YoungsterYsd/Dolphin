## CSV 加载工具（运行时数据驱动配置）。
##
## 配套 Tools/excel2Config 工具的 CSV 输出格式：
## - 编码：UTF-8 with BOM
## - 表头行：[code]id, sub_id, <字段...>[/code]
## - 主行：sub_id 留空；子行：sub_id 填具体值
## - List 字面量：[code]{a,b,c}[/code]（用大括号包裹，逗号分隔，与 Excel 单元格写法一致）
## - 行尾：CRLF（标准 csv），但兼容 LF
##
## 设计要点：
## 1. **不引入字段类型元信息**：CSV 头里没类型，调用方自行用 [method as_float] / [method as_int] /
##    [method as_list_float] 等取值器从 row dict 取数。这样不必维护一份"字段→类型"映射，
##    解析器保持轻量。
## 2. **id 主键**：把多行聚合成 [code]Dictionary[int, RowDict][/code]，主键为 id 列的 int 值。
## 3. **sub_entries 按需聚合**：调用方传 [code]aggregate_subs=true[/code] 时，子行（sub_id 非空）
##    挂到主行的 [code]sub_entries: Array[Dictionary][/code] 上；否则平铺成多行。
## 4. **崩溃式失败**（R-CODE-01）：路径不存在 / 表头缺失 / id 列非法 → assert 崩。
##    单元格值非法（List 解析失败等）走 [method as_*] 取值器时再 fail-fast。
##
## 静态工具类，请勿 new。
class_name CsvLoader
extends RefCounted


# ─────────────────────────────────────────────────────────────
# 入口：加载整张 CSV 表
# ─────────────────────────────────────────────────────────────


## 加载一张 CSV 表 → [code]Dictionary[int, Dictionary][/code]，主键 = id 列。
##
## row dict 结构：
## [codeblock]
## {
##   "id": int,
##   "<field_a>": String,   # 原始字符串（取值时用 as_* 转换）
##   "<field_b>": String,
##   ...
##   # 当 aggregate_subs=true 且存在子行时：
##   "sub_entries": [ {"sub_id": int, "<field_a>": "...", ...}, ... ]
## }
## [/codeblock]
##
## 失败语义：
## - 文件不存在 / 读取失败 → assert 崩
## - 表头缺少 [code]id[/code] / [code]sub_id[/code] 列 → assert 崩
## - id 列空或非整数 → assert 崩（带行号）
##
## [param path] 形如 [code]res://Data/FromExcel/Hero_Data.csv[/code]。
## [param aggregate_subs] 是否把子行（sub_id 非空）聚合到主行的 sub_entries 数组里。
static func load_table(path: String, aggregate_subs: bool = true) -> Dictionary:
	assert(FileAccess.file_exists(path), "CsvLoader: file not found: %s" % path)
	var content: String = FileAccess.get_file_as_string(path)
	assert(not content.is_empty(), "CsvLoader: empty / unreadable file: %s" % path)

	# 去 UTF-8 BOM
	if content.length() > 0 and content.unicode_at(0) == 0xFEFF:
		content = content.substr(1)

	# 统一行尾为 \n，兼容 CRLF / LF
	content = content.replace("\r\n", "\n").replace("\r", "\n")

	var lines: PackedStringArray = content.split("\n", false)
	assert(lines.size() >= 1, "CsvLoader: empty CSV: %s" % path)

	# 解析表头
	var header: PackedStringArray = _split_csv_line(lines[0])
	assert(header.size() >= 2, "CsvLoader: header < 2 columns: %s" % path)
	var id_col: int = header.find("id")
	var sub_id_col: int = header.find("sub_id")
	assert(id_col >= 0, "CsvLoader: header missing 'id' col: %s | header=%s" % [path, header])
	assert(sub_id_col >= 0, "CsvLoader: header missing 'sub_id' col: %s | header=%s" % [path, header])

	var out: Dictionary = {}  # int(id) -> row dict

	# 数据行（行号从 2 开始）
	for line_idx in range(1, lines.size()):
		var line_str: String = lines[line_idx]
		if line_str.strip_edges().is_empty():
			continue
		var cells: PackedStringArray = _split_csv_line(line_str)
		# 容忍尾部缺列（视为空）
		while cells.size() < header.size():
			cells.append("")

		# 解析 id / sub_id
		var id_str: String = cells[id_col].strip_edges()
		assert(id_str.is_valid_int(),
			"CsvLoader: invalid id at %s line %d: %s" % [path, line_idx + 1, id_str])
		var id_int: int = id_str.to_int()
		var sub_id_str: String = cells[sub_id_col].strip_edges()
		var sub_id_val: Variant = null
		if not sub_id_str.is_empty():
			assert(sub_id_str.is_valid_int(),
				"CsvLoader: invalid sub_id at %s line %d: %s" % [path, line_idx + 1, sub_id_str])
			sub_id_val = sub_id_str.to_int()

		# 构造 row dict（含所有字段的原始字符串）
		var row: Dictionary = {}
		for ci in range(header.size()):
			var key: String = header[ci]
			if key.is_empty():
				continue
			row[key] = cells[ci]
		# id / sub_id 类型化覆盖
		row["id"] = id_int
		if sub_id_val != null:
			row["sub_id"] = sub_id_val
		else:
			row["sub_id"] = null

		if not aggregate_subs:
			# 平铺：多个子行会冲掉主行；调用方应不传 aggregate_subs=false 用于无子行表
			# 这里我们简单覆盖（后写赢）；如调用方需要 list，可自行 aggregate
			out[id_int] = row
			continue

		# 聚合模式
		var existing: Dictionary = out.get(id_int, {})
		if sub_id_val == null:
			# 主行：把字段合入；保留可能已存在的 sub_entries
			var subs_existing: Array = existing.get("sub_entries", [])
			existing.merge(row, true)  # row 字段覆盖 existing
			existing["sub_entries"] = subs_existing
			out[id_int] = existing
		else:
			# 子行
			if existing.is_empty():
				# 主行还没出现：先占位
				existing = {"id": id_int, "sub_id": null, "sub_entries": []}
			var subs: Array = existing.get("sub_entries", [])
			subs.append(row)
			existing["sub_entries"] = subs
			out[id_int] = existing

	return out


# ─────────────────────────────────────────────────────────────
# 取值器（调用方按字段类型取）
# ─────────────────────────────────────────────────────────────


## 取 row[key] 当 float。空字符串 → default。
static func as_float(row: Dictionary, key: String, default: float = 0.0) -> float:
	if not row.has(key):
		return default
	var v: Variant = row[key]
	if v == null:
		return default
	if v is float or v is int:
		return float(v)
	var s: String = String(v).strip_edges()
	if s.is_empty():
		return default
	# is_valid_float 也接受整数文本
	assert(s.is_valid_float(), "CsvLoader.as_float: bad value at key=%s val=%s" % [key, s])
	return s.to_float()


## 取 row[key] 当 int。空 → default。
static func as_int(row: Dictionary, key: String, default: int = 0) -> int:
	if not row.has(key):
		return default
	var v: Variant = row[key]
	if v == null:
		return default
	if v is int:
		return v
	if v is float:
		return int(v)
	var s: String = String(v).strip_edges()
	if s.is_empty():
		return default
	assert(s.is_valid_int(), "CsvLoader.as_int: bad value at key=%s val=%s" % [key, s])
	return s.to_int()


## 取 row[key] 当 String。null → default。
static func as_string(row: Dictionary, key: String, default: String = "") -> String:
	if not row.has(key):
		return default
	var v: Variant = row[key]
	if v == null:
		return default
	return String(v)


## 取 row[key] 当 StringName。
static func as_string_name(row: Dictionary, key: String, default: StringName = &"") -> StringName:
	var s: String = as_string(row, key, "")
	if s.is_empty():
		return default
	return StringName(s)


## 取 row[key] 当 List(Float)。期望 [code]{a,b,c}[/code] 字面量；空字符串 → 空数组。
##
## 失败（格式错误）→ assert 崩。
static func as_list_float(row: Dictionary, key: String) -> Array:
	var s: String = as_string(row, key, "").strip_edges()
	if s.is_empty():
		return []
	var inner: String = _strip_braces(s, key)
	if inner.is_empty():
		return []
	var parts: PackedStringArray = inner.split(",")
	var out: Array = []
	out.resize(parts.size())
	for i in range(parts.size()):
		var p: String = parts[i].strip_edges()
		assert(p.is_valid_float(),
			"CsvLoader.as_list_float: bad item at key=%s idx=%d val=%s" % [key, i, p])
		out[i] = p.to_float()
	return out


## 取 row[key] 当 List(Int)。
static func as_list_int(row: Dictionary, key: String) -> Array:
	var s: String = as_string(row, key, "").strip_edges()
	if s.is_empty():
		return []
	var inner: String = _strip_braces(s, key)
	if inner.is_empty():
		return []
	var parts: PackedStringArray = inner.split(",")
	var out: Array = []
	out.resize(parts.size())
	for i in range(parts.size()):
		var p: String = parts[i].strip_edges()
		assert(p.is_valid_int(),
			"CsvLoader.as_list_int: bad item at key=%s idx=%d val=%s" % [key, i, p])
		out[i] = p.to_int()
	return out


## 取 row[key] 当 List(String)。元素无类型校验，按英文逗号 [code],[/code] 拆分（与 List(Int)/List(Float) 一致）。
##
## 注：策划若在文本里需要包含英文逗号，请改用其他分隔字符替代；空字符串返回空数组。
static func as_list_string(row: Dictionary, key: String) -> Array:
	var s: String = as_string(row, key, "").strip_edges()
	if s.is_empty():
		return []
	var inner: String = _strip_braces(s, key)
	if inner.is_empty():
		return []
	var parts: PackedStringArray = inner.split(",")
	var out: Array = []
	out.resize(parts.size())
	for i in range(parts.size()):
		out[i] = parts[i].strip_edges()
	return out


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────


## 拆一行 CSV，处理双引号包裹（含转义双引号 ""→"）。
##
## 不依赖 String.split_csv_row（API 限定 4.x 才有；为版本兼容自实现）。
static func _split_csv_line(line: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var buf: String = ""
	var i: int = 0
	var in_quote: bool = false
	var n: int = line.length()
	while i < n:
		var ch: String = line.substr(i, 1)
		if in_quote:
			if ch == "\"":
				if i + 1 < n and line.substr(i + 1, 1) == "\"":
					buf += "\""
					i += 2
					continue
				in_quote = false
				i += 1
				continue
			buf += ch
			i += 1
		else:
			if ch == "\"":
				in_quote = true
				i += 1
				continue
			if ch == ",":
				out.append(buf)
				buf = ""
				i += 1
				continue
			buf += ch
			i += 1
	out.append(buf)
	return out


## 去掉 List 字面量两端的 `{` `}`。
static func _strip_braces(s: String, key: String) -> String:
	var t: String = s.strip_edges()
	assert(t.begins_with("{") and t.ends_with("}"),
		"CsvLoader._strip_braces: expected {...} at key=%s val=%s" % [key, s])
	return t.substr(1, t.length() - 2).strip_edges()
