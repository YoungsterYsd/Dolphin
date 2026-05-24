"""aggregator 单元测试。直接手工构造 RawSheet，跳过 openpyxl 依赖。"""
from __future__ import annotations

import pytest

from core.aggregator import (
    AggregatedRecord,
    AggregatedSheet,
    SheetError,
    aggregate_sheet,
)
from core.sheet_reader import FieldDef, RawRow, RawSheet
from core.type_parser import TypeKind, TypeSpec, parse_type_literal


# ---------------------------------------------------------------------------
# Fixture 构造器
# ---------------------------------------------------------------------------


def make_field(name: str, type_literal: str, col_idx: int) -> FieldDef:
    return FieldDef(name=name, spec=parse_type_literal(type_literal), col_idx=col_idx)


def make_sheet(
    name: str,
    fields: list[FieldDef],
    rows: list[tuple[int, dict]],
) -> RawSheet:
    """rows 是 [(row_idx, cells_dict), ...]"""
    sheet = RawSheet(sheet_name=name, source_file="<test>")
    sheet.fields = fields
    sheet.rows = [RawRow(row_idx=ri, cells=cells) for ri, cells in rows]
    return sheet


# ---------------------------------------------------------------------------
# 正常聚合
# ---------------------------------------------------------------------------


class TestSimpleAggregation:
    def test_single_main_row(self):
        sheet = make_sheet(
            "Characters",
            [
                make_field("level", "Int", 4),
                make_field("display_name", "String", 5),
            ],
            [
                (
                    3,
                    {
                        "_export": 1,
                        "id": 1,
                        "sub_id": None,
                        "level": 1,
                        "display_name": "Slime",
                    },
                ),
            ],
        )
        agg, errors = aggregate_sheet(sheet)
        assert errors == []
        assert agg.id_order == [1]
        rec = agg.records[1]
        assert rec.fields == {"level": 1, "display_name": "Slime"}
        assert rec.sub_entries == []
        assert rec.has_main_row

    def test_multiple_records(self):
        sheet = make_sheet(
            "Characters",
            [make_field("level", "Int", 4)],
            [
                (3, {"_export": 1, "id": 1, "sub_id": None, "level": 1}),
                (4, {"_export": 1, "id": 2, "sub_id": None, "level": 5}),
                (5, {"_export": 1, "id": 100, "sub_id": None, "level": 1}),
            ],
        )
        agg, errors = aggregate_sheet(sheet)
        assert errors == []
        assert agg.id_order == [1, 2, 100]  # 升序

    def test_export_zero_skipped(self):
        sheet = make_sheet(
            "S",
            [make_field("v", "Int", 4)],
            [
                (3, {"_export": 1, "id": 1, "sub_id": None, "v": 10}),
                (4, {"_export": 0, "id": 2, "sub_id": None, "v": 20}),
            ],
        )
        agg, errors = aggregate_sheet(sheet)
        assert errors == []
        assert agg.id_order == [1]


# ---------------------------------------------------------------------------
# 子项聚合（方案 A）
# ---------------------------------------------------------------------------


class TestSubEntryAggregation:
    def test_main_plus_subs(self):
        sheet = make_sheet(
            "Growth",
            [
                make_field("attribute", "String", 4),
                make_field("base_value", "Float", 5),
            ],
            [
                (3, {"_export": 1, "id": 1001, "sub_id": None, "attribute": "", "base_value": 0.0}),
                (4, {"_export": 1, "id": 1001, "sub_id": 1, "attribute": "max_health", "base_value": 30.0}),
                (5, {"_export": 1, "id": 1001, "sub_id": 2, "attribute": "attack", "base_value": 5.0}),
            ],
        )
        agg, errors = aggregate_sheet(sheet)
        assert errors == []
        rec = agg.records[1001]
        assert rec.has_main_row
        assert len(rec.sub_entries) == 2
        assert rec.sub_entries[0]["sub_id"] == 1
        assert rec.sub_entries[0]["attribute"] == "max_health"
        assert rec.sub_entries[1]["sub_id"] == 2
        assert rec.sub_entries[1]["attribute"] == "attack"

    def test_missing_main_row_uses_defaults(self):
        # 只有子行没有主行 —— 顶级字段应被填默认值
        sheet = make_sheet(
            "Growth",
            [
                make_field("attribute", "String", 4),
                make_field("base_value", "Float", 5),
            ],
            [
                (3, {"_export": 1, "id": 1001, "sub_id": 1, "attribute": "max_health", "base_value": 30.0}),
                (4, {"_export": 1, "id": 1001, "sub_id": 2, "attribute": "attack", "base_value": 5.0}),
            ],
        )
        agg, errors = aggregate_sheet(sheet)
        assert errors == []
        rec = agg.records[1001]
        assert not rec.has_main_row
        # 默认值：String="" / Float=0.0
        assert rec.fields == {"attribute": "", "base_value": 0.0}
        assert len(rec.sub_entries) == 2

    def test_sub_entries_sorted_by_sub_id(self):
        # 乱序输入 —— 输出应升序
        sheet = make_sheet(
            "X",
            [make_field("v", "Int", 4)],
            [
                (3, {"_export": 1, "id": 1, "sub_id": 5, "v": 50}),
                (4, {"_export": 1, "id": 1, "sub_id": 1, "v": 10}),
                (5, {"_export": 1, "id": 1, "sub_id": 3, "v": 30}),
            ],
        )
        agg, errors = aggregate_sheet(sheet)
        assert errors == []
        rec = agg.records[1]
        sub_ids = [e["sub_id"] for e in rec.sub_entries]
        assert sub_ids == [1, 3, 5]


# ---------------------------------------------------------------------------
# 联合键冲突
# ---------------------------------------------------------------------------


class TestUnionKeyConflict:
    def test_duplicate_main_row(self):
        sheet = make_sheet(
            "X",
            [make_field("v", "Int", 4)],
            [
                (3, {"_export": 1, "id": 1, "sub_id": None, "v": 1}),
                (4, {"_export": 1, "id": 1, "sub_id": None, "v": 2}),
            ],
        )
        agg, errors = aggregate_sheet(sheet)
        assert len(errors) == 1
        assert "联合主键重复" in errors[0].reason
        assert errors[0].row_idx == 4
        # 第二行被拒绝；id=1 record 应使用第一行的数据
        assert agg.records[1].fields == {"v": 1}

    def test_duplicate_sub_row(self):
        sheet = make_sheet(
            "X",
            [make_field("v", "Int", 4)],
            [
                (3, {"_export": 1, "id": 1, "sub_id": 1, "v": 10}),
                (4, {"_export": 1, "id": 1, "sub_id": 1, "v": 20}),
            ],
        )
        agg, errors = aggregate_sheet(sheet)
        assert len(errors) == 1
        assert "联合主键重复" in errors[0].reason
        # 仅第一行子项应该被收
        assert len(agg.records[1].sub_entries) == 1
        assert agg.records[1].sub_entries[0]["v"] == 10

    def test_different_subs_no_conflict(self):
        sheet = make_sheet(
            "X",
            [make_field("v", "Int", 4)],
            [
                (3, {"_export": 1, "id": 1, "sub_id": 1, "v": 10}),
                (4, {"_export": 1, "id": 1, "sub_id": 2, "v": 20}),
            ],
        )
        agg, errors = aggregate_sheet(sheet)
        assert errors == []


# ---------------------------------------------------------------------------
# 前三列错误
# ---------------------------------------------------------------------------


class TestFixedColumnErrors:
    def test_export_invalid(self):
        sheet = make_sheet(
            "X",
            [make_field("v", "Int", 4)],
            [
                (3, {"_export": 2, "id": 1, "sub_id": None, "v": 10}),
            ],
        )
        agg, errors = aggregate_sheet(sheet)
        assert len(errors) == 1
        assert errors[0].column_name == "_export"
        assert agg.records == {}

    def test_id_zero(self):
        sheet = make_sheet(
            "X",
            [make_field("v", "Int", 4)],
            [
                (3, {"_export": 1, "id": 0, "sub_id": None, "v": 10}),
            ],
        )
        agg, errors = aggregate_sheet(sheet)
        assert len(errors) == 1
        assert errors[0].column_name == "id"
        assert agg.records == {}

    def test_sub_id_zero(self):
        sheet = make_sheet(
            "X",
            [make_field("v", "Int", 4)],
            [
                (3, {"_export": 1, "id": 1, "sub_id": 0, "v": 10}),
            ],
        )
        agg, errors = aggregate_sheet(sheet)
        assert len(errors) == 1
        assert errors[0].column_name == "sub_id"


# ---------------------------------------------------------------------------
# 用户字段错误（fail-collect 验证）
# ---------------------------------------------------------------------------


class TestUserFieldErrors:
    def test_int_type_mismatch_collects_error(self):
        sheet = make_sheet(
            "X",
            [
                make_field("level", "Int", 4),
                make_field("name", "String", 5),
            ],
            [
                (3, {"_export": 1, "id": 1, "sub_id": None, "level": "abc", "name": "Slime"}),
            ],
        )
        agg, errors = aggregate_sheet(sheet)
        assert len(errors) == 1
        assert errors[0].column_name == "level"
        # 该行因有错被拒绝
        assert 1 not in agg.records

    def test_multiple_errors_collected(self):
        # 5 个错误同时存在，aggregator 应全收
        sheet = make_sheet(
            "X",
            [
                make_field("n", "Int", 4),
                make_field("e", "Enum(A,B,C)", 5),
                make_field("l", "List(Int)", 6),
            ],
            [
                (3, {"_export": 2, "id": 1, "sub_id": None, "n": 1, "e": "A", "l": "{1}"}),  # export err
                (4, {"_export": 1, "id": 0, "sub_id": None, "n": 1, "e": "A", "l": "{1}"}),  # id=0
                (5, {"_export": 1, "id": 2, "sub_id": None, "n": "abc", "e": "X", "l": "{a}"}),  # 3 字段错
            ],
        )
        agg, errors = aggregate_sheet(sheet)
        # 至少 5 个错：1(export)+1(id)+3(field)
        assert len(errors) >= 5

    def test_ignore_column_skipped(self):
        sheet = make_sheet(
            "X",
            [
                make_field("v", "Int", 4),
                make_field("note", "Ignore", 5),
            ],
            [
                (3, {"_export": 1, "id": 1, "sub_id": None, "v": 10, "note": "策划备注"}),
            ],
        )
        agg, errors = aggregate_sheet(sheet)
        assert errors == []
        # Ignore 列不进入聚合输出
        assert agg.records[1].fields == {"v": 10}
