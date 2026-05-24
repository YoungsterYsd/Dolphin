"""sheet_reader 单元测试。用 openpyxl 写临时 xlsx 再读。"""
from __future__ import annotations

from pathlib import Path

import pytest
from openpyxl import Workbook

from core.sheet_reader import (
    FIXED_COL_NAMES,
    FIXED_COL_TYPES,
    read_sheet,
    read_workbook,
)
from core.type_parser import TypeKind


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------


def write_sheet(ws, rows: list[list]) -> None:
    """把 rows 写入 ws，每个内层列表是一行的值。"""
    for r in rows:
        ws.append(r)


def make_xlsx(tmp_path: Path, sheets: dict[str, list[list]]) -> Path:
    """创建临时 xlsx，sheets 是 {sheet_name: [行1, 行2, ...]}。"""
    wb = Workbook()
    # 删默认 sheet
    default = wb.active
    wb.remove(default)
    for name, rows in sheets.items():
        ws = wb.create_sheet(title=name)
        write_sheet(ws, rows)
    path = tmp_path / "test.xlsx"
    wb.save(path)
    return path


# ---------------------------------------------------------------------------
# 正常解析
# ---------------------------------------------------------------------------


class TestReadSheetBasic:
    def test_minimal_sheet(self, tmp_path):
        path = make_xlsx(
            tmp_path,
            {
                "Characters": [
                    ["_export", "id", "sub_id", "level", "display_name"],
                    ["Int", "Int", "Int", "Int", "String"],
                    [1, 1, None, 1, "Slime"],
                    [1, 2, None, 5, "Elite"],
                ]
            },
        )
        sheets = read_workbook(path)
        assert len(sheets) == 1
        s = sheets[0]
        assert s.sheet_name == "Characters"
        assert len(s.fields) == 2
        assert s.fields[0].name == "level"
        assert s.fields[0].spec.kind is TypeKind.INT
        assert s.fields[0].col_idx == 4
        assert s.fields[1].name == "display_name"
        assert s.fields[1].spec.kind is TypeKind.STRING
        assert len(s.rows) == 2
        assert s.rows[0].cells["id"] == 1
        assert s.rows[0].cells["level"] == 1
        assert s.rows[0].cells["display_name"] == "Slime"

    def test_enum_and_list_types(self, tmp_path):
        path = make_xlsx(
            tmp_path,
            {
                "X": [
                    ["_export", "id", "sub_id", "cat", "tags"],
                    ["Int", "Int", "Int", "Enum(A,B,C)", "List(String)"],
                    [1, 1, None, "B", "{x,y,z}"],
                ]
            },
        )
        sheets = read_workbook(path)
        s = sheets[0]
        assert s.fields[0].spec.kind is TypeKind.ENUM
        assert s.fields[0].spec.enum_values == ("A", "B", "C")
        assert s.fields[1].spec.kind is TypeKind.LIST_STRING

    def test_ignore_column(self, tmp_path):
        path = make_xlsx(
            tmp_path,
            {
                "X": [
                    ["_export", "id", "sub_id", "v", "note"],
                    ["Int", "Int", "Int", "Int", "Ignore"],
                    [1, 1, None, 10, "策划备注"],
                ]
            },
        )
        sheets = read_workbook(path)
        s = sheets[0]
        # Ignore 列仍要收入 fields（聚合器决定是否输出）
        assert len(s.fields) == 2
        assert s.fields[1].name == "note"
        assert s.fields[1].spec.is_ignore


# ---------------------------------------------------------------------------
# 前三列校验
# ---------------------------------------------------------------------------


class TestFixedColumnWarnings:
    def test_fixed_col_names_ok(self, tmp_path):
        path = make_xlsx(
            tmp_path,
            {
                "X": [
                    ["_export", "id", "sub_id", "v"],
                    ["Int", "Int", "Int", "Int"],
                    [1, 1, None, 5],
                ]
            },
        )
        s = read_workbook(path)[0]
        assert s.fixed_col_warnings == []

    def test_wrong_fixed_col_name(self, tmp_path):
        path = make_xlsx(
            tmp_path,
            {
                "X": [
                    ["export", "ID", "subId", "v"],  # 全错
                    ["Int", "Int", "Int", "Int"],
                    [1, 1, None, 5],
                ]
            },
        )
        s = read_workbook(path)[0]
        # 3 个 Warning（_export/id/sub_id 都不对）
        names_wrong = [w for w in s.fixed_col_warnings if w.row_idx == 1]
        assert len(names_wrong) == 3

    def test_wrong_fixed_col_type(self, tmp_path):
        path = make_xlsx(
            tmp_path,
            {
                "X": [
                    ["_export", "id", "sub_id", "v"],
                    ["Int", "String", "String", "Int"],  # id/sub_id 类型错
                    [1, 1, None, 5],
                ]
            },
        )
        s = read_workbook(path)[0]
        types_wrong = [w for w in s.fixed_col_warnings if w.row_idx == 2]
        assert len(types_wrong) == 2


# ---------------------------------------------------------------------------
# 类型行错误
# ---------------------------------------------------------------------------


class TestTypeRowErrors:
    def test_unknown_type_literal(self, tmp_path):
        path = make_xlsx(
            tmp_path,
            {
                "X": [
                    ["_export", "id", "sub_id", "v"],
                    ["Int", "Int", "Int", "Bool"],
                    [1, 1, None, "true"],
                ]
            },
        )
        s = read_workbook(path)[0]
        # 该字段不会进入 fields，但产生 header_issue
        assert len(s.fields) == 0
        assert len(s.header_issues) == 1
        assert "类型行非法" in s.header_issues[0].reason

    def test_field_name_empty(self, tmp_path):
        path = make_xlsx(
            tmp_path,
            {
                "X": [
                    ["_export", "id", "sub_id", "", "v2"],
                    ["Int", "Int", "Int", "Int", "Int"],
                    [1, 1, None, 5, 10],
                ]
            },
        )
        s = read_workbook(path)[0]
        # D 列字段名空但类型不为空 → header issue
        assert len(s.header_issues) >= 1
        # v2 仍然解析成功
        assert any(f.name == "v2" for f in s.fields)

    def test_trailing_empty_columns_ok(self, tmp_path):
        # 字段名和类型全空的尾部列应被跳过，不报错
        path = make_xlsx(
            tmp_path,
            {
                "X": [
                    ["_export", "id", "sub_id", "v", None, None],
                    ["Int", "Int", "Int", "Int", None, None],
                    [1, 1, None, 5, None, None],
                ]
            },
        )
        s = read_workbook(path)[0]
        assert len(s.header_issues) == 0
        assert len(s.fields) == 1


# ---------------------------------------------------------------------------
# 数据行
# ---------------------------------------------------------------------------


class TestDataRows:
    def test_empty_row_skipped(self, tmp_path):
        path = make_xlsx(
            tmp_path,
            {
                "X": [
                    ["_export", "id", "sub_id", "v"],
                    ["Int", "Int", "Int", "Int"],
                    [1, 1, None, 10],
                    [None, None, None, None],  # 全空行
                    [1, 2, None, 20],
                ]
            },
        )
        s = read_workbook(path)[0]
        assert len(s.rows) == 2
        assert s.rows[0].cells["id"] == 1
        assert s.rows[1].cells["id"] == 2

    def test_multiple_sheets(self, tmp_path):
        path = make_xlsx(
            tmp_path,
            {
                "A": [
                    ["_export", "id", "sub_id", "v"],
                    ["Int", "Int", "Int", "Int"],
                    [1, 1, None, 10],
                ],
                "B": [
                    ["_export", "id", "sub_id", "name"],
                    ["Int", "Int", "Int", "String"],
                    [1, 1, None, "hello"],
                ],
            },
        )
        sheets = read_workbook(path)
        assert len(sheets) == 2
        assert {s.sheet_name for s in sheets} == {"A", "B"}


# ---------------------------------------------------------------------------
# 端到端：read + aggregate
# ---------------------------------------------------------------------------


class TestEndToEndReadAggregate:
    """sheet_reader + aggregator 联合 round-trip。"""

    def test_growth_table_roundtrip(self, tmp_path):
        from core.aggregator import aggregate_sheet

        path = make_xlsx(
            tmp_path,
            {
                "Growth": [
                    ["_export", "id", "sub_id", "attribute", "base_value", "per_level"],
                    ["Int", "Int", "Int", "String", "Float", "Float"],
                    [1, 1001, 1, "max_health", 30.0, 5.0],
                    [1, 1001, 2, "max_health", 30.0, 8.0],
                    [1, 1001, 3, "attack", 5.0, 1.0],
                    [1, 2001, 1, "max_health", 200.0, 50.0],
                ]
            },
        )
        sheets = read_workbook(path)
        agg, errors = aggregate_sheet(sheets[0])
        assert errors == []
        assert agg.id_order == [1001, 2001]
        assert len(agg.records[1001].sub_entries) == 3
        assert agg.records[1001].sub_entries[0]["sub_id"] == 1
        assert agg.records[1001].sub_entries[0]["attribute"] == "max_health"
        assert len(agg.records[2001].sub_entries) == 1
