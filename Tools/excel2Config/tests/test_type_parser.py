"""type_parser 单元测试。"""
from __future__ import annotations

import pytest

from core.type_parser import (
    ParseError,
    TypeKind,
    TypeLiteralError,
    TypeSpec,
    default_value,
    parse_cell,
    parse_export_flag,
    parse_id,
    parse_sub_id,
    parse_type_literal,
)


# ---------------------------------------------------------------------------
# parse_type_literal
# ---------------------------------------------------------------------------


class TestParseTypeLiteral:
    @pytest.mark.parametrize(
        "literal, kind",
        [
            ("Int", TypeKind.INT),
            ("Float", TypeKind.FLOAT),
            ("String", TypeKind.STRING),
            ("Ignore", TypeKind.IGNORE),
        ],
    )
    def test_scalar(self, literal, kind):
        spec = parse_type_literal(literal)
        assert spec.kind is kind

    def test_enum(self):
        spec = parse_type_literal("Enum(Normal,Elite,Boss)")
        assert spec.kind is TypeKind.ENUM
        assert spec.enum_values == ("Normal", "Elite", "Boss")

    def test_enum_with_spaces(self):
        spec = parse_type_literal("Enum(  A , B , C  )")
        assert spec.enum_values == ("A", "B", "C")

    def test_enum_empty_raises(self):
        with pytest.raises(TypeLiteralError):
            parse_type_literal("Enum()")

    def test_enum_duplicate_raises(self):
        with pytest.raises(TypeLiteralError):
            parse_type_literal("Enum(A,B,A)")

    @pytest.mark.parametrize(
        "literal, kind, inner",
        [
            ("List(Int)", TypeKind.LIST_INT, TypeKind.INT),
            ("List(Float)", TypeKind.LIST_FLOAT, TypeKind.FLOAT),
            ("List(String)", TypeKind.LIST_STRING, TypeKind.STRING),
        ],
    )
    def test_list(self, literal, kind, inner):
        spec = parse_type_literal(literal)
        assert spec.kind is kind
        assert spec.list_inner is inner
        assert spec.is_list

    def test_nested_list_rejected(self):
        with pytest.raises(TypeLiteralError):
            parse_type_literal("List(List(Int))")

    def test_unknown_literal_rejected(self):
        with pytest.raises(TypeLiteralError):
            parse_type_literal("Bool")
        with pytest.raises(TypeLiteralError):
            parse_type_literal("StringName")
        with pytest.raises(TypeLiteralError):
            parse_type_literal("random_thing")

    def test_empty_raises(self):
        with pytest.raises(TypeLiteralError):
            parse_type_literal(None)
        with pytest.raises(TypeLiteralError):
            parse_type_literal("")
        with pytest.raises(TypeLiteralError):
            parse_type_literal("   ")


# ---------------------------------------------------------------------------
# default_value
# ---------------------------------------------------------------------------


class TestDefaultValue:
    def test_int_default(self):
        assert default_value(parse_type_literal("Int")) == 0

    def test_float_default(self):
        assert default_value(parse_type_literal("Float")) == 0.0

    def test_string_default(self):
        assert default_value(parse_type_literal("String")) == ""

    def test_enum_default_is_first(self):
        spec = parse_type_literal("Enum(Normal,Elite,Boss)")
        assert default_value(spec) == "Normal"

    @pytest.mark.parametrize("literal", ["List(Int)", "List(Float)", "List(String)"])
    def test_list_default_is_empty(self, literal):
        assert default_value(parse_type_literal(literal)) == []

    def test_ignore_default_is_none(self):
        assert default_value(parse_type_literal("Ignore")) is None


# ---------------------------------------------------------------------------
# parse_cell
# ---------------------------------------------------------------------------


class TestParseCellInt:
    spec = TypeSpec(kind=TypeKind.INT, raw="Int")

    def test_blank_to_default(self):
        v, err = parse_cell(self.spec, None)
        assert v == 0 and err is None
        v, err = parse_cell(self.spec, "")
        assert v == 0 and err is None
        v, err = parse_cell(self.spec, "  ")
        assert v == 0 and err is None

    def test_int(self):
        v, err = parse_cell(self.spec, 5)
        assert v == 5 and err is None

    def test_negative_int(self):
        v, err = parse_cell(self.spec, -3)
        assert v == -3 and err is None

    def test_float_with_integer_value(self):
        # openpyxl 经常把整数读成 float
        v, err = parse_cell(self.spec, 5.0)
        assert v == 5 and err is None

    def test_non_integer_float_rejected(self):
        v, err = parse_cell(self.spec, 5.5)
        assert v is None and isinstance(err, ParseError)

    def test_string_number(self):
        v, err = parse_cell(self.spec, "42")
        assert v == 42 and err is None

    def test_string_with_dot_zero(self):
        v, err = parse_cell(self.spec, "5.0")
        assert v == 5 and err is None

    def test_letter_rejected(self):
        v, err = parse_cell(self.spec, "abc")
        assert v is None and isinstance(err, ParseError)

    def test_bool_rejected(self):
        v, err = parse_cell(self.spec, True)
        assert v is None and isinstance(err, ParseError)


class TestParseCellFloat:
    spec = TypeSpec(kind=TypeKind.FLOAT, raw="Float")

    def test_blank_to_default(self):
        v, err = parse_cell(self.spec, None)
        assert v == 0.0 and err is None

    def test_float(self):
        v, err = parse_cell(self.spec, 3.14)
        assert v == 3.14 and err is None

    def test_int_promoted(self):
        v, err = parse_cell(self.spec, 5)
        assert v == 5.0 and err is None
        assert isinstance(v, float)

    def test_string_float(self):
        v, err = parse_cell(self.spec, "-0.5")
        assert v == -0.5 and err is None

    def test_letter_rejected(self):
        v, err = parse_cell(self.spec, "xyz")
        assert v is None and isinstance(err, ParseError)


class TestParseCellString:
    spec = TypeSpec(kind=TypeKind.STRING, raw="String")

    def test_blank_to_default(self):
        v, err = parse_cell(self.spec, None)
        assert v == "" and err is None

    def test_string(self):
        v, err = parse_cell(self.spec, "Slime")
        assert v == "Slime" and err is None

    def test_integer_float_to_int_string(self):
        # openpyxl 5 → 5.0；String 列要写成 "5" 而不是 "5.0"
        v, err = parse_cell(self.spec, 5.0)
        assert v == "5" and err is None

    def test_real_float_kept(self):
        v, err = parse_cell(self.spec, 3.14)
        assert v == "3.14" and err is None


class TestParseCellEnum:
    spec = TypeSpec(
        kind=TypeKind.ENUM,
        enum_values=("Normal", "Elite", "Boss"),
        raw="Enum(Normal,Elite,Boss)",
    )

    def test_blank_to_first(self):
        v, err = parse_cell(self.spec, None)
        assert v == "Normal" and err is None

    def test_valid(self):
        v, err = parse_cell(self.spec, "Elite")
        assert v == "Elite" and err is None

    def test_strip_whitespace(self):
        v, err = parse_cell(self.spec, "  Boss  ")
        assert v == "Boss" and err is None

    def test_invalid_value(self):
        v, err = parse_cell(self.spec, "Mythic")
        assert v is None and isinstance(err, ParseError)


class TestParseCellList:
    int_spec = TypeSpec(
        kind=TypeKind.LIST_INT, list_inner=TypeKind.INT, raw="List(Int)"
    )
    float_spec = TypeSpec(
        kind=TypeKind.LIST_FLOAT, list_inner=TypeKind.FLOAT, raw="List(Float)"
    )
    str_spec = TypeSpec(
        kind=TypeKind.LIST_STRING, list_inner=TypeKind.STRING, raw="List(String)"
    )

    def test_blank_to_empty(self):
        v, err = parse_cell(self.int_spec, None)
        assert v == [] and err is None

    def test_empty_braces(self):
        v, err = parse_cell(self.int_spec, "{}")
        assert v == [] and err is None

    def test_int_list(self):
        v, err = parse_cell(self.int_spec, "{1,2,3}")
        assert v == [1, 2, 3] and err is None

    def test_int_list_with_spaces(self):
        v, err = parse_cell(self.int_spec, "{ 1 , 2 , 3 }")
        assert v == [1, 2, 3] and err is None

    def test_float_list(self):
        v, err = parse_cell(self.float_spec, "{1.5,2.5}")
        assert v == [1.5, 2.5] and err is None

    def test_string_list(self):
        v, err = parse_cell(self.str_spec, "{hello,world}")
        assert v == ["hello", "world"] and err is None

    def test_empty_tokens_become_defaults(self):
        v, err = parse_cell(self.int_spec, "{,,}")
        assert v == [0, 0, 0] and err is None
        v, err = parse_cell(self.str_spec, "{,,}")
        assert v == ["", "", ""] and err is None

    def test_missing_braces_rejected(self):
        v, err = parse_cell(self.int_spec, "1,2,3")
        assert v is None and isinstance(err, ParseError)

    def test_only_open_brace_rejected(self):
        v, err = parse_cell(self.int_spec, "{1,2,3")
        assert v is None and isinstance(err, ParseError)

    def test_wrong_inner_type_rejected(self):
        v, err = parse_cell(self.int_spec, "{1,abc,3}")
        assert v is None and isinstance(err, ParseError)


class TestParseCellIgnore:
    spec = TypeSpec(kind=TypeKind.IGNORE, raw="Ignore")

    def test_always_none(self):
        v, err = parse_cell(self.spec, "anything")
        assert v is None and err is None
        v, err = parse_cell(self.spec, None)
        assert v is None and err is None


# ---------------------------------------------------------------------------
# 前三列专用解析
# ---------------------------------------------------------------------------


class TestParseExportFlag:
    def test_0(self):
        v, err = parse_export_flag(0)
        assert v == 0 and err is None

    def test_1(self):
        v, err = parse_export_flag(1)
        assert v == 1 and err is None

    def test_string_form(self):
        v, err = parse_export_flag("1")
        assert v == 1 and err is None

    def test_blank_rejected(self):
        v, err = parse_export_flag(None)
        assert v is None and isinstance(err, ParseError)
        v, err = parse_export_flag("")
        assert v is None and isinstance(err, ParseError)

    def test_other_int_rejected(self):
        v, err = parse_export_flag(2)
        assert v is None and isinstance(err, ParseError)

    def test_non_int_rejected(self):
        v, err = parse_export_flag("yes")
        assert v is None and isinstance(err, ParseError)


class TestParseId:
    def test_positive_int(self):
        v, err = parse_id(5)
        assert v == 5 and err is None

    def test_negative_int(self):
        # 负 id 当前规约下也允许（仅禁 0 和空）
        v, err = parse_id(-1)
        assert v == -1 and err is None

    def test_zero_rejected(self):
        v, err = parse_id(0)
        assert v is None and isinstance(err, ParseError)

    def test_blank_rejected(self):
        v, err = parse_id(None)
        assert v is None and isinstance(err, ParseError)

    def test_letter_rejected(self):
        v, err = parse_id("abc")
        assert v is None and isinstance(err, ParseError)


class TestParseSubId:
    def test_blank_is_main_row(self):
        # 留空表示主行：返回 (None, None)
        v, err = parse_sub_id(None)
        assert v is None and err is None
        v, err = parse_sub_id("")
        assert v is None and err is None
        v, err = parse_sub_id("  ")
        assert v is None and err is None

    def test_positive_int(self):
        v, err = parse_sub_id(3)
        assert v == 3 and err is None

    def test_zero_rejected(self):
        v, err = parse_sub_id(0)
        assert v is None and isinstance(err, ParseError)

    def test_non_int_rejected(self):
        v, err = parse_sub_id("xyz")
        assert v is None and isinstance(err, ParseError)
