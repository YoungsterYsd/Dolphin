## 道具 Fragment 基类（Resource）。
##
## Lyra Inventory Fragment 模式 —— 组合式物品定义。
## 多个 Fragment 组合在 [ItemDefinition.fragments] 数组里 = 一件物品的完整能力。
##
## 子类按需 override 5 个虚钩子（默认 noop）：
##   - [method on_instance_created]：ItemInstance.create_new() 时触发（如 Fragment_Equip 滚字）
##   - [method intercepts_inventory_add]：是否拦截入库（如 Fragment_Currency 路由到 CurrencyManager）
##   - [method handle_inventory_add]：拦截后的处理
##   - [method on_use]：InventoryComponent.use 时触发（返回 false 阻断 consume）
##   - [method on_equipped]：EquipmentComponent.equip 时触发（如 Fragment_GA 授予技能）
##   - [method on_unequipped]：unequip 时触发
##
## 所有 Fragment 子类必须实现 [method from_csv_row] 静态工厂（CSV 装配期调用）。
##
## R-CODE-02：用声明式 fragments 数组 + 钩子虚函数路由，**不**走字符串反射。
class_name ItemFragment
extends Resource


## CSV → Fragment 实例的工厂方法。子类必须 override。
##
## [param row]：CsvLoader 解析后的 row dict（含 sub_entries[] 用于 1:N 子表）
## [param source]：CsvTableSource，子类可按需取其它 CSV 表
##
## 返回构造好的 Fragment 实例；返回 null 表示该 id 无对应配置（调用方应过滤）。
static func from_csv_row(_row: Dictionary, _source) -> ItemFragment:
	push_error("ItemFragment.from_csv_row: must be overridden by subclass")
	return null


## ItemInstance 新建时触发（仅 ItemInstance.create_new 路径会调，from_save 不调）。
##
## 用途：写入 stat_tags 的初始值（如 Fragment_Equip 滚字结果、Fragment_Stackable 初始堆数）。
func on_instance_created(_instance) -> void:
	pass


## 是否拦截 InventoryComponent.add 流程。
##
## 返回 true → InventoryComponent 不会把物品放进背包槽，改调 [method handle_inventory_add]。
## 用于 Fragment_Currency 路由到 CurrencyManager（货币不进背包网格）。
func intercepts_inventory_add(_def, _count: int) -> bool:
	return false


## 拦截后的处理。返回"已消化的数量"。
func handle_inventory_add(_owner, _def, _count: int) -> int:
	return 0


## InventoryComponent.use(slot) 时由通用流程触发（每个 fragment 都调一次）。
##
## 返回 true → 允许通用 consume 流程继续（结合 [code]def.consumable[/code] 决定是否扣 1）；
## 返回 false → 阻断 consume（如 Fragment_Currency 不响应 use）。
func on_use(_owner, _instance) -> bool:
	return true


## EquipmentComponent.equip(instance) 时触发（每个 fragment 都调一次）。
##
## 用途：Fragment_GA 授予技能 / Fragment_GE 挂载常驻 GE。
func on_equipped(_owner, _instance) -> void:
	pass


## EquipmentComponent.unequip 时触发（每个 fragment 都调一次）。
func on_unequipped(_owner, _instance) -> void:
	pass
