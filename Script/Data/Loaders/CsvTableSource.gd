## CSV 表数据源（IO 层抽象）。
##
## 启动期一次性 [method load_paths] 读所有需要的 CSV 文件到内存缓存，
## 后续 [method get_table] 按 path 取已解析的 RowDict[int]。
##
## 设计目标：
##   - SRP：把"文件 IO + CsvLoader.load_table"集中在一处，业务侧只接触 Dictionary
##   - 便于测试：替换为 MockTableSource 可注入测试数据，不依赖文件系统
##   - 失败语义：load_paths 内部如某 CSV 缺失 → CsvLoader 自带 assert 崩（R-CODE-01）
class_name CsvTableSource
extends RefCounted

var _tables: Dictionary = {}  # String(path) -> Dictionary[int, RowDict]


## 一次性加载多个 CSV 文件。
##
## 内部调用 [method CsvLoader.load_table]，路径不存在 / 表头缺 id-sub_id → assert 崩。
func load_paths(paths: Array) -> void:
	for p in paths:
		var path_str: String = String(p)
		_tables[path_str] = CsvLoader.load_table(path_str, true)


## 取已加载的表（按 path）。
##
## 表未加载 → assert 崩（开发期错误，应在 load_paths 时一并加载）。
func get_table(path: String) -> Dictionary:
	assert(_tables.has(path), "CsvTableSource.get_table: not loaded: %s" % path)
	return _tables[path]


## 表是否已加载。
func has_table(path: String) -> bool:
	return _tables.has(path)


## 取行（按 path + id）。找不到返回空 dict（不崩；调用方按需 assert）。
func get_row(path: String, id: int) -> Dictionary:
	return get_table(path).get(id, {})


## 已加载的表数量（调试用）。
func table_count() -> int:
	return _tables.size()
