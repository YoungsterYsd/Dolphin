"""按 id groupby + sub_id 聚合（方案 A）。

输入：RawSheet（含 fields 与 raw rows）
输出：AggregatedSheet（每个 id 一条 record）+ errors 列表

聚合规则（详见 Plans/三期开发计划.md M10.2「子 id 聚合规则」）：
- 同 id 多行；sub_id 留空的是主行（提供顶级字段）；sub_id 非空的是子行（进 sub_entries）
- 主行可缺省：无主行时用类型默认值补齐顶级字段
- (id, sub_id) 联合键全表唯一
- 子行的字段：除主行专属字段外都收进 sub_entries[i]
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from .sheet_reader import FieldDef, RawSheet
from .type_parser import (
    ParseError,
    TypeKind,
    default_value,
    parse_cell,
    parse_export_flag,
    parse_id,
    parse_sub_id,
)


# ---------------------------------------------------------------------------
# 错误数据结构
# ---------------------------------------------------------------------------


@dataclass
class SheetError:
    """聚合阶段产生的错误（fail-collect 收集）。"""

    sheet_name: str
    row_idx: int  # 1-based
    col_idx: int  # 1-based；0 表示行级错误（如联合键冲突）
    column_name: str  # 字段名；空表示行级
    reason: str
    raw_value: Any = None

    def format(self) -> str:
        loc = f"{self.sheet_name}!"
        loc += f"row {self.row_idx}"
        if self.col_idx > 0:
            loc += f", col {self.col_idx} ({self.column_name})"
        return f"[{loc}] {self.reason}" + (
            f" | raw={self.raw_value!r}" if self.raw_value is not None else ""
        )


# ---------------------------------------------------------------------------
# 聚合输出
# ---------------------------------------------------------------------------


@dataclass
class AggregatedRecord:
    """单个 id 的聚合记录。"""

    id: int
    fields: dict[str, Any] = field(default_factory=dict)  # 顶级字段（来自主行）
    sub_entries: list[dict[str, Any]] = field(default_factory=list)  # 子项数组
    has_main_row: bool = False  # 是否出现过主行（用于诊断）

    def to_json_value(self) -> dict[str, Any]:
        """转为 JSON 输出形式。"""
        out: dict[str, Any] = dict(self.fields)
        out["sub_entries"] = self.sub_entries
        return out


@dataclass
class AggregatedSheet:
    """单张 sheet 的聚合结果。"""

    sheet_name: str
    records: dict[int, AggregatedRecord] = field(default_factory=dict)  # id → 记录
    # 输出顺序：按 id 升序输出（json_writer 会用）
    id_order: list[int] = field(default_factory=list)


# ---------------------------------------------------------------------------
# 聚合入口
# ---------------------------------------------------------------------------


def aggregate_sheet(
    raw: RawSheet,
) -> tuple[AggregatedSheet, list[SheetError]]:
    """聚合单张 sheet。返回 (聚合结果, 错误列表)。"""
    agg = AggregatedSheet(sheet_name=raw.sheet_name)
    errors: list[SheetError] = []

    # 用户字段（排除 Ignore）
    user_fields = [f for f in raw.fields if not f.spec.is_ignore]

    # 联合键去重：(id, sub_id_or_None) → first_row_idx
    seen_keys: dict[tuple[int, int | None], int] = {}

    for raw_row in raw.rows:
        row_idx = raw_row.row_idx

        # --- 解析前三列 ---
        export_val, export_err = parse_export_flag(raw_row.cells.get("_export"))
        if export_err is not None:
            errors.append(
                SheetError(
                    sheet_name=raw.sheet_name,
                    row_idx=row_idx,
                    col_idx=1,
                    column_name="_export",
                    reason=export_err.reason,
                    raw_value=export_err.raw_value,
                )
            )
            # _export 错时跳过该行（无法判定是否导出）
            continue

        if export_val == 0:
            # 草稿行，跳过
            continue

        id_val, id_err = parse_id(raw_row.cells.get("id"))
        if id_err is not None:
            errors.append(
                SheetError(
                    sheet_name=raw.sheet_name,
                    row_idx=row_idx,
                    col_idx=2,
                    column_name="id",
                    reason=id_err.reason,
                    raw_value=id_err.raw_value,
                )
            )
            continue

        sub_id_val, sub_id_err = parse_sub_id(raw_row.cells.get("sub_id"))
        if sub_id_err is not None:
            errors.append(
                SheetError(
                    sheet_name=raw.sheet_name,
                    row_idx=row_idx,
                    col_idx=3,
                    column_name="sub_id",
                    reason=sub_id_err.reason,
                    raw_value=sub_id_err.raw_value,
                )
            )
            continue

        # --- 联合键冲突 ---
        key = (id_val, sub_id_val)
        if key in seen_keys:
            prev_row = seen_keys[key]
            sub_id_desc = "(主行)" if sub_id_val is None else f"sub_id={sub_id_val}"
            errors.append(
                SheetError(
                    sheet_name=raw.sheet_name,
                    row_idx=row_idx,
                    col_idx=0,
                    column_name="",
                    reason=(
                        f"(id, sub_id) 联合主键重复：id={id_val} {sub_id_desc}"
                        f"（首次出现于 row {prev_row}）"
                    ),
                )
            )
            # 不 continue：仍然解析数据用于后续可能的检查；但不写入 record
            duplicate_key = True
        else:
            seen_keys[key] = row_idx
            duplicate_key = False

        # --- 解析用户字段 ---
        parsed_cells: dict[str, Any] = {}
        row_has_field_error = False
        for fdef in user_fields:
            raw_cell = raw_row.cells.get(fdef.name)
            value, err = parse_cell(fdef.spec, raw_cell)
            if err is not None:
                errors.append(
                    SheetError(
                        sheet_name=raw.sheet_name,
                        row_idx=row_idx,
                        col_idx=fdef.col_idx,
                        column_name=fdef.name,
                        reason=err.reason,
                        raw_value=err.raw_value,
                    )
                )
                row_has_field_error = True
                continue
            parsed_cells[fdef.name] = value

        if duplicate_key or row_has_field_error:
            # 该行有错；不写入聚合 record，避免污染输出
            continue

        # --- 写入聚合 record ---
        rec = agg.records.get(id_val)
        if rec is None:
            rec = AggregatedRecord(id=id_val)
            agg.records[id_val] = rec
            agg.id_order.append(id_val)

        if sub_id_val is None:
            # 主行：顶级字段
            rec.fields = parsed_cells
            rec.has_main_row = True
        else:
            # 子行：sub_id 字段放第一位，便于阅读
            sub_entry = {"sub_id": sub_id_val}
            sub_entry.update(parsed_cells)
            rec.sub_entries.append(sub_entry)

    # --- 主行缺省补齐：用类型默认值 ---
    for id_val, rec in agg.records.items():
        if not rec.has_main_row:
            rec.fields = {
                fdef.name: default_value(fdef.spec) for fdef in user_fields
            }

    # --- 排序：id 升序，子项按 sub_id 升序 ---
    agg.id_order.sort()
    for rec in agg.records.values():
        rec.sub_entries.sort(key=lambda e: e.get("sub_id", 0))

    return agg, errors
