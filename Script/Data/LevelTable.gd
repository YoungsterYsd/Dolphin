## 升级表（玩家等级经验曲线，玩家专用）。
##
## 数据来源：[code]Tools/Excel/角色表.xlsx → Hero_Lev sheet[/code]，
## 由 excel2Config 工具导出为 [code]res://Data/FromExcel/Hero_Lev.csv[/code]。
##
## ── CSV 契约 ──
## 表头：[code]id, sub_id, Lev, Exp[/code]
## 语义：[code]Lev=N[/code] 行的 [code]Exp[/code] 字段表示
##       "**从 N 级升到 N+1 级**所需的经验"。
## 示例（当前 CSV）：
##   - Lev=1 Exp=10  → 1→2 需要 10 经验
##   - Lev=9 Exp=90  → 9→10 需要 90 经验
##   - 没有 Lev=10 行 → 10 级是上限（CSV 里没"通往下一级"的记录就意味满级）
##
## ── 等级上限规则 ──
## [member max_level] = CSV 中最大 Lev + 1（"加完最后一档就到上限"）。
## 策划改 Excel 加一行（如 Lev=10 Exp=100）→ 重导 CSV → 上限自动变成 11，零代码改动。
##
## ── 与怪物等级的关系 ──
## 怪物等级在 Monster_Data.csv 直接配死，**不读本表**；本表仅给玩家累积经验用。
##
## ── 失败语义（R-CODE-01 fail-fast）──
## - CSV 缺失 → CsvLoader.load_table 内部 assert 崩
## - 查询不存在的等级（< 1 或 > top_lev）→ assert 崩（属于业务调用错误）
## - 表内空（无任何 Lev 行）→ load_from_csv 后 assert 崩
##
## 由 [ConfigCenter] 在 _bootstrap 时装载并通过 [method ConfigCenter.get_xp_to_next]
## 等 API 暴露给业务侧；业务侧禁止直接 new LevelTable。
class_name LevelTable
extends RefCounted


## CSV 路径常量。
const CSV_PATH := "res://Data/FromExcel/Hero_Lev.csv"


## 等级 N → 升到 N+1 级所需经验。
## 例：[code]xp_curve[1] = 10[/code] 表示 1→2 需要 10 经验。
var xp_curve: Dictionary = {}

## 玩家最大可达等级（=CSV 最大 Lev + 1）。
##
## 当前 CSV 最大 Lev=9 → max_level=10。
var max_level: int = 1


## 从 CSV 加载并解析。
##
## R-CODE-01：CSV 内容必须有效；解析失败 / 空表 → assert 崩。
func load_from_csv(path: String = CSV_PATH) -> void:
	xp_curve.clear()
	max_level = 1
	# Hero_Lev 表无子行，平铺即可
	var rows: Dictionary = CsvLoader.load_table(path, false)
	var top_lev: int = 0
	for id_key in rows.keys():
		var row: Dictionary = rows[id_key]
		# 兼容 Excel 表头大小写（当前 Hero_Lev 表头为 Lev/Exp 大写驼峰；
		# TODO 与策划同步把 Excel 表头统一为小写 lev/exp 后可删 lower 兼容分支）
		var lev: int = CsvLoader.as_int(row, "Lev", 0)
		if lev <= 0:
			lev = CsvLoader.as_int(row, "lev", 0)
		var exp: int = CsvLoader.as_int(row, "Exp", 0)
		if exp <= 0:
			exp = CsvLoader.as_int(row, "exp", 0)
		assert(lev > 0 and exp > 0,
			"LevelTable: invalid row in %s: id=%s lev=%d exp=%d" % [path, id_key, lev, exp])
		xp_curve[lev] = exp
		if lev > top_lev:
			top_lev = lev
	assert(top_lev > 0, "LevelTable: empty curve loaded from %s" % path)
	# 等级上限 = CSV 最大档 + 1
	max_level = top_lev + 1


## 取从 [param level] 升到 [param level]+1 所需经验。
##
## - 已满级（[code]level >= max_level[/code]）→ 返回 0（业务侧据此判定满级）
## - 等级 < 1 或 1 ≤ level < max_level 但 CSV 漏配 → assert 崩
func get_xp_to_next(level: int) -> int:
	if level >= max_level:
		return 0
	assert(level >= 1, "LevelTable.get_xp_to_next: level must be >= 1, got %d" % level)
	assert(xp_curve.has(level),
		"LevelTable.get_xp_to_next: missing level %d in curve (CSV must cover 1..%d)" % [level, max_level - 1])
	return int(xp_curve[level])
