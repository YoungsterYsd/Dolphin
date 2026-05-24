"""按 sheet 输出 .csv（与 json_writer 并列的另一种导出格式）。

约定：
- 每张 sheet 输出 1 个 `<output_dir>/<sheet_name>.csv`
- 表头行 = `id, sub_id, <user_field_1>, <user_field_2>, ...`
- 主行 `sub_id` 列留空；子行 `sub_id` 列填具体值
- 主行的顶级字段写一行；每个 sub_entry 再写一行（顶级字段会重复主行的值，
  方便策划在 Excel 里直接看到「这条 sub 属于哪条主记录」）
- List 序列化为 `{a,b,c}`，与 Excel 单元格写法一致
- Float 用 repr() 等价写出
- 编码：UTF-8 with BOM（让 Windows Excel 双击直接打开能识别中文）
- 行尾：CRLF（csv 标准）；分隔符：`,`
"""
from __future__ import annotations

import csv
from pathlib import Path
from typing import Any

from .aggregator import AggregatedRecord, AggregatedSheet
from .sheet_reader import RawSheet
from .validator import ValidationResult


# ---------------------------------------------------------------------------
# 序列化辅助
# ---------------------------------------------------------------------------


def _format_cell(value: Any) -> str:
    """把单个字段值序列化为 CSV 单元格文本。

    - None         → "" （空单元格）
    - bool         → "1"/"0"（_export 不会进来；但保留以防未来扩展）
    - int          → str(int)
    - float        → repr(float)（避免 1.1 → 1.0999...）
    - str          → 原字符串
    - list         → {item1,item2,...}（与 Excel 单元格写法一致）
    """
    if value is None:
        return ""
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, list):
        inner = ",".join(_format_cell(v) for v in value)
        return "{" + inner + "}"
    return str(value)


def _user_field_names(agg: AggregatedSheet) -> list[str]:
    """从聚合结果反推用户字段名顺序（保持 Excel 中 D 列起的顺序）。

    aggregator 已经把字段按声明顺序写进 record.fields；我们以「第一个有 fields
    的 record」为准；都没有时退化为子项里 sub_id 之外的并集。
    """
    for rec in agg.records.values():
        if rec.fields:
            return list(rec.fields.keys())
    # 兜底：从 sub_entries 收集（去掉 sub_id）
    seen: list[str] = []
    for rec in agg.records.values():
        for sub in rec.sub_entries:
            for k in sub.keys():
                if k != "sub_id" and k not in seen:
                    seen.append(k)
    return seen


# ---------------------------------------------------------------------------
# 单张 sheet 落盘
# ---------------------------------------------------------------------------


def write_sheet_csv(agg: AggregatedSheet, output_dir: str | Path) -> Path:
    """把单张 sheet 的聚合结果写为 .csv，返回文件路径。

    若该 sheet 没有任何记录，仍然写一个只有表头的 CSV。
    """
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    out_path = output_dir / f"{agg.sheet_name}.csv"

    user_fields = _user_field_names(agg)
    header = ["id", "sub_id", *user_fields]

    # 用 utf-8-sig 写入 BOM；newline="" 让 csv 模块按 dialect 控制行尾
    with open(out_path, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f, dialect="excel")  # excel = 逗号分隔 + CRLF
        writer.writerow(header)

        for id_val in agg.id_order:
            rec = agg.records[id_val]
            # 主行
            main_row = [str(id_val), ""]
            for fname in user_fields:
                main_row.append(_format_cell(rec.fields.get(fname)))
            writer.writerow(main_row)

            # 子行（按 sub_id 升序，aggregator 已排过序）
            for sub in rec.sub_entries:
                sub_id = sub.get("sub_id")
                sub_row = [str(id_val), _format_cell(sub_id)]
                for fname in user_fields:
                    # 子行的字段：优先用子行自己写过的；否则 fallback 到主行
                    if fname in sub:
                        sub_row.append(_format_cell(sub[fname]))
                    else:
                        sub_row.append(_format_cell(rec.fields.get(fname)))
                writer.writerow(sub_row)

    return out_path


# ---------------------------------------------------------------------------
# 批量落盘
# ---------------------------------------------------------------------------


def write_all_csv(
    result: ValidationResult,
    output_dir: str | Path,
    *,
    skip_errored: bool = True,
) -> list[Path]:
    """把 ValidationResult 中所有 sheet 的聚合结果写为 .csv。"""
    output_dir = Path(output_dir)
    written: list[Path] = []
    for sr in result.sheets:
        if skip_errored and not sr.is_clean:
            continue
        if sr.sheet_name == "<workbook>":
            continue
        out_path = write_sheet_csv(sr.agg, output_dir)
        written.append(out_path)
    return written
