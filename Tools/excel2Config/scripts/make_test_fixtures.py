"""生成测试 xlsx 文件，供手动测试 excel2tres 工具。

输出：
    Tools/Excel/Sample_Clean.xlsx   —— 全干净，覆盖全部类型与聚合特性
    Tools/Excel/Sample_Bad.xlsx     —— 故意混入 7 类错误 + 2 类警告，用于验证 fail-collect

运行：
    cd Tools/excel2tres
    python scripts/make_test_fixtures.py
"""
from __future__ import annotations

from pathlib import Path

from openpyxl import Workbook


# 输出位置（相对仓库根）
ROOT = Path(__file__).resolve().parents[2]  # Tools/excel2tres/scripts → Tools/
EXCEL_DIR = ROOT / "Excel"
EXCEL_DIR.mkdir(parents=True, exist_ok=True)


# ---------------------------------------------------------------------------
# Sample_Clean.xlsx —— 走通各种类型/聚合
# ---------------------------------------------------------------------------


CLEAN_SHEETS: dict[str, list[list]] = {
    # 简单标量 + Enum + List
    "Characters": [
        ["_export", "id", "sub_id", "category", "level", "display_name", "move_speed", "growth_table_id", "scene_path", "tags"],
        ["Int", "Int", "Int", "Enum(Normal,Elite,Boss)", "Int", "String", "Float", "Int", "String", "List(String)"],
        [1, 1, None, "Normal", 1, "Slime", -1.0, 1001, "res://Scenes/Characters/Enemy_Slime.tscn", "{enemy.normal,goblin}"],
        [1, 2, None, "Elite", 5, "Elite Slime", 2.5, 1001, "res://Scenes/Characters/Enemy_Slime.tscn", "{enemy.elite}"],
        [1, 100, None, "Boss", 1, "Boss Demo", -1.0, 2001, "res://Scenes/Characters/Boss_Demo.tscn", "{enemy.boss}"],
        # 草稿行：_export=0 → 跳过
        [0, 999, None, "Normal", 0, "WIP NPC", 0, 0, "", "{}"],
    ],
    # 主行 + 多 sub_id 子行（聚合方案 A）
    "Growth": [
        ["_export", "id", "sub_id", "attribute", "base_value", "breakpoint_level", "per_level_delta"],
        ["Int", "Int", "Int", "String", "Float", "Int", "Float"],
        # id=1001 有主行（虽然主行所有字段都留空，会走默认值；策划可见）
        [1, 1001, None, None, None, None, None],
        [1, 1001, 1, "max_health", 30.0, 5, 5.0],
        [1, 1001, 2, "max_health", 30.0, 10, 8.0],
        [1, 1001, 3, "attack", 5.0, 10, 1.0],
        [1, 1001, 4, "defense", 2.0, 10, 0.5],
        # id=2001 没有主行（演示主行可缺省）
        [1, 2001, 1, "max_health", 200.0, 10, 50.0],
        [1, 2001, 2, "attack", 30.0, 10, 5.0],
    ],
    # Ignore 列 + List(Int)/List(Float) + 留空走默认值
    "Items": [
        ["_export", "id", "sub_id", "display_name", "max_stack", "drop_weights", "price", "rarity", "_note"],
        ["Int", "Int", "Int", "String", "Int", "List(Int)", "Float", "Enum(Common,Rare,Epic,Legendary)", "Ignore"],
        # 留空：max_stack→0, drop_weights→[], rarity→第一项 Common
        [1, 3001, None, "Health Potion", None, None, 10.0, None, "策划备注：初始道具"],
        [1, 3002, None, "Iron Sword", 1, "{10,20,5}", 50.0, "Rare", "近战武器"],
        [1, 3003, None, "Boss Drop", 1, "{1}", 999.5, "Legendary", "Boss 专属"],
    ],
    # List(Float) + 全字段留空测试
    "Effects": [
        ["_export", "id", "sub_id", "display_name", "duration", "period", "tag_list"],
        ["Int", "Int", "Int", "String", "Float", "Float", "List(String)"],
        [1, 2001, None, "BasicDamage", -1.0, 0.0, "{damage.physical}"],
        [1, 2002, None, "Burning(3s)", 3.0, 0.5, "{dot.fire,debuff}"],
        # 全字段留空
        [1, 2003, None, None, None, None, None],
    ],
}


# ---------------------------------------------------------------------------
# Sample_Bad.xlsx —— 各类错误 / 警告
# ---------------------------------------------------------------------------
#
# 一份表里同时混入：
#   E1: _export=2（非 0/1）
#   E2: id=0
#   E3: sub_id=0
#   E4: Int 列填字母 abc
#   E5: Enum 值不在词表
#   E6: List(Int) 缺大括号
#   E7: (id, sub_id) 联合主键重复（含主行重复）
#   W1: 前三列字段名错（_export 写成 export）
#   W2: 前三列类型错（id 类型行写 String）
#
# 工具应当一次性收集 ≥7 个 Error + ≥1 个 Warning（fail-collect 验证）。


BAD_SHEETS: dict[str, list[list]] = {
    "BadSheet": [
        # 行 1：W1 前三列字段名错（应为 _export / id / sub_id）
        ["export", "id", "sub_id", "level", "category", "tags", "name"],
        # 行 2：W2 前三列类型错（id 应该是 Int，这里写成 String）
        ["Int", "String", "Int", "Int", "Enum(A,B,C)", "List(Int)", "String"],
        # 行 3：✓ 干净行
        [1, 1, None, 1, "A", "{1,2,3}", "Alice"],
        # 行 4：E1 _export=2
        [2, 2, None, 1, "A", "{1}", "Bob"],
        # 行 5：E2 id=0
        [1, 0, None, 1, "A", "{1}", "Charlie"],
        # 行 6：E3 sub_id=0
        [1, 3, 0, 1, "A", "{1}", "Dave"],
        # 行 7：E4 Int 列填字母
        [1, 4, None, "abc", "A", "{1}", "Eve"],
        # 行 8：E5 Enum 非词表值 Mythic
        [1, 5, None, 1, "Mythic", "{1}", "Frank"],
        # 行 9：E6 List(Int) 缺大括号
        [1, 6, None, 1, "A", "1,2,3", "Grace"],
        # 行 10/11：E7 联合主键重复（id=1, sub_id 都为空）
        [1, 1, None, 99, "B", "{}", "Heidi"],  # 与行 3 主键冲突
    ],
    # 类型行未知字面量（Bool）—— 整列字段会被丢弃，但其它字段仍可解析
    "UnknownTypeSheet": [
        ["_export", "id", "sub_id", "v", "is_active"],
        ["Int", "Int", "Int", "Int", "Bool"],  # Bool 是非法类型
        [1, 1, None, 10, True],
    ],
}


# ---------------------------------------------------------------------------
# 写文件
# ---------------------------------------------------------------------------


def write_xlsx(path: Path, sheets: dict[str, list[list]]) -> None:
    wb = Workbook()
    wb.remove(wb.active)
    for name, rows in sheets.items():
        ws = wb.create_sheet(title=name)
        for r in rows:
            ws.append(r)
    wb.save(path)
    print(f"  wrote {path}")


def main() -> None:
    print(f"输出目录: {EXCEL_DIR}")
    write_xlsx(EXCEL_DIR / "Sample_Clean.xlsx", CLEAN_SHEETS)
    write_xlsx(EXCEL_DIR / "Sample_Bad.xlsx", BAD_SHEETS)
    print("完成。")


if __name__ == "__main__":
    main()
