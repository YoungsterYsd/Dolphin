## 业务日志门面（薄封装，转发到 Godot 原生 API）。
##
## 用法：[code]GameLogger.info("GAS", "ability activated: %s" % id)[/code]
## 通道（channel）建议取值："Core" / "GAS" / "AI" / "UI" / "Level" / "Audio" / "Settings" / "Character"。
## 业务代码禁止裸 [code]print()[/code]，统一走本类（参见 R-LOG-01）。
##
## 实现策略：
##   - [method info] → [method @GlobalScope.print_rich]，彩色控制台输出
##   - [method warn] → [method @GlobalScope.push_warning]，进 Debugger Errors 面板
##   - [method error] → [method @GlobalScope.push_error]，进 Debugger Errors 面板 + 默认触发断点
##
## 注：类名 [code]GameLogger[/code] 而非 [code]Logger[/code]，因 Godot 4.x 内置 [Logger]
## 是「日志接收钩子」（被动 observer，配合 [method OS.add_logger] 使用），并非输出门面。
## 未来若需错误上报 / 录像日志，可另写 [code]extends Logger[/code] 子类注册进去，与本类正交。
class_name GameLogger
extends RefCounted


static func info(channel: String, msg: String) -> void:
	print_rich("[color=gray][INFO][/color][color=cyan][%s][/color] %s" % [channel, msg])


static func warn(channel: String, msg: String) -> void:
	push_warning("[%s] %s" % [channel, msg])


static func error(channel: String, msg: String) -> void:
	push_error("[%s] %s" % [channel, msg])
