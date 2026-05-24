## 伤害冲击 → 硬度等级映射表（玩家敌人共用）。
##
## 数据来源（R-DATA-03 走 CSV 路线）：
## - Excel 源：[code]Tools/Excel/战斗配置表.xlsx[/code] 的 [code]Dmg_Hardness[/code] sheet
## - 运行时 CSV：[code]Data/FromExcel/Dmg_Hardness.csv[/code]
##
## CSV 表结构（按 [code]DmgPercent[/code] 升序）：
## [codeblock]
## id, sub_id, DmgPercent, Hardness
## 1,  ,        0.05,       1
## 2,  ,        0.10,       2
## 3,  ,        0.30,       3
## 4,  ,        0.50,       4
## 5,  ,        0.80,       5
## 6,  ,        1.00,       6
## [/codeblock]
##
## 语义：本下命中造成 [code]ratio = dealt / target.max_health[/code] 的伤害占比，
## 反查表得出"这一下的冲击硬度等级"，与目标当前硬度比较决定是否打断。
##
## 由 [InterruptResolver] 在 [DamagePipeline] 第 10.5 步调用：当 [DamageNode.hit_poise] = -1 时回退本表。
##
## 设计：纯静态 + 启动期一次加载并排序缓存；热点路径只查内存。
class_name PoiseImpactTable

const _LOG_CH := "Combat"
const _CSV_PATH := "res://Data/FromExcel/Dmg_Hardness.csv"

## 已排序条目缓存：[{ratio: float, level: int}, ...]，按 ratio 升序。
static var _entries: Array = []

## 是否已尝试加载（无论成功）。避免重复 I/O。
static var _loaded: bool = false


## 显式加载（启动期可由 ConfigCenter / GameInstance 触发；运行期首次 resolve 也会自动触发）。
##
## 失败语义（R-CODE-01）：
## - 文件不存在 / 解析失败 / 表为空 → assert 崩
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true

	var table: Dictionary = CsvLoader.load_table(_CSV_PATH, false)
	assert(not table.is_empty(),
		"PoiseImpactTable: empty table at %s" % _CSV_PATH)

	var arr: Array = []
	for id in table.keys():
		var row: Dictionary = table[id]
		# 用 CsvLoader 取值器（自动类型转换 + 失败 assert）
		var ratio: float = CsvLoader.as_float(row, "DmgPercent")
		var level: int = CsvLoader.as_int(row, "Hardness")
		arr.append({"ratio": ratio, "level": level})

	assert(not arr.is_empty(),
		"PoiseImpactTable: no valid entries in %s" % _CSV_PATH)

	arr.sort_custom(func(a, b): return float(a["ratio"]) < float(b["ratio"]))
	_entries = arr

	GameLogger.info(_LOG_CH, "PoiseImpactTable loaded %d entries from %s" % [_entries.size(), _CSV_PATH])


## 按伤害比例（[code]dealt / max_hp[/code]）反查冲击硬度等级。
##
## 比例低于第一档的"擦伤"返回 [code]0[/code]（不打断任何东西，含 base_poise=0 的角色也不打断）。
## 比例命中某档时返回该档 Hardness；超出最高档自动取最高档。
static func resolve(damage_ratio: float) -> int:
	ensure_loaded()
	if damage_ratio <= 0.0 or _entries.is_empty():
		return 0
	var lv: int = 0
	for e in _entries:
		if damage_ratio >= float(e["ratio"]):
			lv = int(e["level"])
		else:
			break
	return lv


## 调试用：返回当前缓存条目副本（按 ratio 升序）。
static func get_entries_snapshot() -> Array:
	ensure_loaded()
	return _entries.duplicate(true)
