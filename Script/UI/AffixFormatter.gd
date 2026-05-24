## 词条 / 属性显示格式化工具（静态工具类）。
##
## 把 affix_mod dict（[code]{attribute, op, magnitude}[/code]）格式化为玩家可读字符串：
##   - `add` 操作 → 整数 / 一位小数显示，绝对值（如 [color=lightblue]+20 生命[/color]）
##   - `multiply` 操作 → 百分比显示（如 [color=lightblue]+10% 攻击加成[/color]）
##   - 颜色：正向加成蓝色 / 负向减益红色
##
## 同时维护属性显示名映射（attribute_name → 中文显示名 + 单位约定）。
## R-HUD-03：颜色 / 字号 不硬编码 → 走 BBCode tag，由 RichTextLabel theme 决定具体色值。
##
## 使用：
## [codeblock]
## var line: String = AffixFormatter.format_mod({"attribute": "attack_base", "op": "add", "magnitude": 15.0})
## # → "  +15 基础攻击"
## var name: String = AffixFormatter.attribute_display_name(&"attack_bonus")
## # → "攻击加成"
## [/codeblock]
class_name AffixFormatter
extends RefCounted

# 属性名 → 中文显示名（按 attr_plan.csv 现有词条 + 常用扩展）
const ATTR_DISPLAY_NAMES: Dictionary = {
	&"health_base": "生命",
	&"max_health": "最大生命",
	&"stamina_max": "最大耐力",
	&"stamina_current": "耐力",
	&"attack_base": "基础攻击",
	&"attack_bonus": "攻击加成",
	&"crit_chance": "暴击率",
	&"crit_damage": "暴击伤害",
	&"def_pierce": "破甲",
	&"dmg_red_mul": "减伤",
	&"life_steal_mul": "吸血",
	&"move_speed_base": "移动速度",
}


## 格式化单条 affix mod。
## mod = `{attribute: StringName, op: String("add"|"multiply"), magnitude: float}`
##
## 返回带 BBCode 着色的行（前缀两个空格缩进）。
static func format_mod(mod: Dictionary) -> String:
	var attr_name: StringName = StringName(str(mod.get("attribute", "")))
	var op: String = String(mod.get("op", "add"))
	var mag: float = float(mod.get("magnitude", 0.0))
	var disp: String = attribute_display_name(attr_name)
	var sign: String = "+" if mag >= 0.0 else ""
	var color: String = "lightblue" if mag >= 0.0 else "salmon"
	var value_text: String
	if op == "multiply":
		value_text = "%s%.0f%%" % [sign, mag * 100.0]
	else:
		# 整数显示去掉 .0；小数保留 1 位
		if abs(mag - round(mag)) < 0.001:
			value_text = "%s%d" % [sign, int(round(mag))]
		else:
			value_text = "%s%.1f" % [sign, mag]
	return "  [color=%s]%s %s[/color]" % [color, value_text, disp]


## 属性 attribute_name → 中文显示名（找不到回退原 string）。
static func attribute_display_name(attr_name: StringName) -> String:
	return String(ATTR_DISPLAY_NAMES.get(attr_name, str(attr_name)))


## 品质（rarity 0~5）→ 颜色 + 中文标签。
##
## 返回 `{color: Color, label: String}`。
## 0 = 无品质（白）、1 普通（白）、2 优良（绿）、3 稀有（蓝）、4 史诗（紫）、5 传说（橙）、6 神话（红）
static func rarity_style(rarity: int) -> Dictionary:
	match rarity:
		0, 1:
			return {"color": Color(0.85, 0.85, 0.85, 1), "label": "普通"}
		2:
			return {"color": Color(0.4, 0.9, 0.4, 1), "label": "优良"}
		3:
			return {"color": Color(0.35, 0.6, 1.0, 1), "label": "稀有"}
		4:
			return {"color": Color(0.7, 0.4, 1.0, 1), "label": "史诗"}
		5:
			return {"color": Color(1.0, 0.6, 0.1, 1), "label": "传说"}
		_:
			return {"color": Color(1.0, 0.3, 0.3, 1), "label": "神话"}


## 一次性把 mods 数组格式化为多行 BBCode 文本（RichTextLabel 用）。
static func format_mods_block(mods: Array) -> String:
	if mods.is_empty():
		return ""
	var lines: Array[String] = ["[i]── 词条 ──[/i]"]
	for m in mods:
		lines.append(format_mod(m))
	return "\n".join(lines)


## 把 mods 数组格式化为纯文本（普通 Label 用，不含 BBCode）。
static func format_mods_block_plain(mods: Array) -> String:
	if mods.is_empty():
		return ""
	var lines: Array[String] = ["── 词条 ──"]
	for m in mods:
		lines.append(_format_mod_plain(m))
	return "\n".join(lines)


static func _format_mod_plain(mod: Dictionary) -> String:
	var attr_name: StringName = StringName(str(mod.get("attribute", "")))
	var op: String = String(mod.get("op", "add"))
	var mag: float = float(mod.get("magnitude", 0.0))
	var disp: String = attribute_display_name(attr_name)
	var sign: String = "+" if mag >= 0.0 else ""
	if op == "multiply":
		return "  %s%.0f%% %s" % [sign, mag * 100.0, disp]
	if abs(mag - round(mag)) < 0.001:
		return "  %s%d %s" % [sign, int(round(mag)), disp]
	return "  %s%.1f %s" % [sign, mag, disp]
