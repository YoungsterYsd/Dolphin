"""类型字面量解析 + 单元格值校验/转换。

类型词表（详见 Plans/三期开发计划.md M10.2）：
    Int
    Float
    String
    Enum(v1,v2,...)
    List(Int) | List(Float) | List(String)
    Ignore

单元格留空 → 取类型默认值（Int=0, Float=0.0, String="", Enum=v1, List=[]）。
类型不匹配 → 返回 ParseError（不抛异常，供 fail-collect 校验器收集）。

固定列说明（前三列由调用方处理，不走 parse_type_literal）：
    _export 列：Int + 严格 0/1
    id 列    ：Int + 非空非 0
    sub_id 列：Int + 可空（空=主行）+ 非 0
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Optional


# ---------------------------------------------------------------------------
# 类型种类枚举
# ---------------------------------------------------------------------------


class TypeKind(str, Enum):
    INT = "Int"
    FLOAT = "Float"
    STRING = "String"
    ENUM = "Enum"
    LIST_INT = "List(Int)"
    LIST_FLOAT = "List(Float)"
    LIST_STRING = "List(String)"
    IGNORE = "Ignore"


# ---------------------------------------------------------------------------
# TypeSpec：类型行解析后的结构化结果
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class TypeSpec:
    """单列的类型规约。"""

    kind: TypeKind
    # Enum 词表（按 Excel 中声明顺序保留）
    enum_values: tuple[str, ...] = field(default_factory=tuple)
    # List 的内部元素类型（仅 LIST_* 时有意义）：TypeKind.INT / FLOAT / STRING
    list_inner: Optional[TypeKind] = None
    # 原始类型字面量（用于错误信息）
    raw: str = ""

    @property
    def is_ignore(self) -> bool:
        return self.kind is TypeKind.IGNORE

    @property
    def is_list(self) -> bool:
        return self.kind in (TypeKind.LIST_INT, TypeKind.LIST_FLOAT, TypeKind.LIST_STRING)


# ---------------------------------------------------------------------------
# 错误结构
# ---------------------------------------------------------------------------


class TypeLiteralError(ValueError):
    """类型行字面量写错时抛出（fail-fast 类，因为整张 sheet 都解析不动）。"""


@dataclass
class ParseError:
    """单元格解析错误。fail-collect 风格，调用方收集后批量上报。"""

    reason: str
    raw_value: Any
    type_literal: str

    def __str__(self) -> str:  # pragma: no cover - 仅诊断
        return f"{self.reason} (raw={self.raw_value!r}, type={self.type_literal})"


# ---------------------------------------------------------------------------
# 类型字面量解析
# ---------------------------------------------------------------------------


_SCALAR_KINDS: dict[str, TypeKind] = {
    "Int": TypeKind.INT,
    "Float": TypeKind.FLOAT,
    "String": TypeKind.STRING,
    "Ignore": TypeKind.IGNORE,
}

_LIST_INNER_MAP: dict[str, TypeKind] = {
    "Int": TypeKind.INT,
    "Float": TypeKind.FLOAT,
    "String": TypeKind.STRING,
}

_LIST_KIND_MAP: dict[TypeKind, TypeKind] = {
    TypeKind.INT: TypeKind.LIST_INT,
    TypeKind.FLOAT: TypeKind.LIST_FLOAT,
    TypeKind.STRING: TypeKind.LIST_STRING,
}


def parse_type_literal(literal: Any) -> TypeSpec:
    """解析类型行单元格的字面量字符串为 TypeSpec。

    支持：
        Int / Float / String / Ignore
        Enum(v1,v2,...)
        List(Int) / List(Float) / List(String)

    其它写法（含 Bool / StringName / List(List(Int)) 等）抛 TypeLiteralError。
    """
    if literal is None:
        raise TypeLiteralError("类型行不允许留空")
    raw = str(literal).strip()
    if not raw:
        raise TypeLiteralError("类型行不允许留空")

    # 标量
    if raw in _SCALAR_KINDS:
        return TypeSpec(kind=_SCALAR_KINDS[raw], raw=raw)

    # Enum(...)
    if raw.startswith("Enum(") and raw.endswith(")"):
        inner = raw[len("Enum(") : -1]
        values = tuple(v.strip() for v in inner.split(",") if v.strip())
        if not values:
            raise TypeLiteralError(f"Enum 词表为空：{raw}")
        # Enum 值不允许重复
        if len(set(values)) != len(values):
            raise TypeLiteralError(f"Enum 词表存在重复值：{raw}")
        return TypeSpec(kind=TypeKind.ENUM, enum_values=values, raw=raw)

    # List(Inner)
    if raw.startswith("List(") and raw.endswith(")"):
        inner = raw[len("List(") : -1].strip()
        if inner not in _LIST_INNER_MAP:
            raise TypeLiteralError(
                f"List 内部类型仅支持 Int / Float / String，实际：{raw}"
            )
        inner_kind = _LIST_INNER_MAP[inner]
        return TypeSpec(
            kind=_LIST_KIND_MAP[inner_kind],
            list_inner=inner_kind,
            raw=raw,
        )

    raise TypeLiteralError(f"未知类型字面量：{raw!r}")


# ---------------------------------------------------------------------------
# 默认值
# ---------------------------------------------------------------------------


def default_value(spec: TypeSpec) -> Any:
    """返回类型对应的"单元格留空时"默认值。"""
    if spec.kind is TypeKind.INT:
        return 0
    if spec.kind is TypeKind.FLOAT:
        return 0.0
    if spec.kind is TypeKind.STRING:
        return ""
    if spec.kind is TypeKind.ENUM:
        # 词表第一项
        return spec.enum_values[0] if spec.enum_values else ""
    if spec.is_list:
        return []
    if spec.kind is TypeKind.IGNORE:
        return None
    raise AssertionError(f"unreachable kind={spec.kind!r}")  # pragma: no cover


# ---------------------------------------------------------------------------
# 单元格值解析
# ---------------------------------------------------------------------------


def _is_blank(raw: Any) -> bool:
    """判断单元格是否为空（None 或全空白字符串）。"""
    if raw is None:
        return True
    if isinstance(raw, str) and raw.strip() == "":
        return True
    return False


def _parse_int(raw: Any) -> Optional[int]:
    """尝试把 raw 转为 int。失败返回 None。

    接受：
        - Python int（openpyxl 数字单元格）
        - Python float 但实际是整数（如 5.0）
        - 数字字符串（"5"、"-3"、" 5 "）
    拒绝：
        - 真小数（1.5）
        - bool（虽然 isinstance(bool, int) 为 True，但语义上不属于）
        - 任何非数字字符串
    """
    if isinstance(raw, bool):
        return None
    if isinstance(raw, int):
        return raw
    if isinstance(raw, float):
        if raw.is_integer():
            return int(raw)
        return None
    if isinstance(raw, str):
        s = raw.strip()
        if not s:
            return None
        try:
            return int(s)
        except ValueError:
            # 兼容 "5.0" 这种字符串
            try:
                f = float(s)
            except ValueError:
                return None
            if f.is_integer():
                return int(f)
            return None
    return None


def _parse_float(raw: Any) -> Optional[float]:
    if isinstance(raw, bool):
        return None
    if isinstance(raw, (int, float)):
        return float(raw)
    if isinstance(raw, str):
        s = raw.strip()
        if not s:
            return None
        try:
            return float(s)
        except ValueError:
            return None
    return None


def _parse_list_payload(raw: Any) -> Optional[list[str]]:
    """解析 `{a,b,c}` → ['a', 'b', 'c']。

    返回 None 表示格式错误（缺括号 / 非字符串）。
    `{}` → []
    `{,,}` → ['', '', '']
    """
    if not isinstance(raw, str):
        return None
    s = raw.strip()
    if not (s.startswith("{") and s.endswith("}")):
        return None
    inner = s[1:-1]
    if inner == "":
        return []
    # 注意：保留空项；strip 每个 token 的首尾空白
    return [tok.strip() for tok in inner.split(",")]


def parse_cell(spec: TypeSpec, raw: Any) -> tuple[Any, Optional[ParseError]]:
    """按 spec 解析单元格值。

    返回 (value, error)：
        - 解析成功：(value, None)
        - 留空：(default_value, None)
        - 类型不匹配：(None, ParseError)
    """
    if spec.is_ignore:
        return (None, None)

    if _is_blank(raw):
        return (default_value(spec), None)

    if spec.kind is TypeKind.INT:
        v = _parse_int(raw)
        if v is None:
            return (None, ParseError("Int 类型不匹配", raw, spec.raw))
        return (v, None)

    if spec.kind is TypeKind.FLOAT:
        v = _parse_float(raw)
        if v is None:
            return (None, ParseError("Float 类型不匹配", raw, spec.raw))
        return (v, None)

    if spec.kind is TypeKind.STRING:
        # 任何非空值都转字符串；数字也按字符串保留（如 "1.0" 写入 String 列）
        if isinstance(raw, float) and raw.is_integer():
            # openpyxl 把整数也读成 float；String 列要保留可读形式
            return (str(int(raw)), None)
        return (str(raw), None)

    if spec.kind is TypeKind.ENUM:
        s = str(raw).strip()
        if s not in spec.enum_values:
            return (
                None,
                ParseError(
                    f"Enum 值不在词表 {list(spec.enum_values)}", raw, spec.raw
                ),
            )
        return (s, None)

    if spec.is_list:
        tokens = _parse_list_payload(raw)
        if tokens is None:
            return (
                None,
                ParseError("List 格式错误：必须用大括号 `{a,b,c}`", raw, spec.raw),
            )

        inner = spec.list_inner
        out: list[Any] = []
        for tok in tokens:
            # 空 token 走该类型默认值（如 {,,} → [0,0,0] 或 ["","",""]）
            if tok == "":
                if inner is TypeKind.INT:
                    out.append(0)
                elif inner is TypeKind.FLOAT:
                    out.append(0.0)
                else:  # STRING
                    out.append("")
                continue
            if inner is TypeKind.INT:
                v = _parse_int(tok)
                if v is None:
                    return (
                        None,
                        ParseError(
                            f"List(Int) 内部元素不是整型：{tok!r}", raw, spec.raw
                        ),
                    )
                out.append(v)
            elif inner is TypeKind.FLOAT:
                v = _parse_float(tok)
                if v is None:
                    return (
                        None,
                        ParseError(
                            f"List(Float) 内部元素不是浮点：{tok!r}", raw, spec.raw
                        ),
                    )
                out.append(v)
            else:  # STRING：原样保留
                out.append(tok)
        return (out, None)

    raise AssertionError(f"unreachable kind={spec.kind!r}")  # pragma: no cover


# ---------------------------------------------------------------------------
# 前三列专用解析（供 sheet_reader 复用）
# ---------------------------------------------------------------------------


def parse_export_flag(raw: Any) -> tuple[Optional[int], Optional[ParseError]]:
    """A 列 _export：严格 0/1，不允许空。"""
    if _is_blank(raw):
        return (None, ParseError("_export 不允许留空", raw, "Int"))
    v = _parse_int(raw)
    if v is None or v not in (0, 1):
        return (None, ParseError("_export 必须是 0 或 1", raw, "Int"))
    return (v, None)


def parse_id(raw: Any) -> tuple[Optional[int], Optional[ParseError]]:
    """B 列 id：Int + 非空 + 非 0。"""
    if _is_blank(raw):
        return (None, ParseError("id 不允许留空", raw, "Int"))
    v = _parse_int(raw)
    if v is None:
        return (None, ParseError("id 必须是 Int", raw, "Int"))
    if v == 0:
        return (None, ParseError("id 不允许为 0", raw, "Int"))
    return (v, None)


def parse_sub_id(raw: Any) -> tuple[Optional[int], Optional[ParseError]]:
    """C 列 sub_id：Int + 留空（=主行） + 非 0。

    返回 (value_or_None, error_or_None)：
        - 留空：(None, None) —— None 表示主行
        - 非空非 0 的 Int：(int_value, None)
        - 0 / 非 Int：(None, ParseError)
    """
    if _is_blank(raw):
        return (None, None)
    v = _parse_int(raw)
    if v is None:
        return (None, ParseError("sub_id 必须是 Int", raw, "Int"))
    if v == 0:
        return (None, ParseError("sub_id 不允许为 0（留空表达主行）", raw, "Int"))
    return (v, None)
