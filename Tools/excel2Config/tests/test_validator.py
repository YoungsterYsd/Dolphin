"""validator 单测。重点：fail-collect（一次收集多个错误）。"""
from __future__ import annotations

from pathlib import Path

from openpyxl import Workbook

from core.validator import validate_paths


def _make_xlsx(tmp_path: Path, sheets: dict[str, list[list]], name: str = "t.xlsx") -> Path:
    wb = Workbook()
    wb.remove(wb.active)
    for sname, rows in sheets.items():
        ws = wb.create_sheet(title=sname)
        for r in rows:
            ws.append(r)
    path = tmp_path / name
    wb.save(path)
    return path


# ---------------------------------------------------------------------------
# 正常路径
# ---------------------------------------------------------------------------


class TestHappyPath:
    def test_single_clean_sheet(self, tmp_path):
        p = _make_xlsx(
            tmp_path,
            {
                "Characters": [
                    ["_export", "id", "sub_id", "level", "name"],
                    ["Int", "Int", "Int", "Int", "String"],
                    [1, 1, None, 1, "Slime"],
                    [1, 2, None, 5, "Elite"],
                ]
            },
        )
        result = validate_paths([p])
        assert result.is_clean
        assert len(result.sheets) == 1
        assert len(result.all_errors) == 0

    def test_directory_scan(self, tmp_path):
        _make_xlsx(
            tmp_path,
            {"A": [["_export", "id", "sub_id", "v"], ["Int", "Int", "Int", "Int"], [1, 1, None, 1]]},
            name="combat.xlsx",
        )
        _make_xlsx(
            tmp_path,
            {"B": [["_export", "id", "sub_id", "n"], ["Int", "Int", "Int", "String"], [1, 1, None, "x"]]},
            name="items.xlsx",
        )
        result = validate_paths([tmp_path])
        assert result.is_clean
        assert {s.sheet_name for s in result.sheets} == {"A", "B"}

    def test_only_sheet_filter(self, tmp_path):
        p = _make_xlsx(
            tmp_path,
            {
                "A": [["_export", "id", "sub_id", "v"], ["Int", "Int", "Int", "Int"], [1, 1, None, 1]],
                "B": [["_export", "id", "sub_id", "v"], ["Int", "Int", "Int", "Int"], [1, 1, None, 2]],
            },
        )
        result = validate_paths([p], only_sheet="B")
        assert len(result.sheets) == 1
        assert result.sheets[0].sheet_name == "B"


# ---------------------------------------------------------------------------
# Fail-collect：M10.3 验收清单的 5 类错误同时存在
# ---------------------------------------------------------------------------


class TestFailCollect:
    """对应 M10.3 验收：
    故意写 _export=2 / id=0 / Int 列填字母 / Enum 写非枚举值 / (id,sub_id) 联合键重复
    → 校验输出全部 5 个错误。
    """

    def test_five_kinds_of_errors_all_collected(self, tmp_path):
        p = _make_xlsx(
            tmp_path,
            {
                "X": [
                    ["_export", "id", "sub_id", "level", "cat"],
                    ["Int", "Int", "Int", "Int", "Enum(A,B,C)"],
                    # row 3：_export=2（错 1）
                    [2, 1, None, 1, "A"],
                    # row 4：id=0（错 2）
                    [1, 0, None, 1, "A"],
                    # row 5：Int 列填字母 abc（错 3）
                    [1, 10, None, "abc", "A"],
                    # row 6：Enum 非词表值 Mythic（错 4）
                    [1, 20, None, 1, "Mythic"],
                    # row 7+8：联合键重复（错 5）
                    [1, 30, None, 1, "A"],
                    [1, 30, None, 2, "B"],
                ]
            },
        )
        result = validate_paths([p])
        errors = result.all_errors
        # 至少 5 个独立错误
        assert len(errors) >= 5

        # 分类验证（每类至少一条）
        reasons = " | ".join(e.reason for e in errors)
        assert "_export" in reasons
        assert "id" in reasons  # id=0
        assert "Int" in reasons  # abc
        assert "Enum" in reasons or "词表" in reasons
        assert "联合主键重复" in reasons


# ---------------------------------------------------------------------------
# 留空走默认值（M10.3 验收）
# ---------------------------------------------------------------------------


class TestBlankCellsDefaults:
    def test_blank_cells_no_error(self, tmp_path):
        # D 列起字段全留空 → 不报错，走默认值
        p = _make_xlsx(
            tmp_path,
            {
                "X": [
                    ["_export", "id", "sub_id", "n", "f", "s", "e", "li", "ls"],
                    ["Int", "Int", "Int", "Int", "Float", "String", "Enum(A,B,C)", "List(Int)", "List(String)"],
                    [1, 1, None, None, None, None, None, None, None],
                ]
            },
        )
        result = validate_paths([p])
        assert result.is_clean

        rec = result.sheets[0].agg.records[1]
        assert rec.fields == {
            "n": 0,
            "f": 0.0,
            "s": "",
            "e": "A",  # Enum 第一项
            "li": [],
            "ls": [],
        }


# ---------------------------------------------------------------------------
# Warning（前三列名称/类型不一致）
# ---------------------------------------------------------------------------


class TestWarnings:
    def test_fixed_col_name_warning_no_error(self, tmp_path):
        p = _make_xlsx(
            tmp_path,
            {
                "X": [
                    ["export", "id", "sub_id", "v"],  # _export 错写成 export
                    ["Int", "Int", "Int", "Int"],
                    [1, 1, None, 5],
                ]
            },
        )
        result = validate_paths([p])
        # Warning 不阻断
        assert result.is_clean
        assert len(result.all_warnings) >= 1
