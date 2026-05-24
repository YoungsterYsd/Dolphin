"""按 sheet 输出 .json。

约定（详见 Plans/三期开发计划.md M10.3「输出约定」）：
- 每张 sheet 输出 1 个 `<output_dir>/<sheet_name>.json`
- 顶级是字典，key = id 字符串化
- value 是该 id 的记录，含 sub_entries: [...]
- 不写元信息（_meta）
- 2 空格缩进，UTF-8 无 BOM，行尾 LF
- id key 按数值升序排序（保证重复跑 git diff 稳定）
- Float 用 repr() 等价写出（避免 1.1 输出成 1.0999999999...）
"""
from __future__ import annotations

import json
from pathlib import Path

from .aggregator import AggregatedSheet
from .validator import SheetResult, ValidationResult


# ---------------------------------------------------------------------------
# 单张 sheet 落盘
# ---------------------------------------------------------------------------


def build_json_payload(agg: AggregatedSheet) -> dict[str, dict]:
    """把 AggregatedSheet 转为顶级 JSON 对象。

    返回值是一个普通 dict，已按 id 升序排好；调用方再 json.dump。
    """
    payload: dict[str, dict] = {}
    for id_val in agg.id_order:
        rec = agg.records[id_val]
        payload[str(id_val)] = rec.to_json_value()
    return payload


def write_sheet(agg: AggregatedSheet, output_dir: str | Path) -> Path:
    """把单张 sheet 的聚合结果写为 .json，返回文件路径。

    若 sheet 没有任何记录（全被 _export=0 过滤掉），仍然写空字典 `{}`。
    """
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    out_path = output_dir / f"{agg.sheet_name}.json"

    payload = build_json_payload(agg)
    # 关键：sort_keys=False 是为了保留我们自己排好的升序（json.dump 默认按字符串排
    # 会把 "100" 排到 "2" 前面，错；我们已用 id_order 数值升序，直接 dump）
    text = json.dumps(
        payload,
        ensure_ascii=False,
        indent=2,
        sort_keys=False,
    )
    # 强制 LF 行尾
    text = text.replace("\r\n", "\n")
    # 写文件时用 newline="" 防止 Windows 自动转 CRLF
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
        f.write("\n")  # 文件末尾保留一个换行（POSIX 习惯）
    return out_path


# ---------------------------------------------------------------------------
# 批量落盘
# ---------------------------------------------------------------------------


def write_all(
    result: ValidationResult,
    output_dir: str | Path,
    *,
    skip_errored: bool = True,
) -> list[Path]:
    """把 ValidationResult 中所有 sheet 的聚合结果落盘。

    skip_errored=True 时：跳过含 error 的 sheet（不写出可能不完整的数据）
    skip_errored=False 时：所有 sheet 都写（部分数据；可用于调试）
    """
    output_dir = Path(output_dir)
    written: list[Path] = []
    for sr in result.sheets:
        if skip_errored and not sr.is_clean:
            continue
        if sr.sheet_name == "<workbook>":
            # 占位错误项，无聚合数据可写
            continue
        out_path = write_sheet(sr.agg, output_dir)
        written.append(out_path)
    return written
