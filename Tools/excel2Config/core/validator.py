"""顶层校验入口：fail-collect 编排器。

把 sheet_reader → aggregator 串起来，对一组 .xlsx 文件做完整扫描：
- 收集所有错误（任意一个 sheet 任意一行）
- 收集所有警告（前三列名称/类型错位等）
- 不在这里写文件；由 main/gui 决定是否调用 json_writer 落盘
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from .aggregator import AggregatedSheet, SheetError, aggregate_sheet
from .sheet_reader import HeaderIssue, RawSheet, read_workbook


# ---------------------------------------------------------------------------
# 警告 / 结果数据结构
# ---------------------------------------------------------------------------


@dataclass
class SheetWarning:
    """非阻断的警告。"""

    sheet_name: str
    row_idx: int
    col_idx: int
    reason: str
    source_file: str = ""

    def format(self) -> str:
        loc = ""
        if self.source_file:
            loc += f"{Path(self.source_file).name}::"
        loc += f"{self.sheet_name}!row {self.row_idx}, col {self.col_idx}"
        return f"[{loc}] {self.reason}"


@dataclass
class SheetResult:
    """单张 sheet 的完整结果。"""

    sheet_name: str
    source_file: str
    raw: RawSheet
    agg: AggregatedSheet
    errors: list[SheetError] = field(default_factory=list)
    warnings: list[SheetWarning] = field(default_factory=list)

    @property
    def is_clean(self) -> bool:
        return len(self.errors) == 0


@dataclass
class ValidationResult:
    """整次扫描的汇总结果。"""

    sheets: list[SheetResult] = field(default_factory=list)

    @property
    def all_errors(self) -> list[SheetError]:
        return [e for s in self.sheets for e in s.errors]

    @property
    def all_warnings(self) -> list[SheetWarning]:
        return [w for s in self.sheets for w in s.warnings]

    @property
    def is_clean(self) -> bool:
        return all(s.is_clean for s in self.sheets)

    def summary(self) -> str:
        n_sheets = len(self.sheets)
        n_rows = sum(len(s.agg.records) for s in self.sheets)
        n_err = len(self.all_errors)
        n_warn = len(self.all_warnings)
        return (
            f"扫描完成：{n_sheets} sheets, {n_rows} records, "
            f"{n_err} errors, {n_warn} warnings"
        )


# ---------------------------------------------------------------------------
# 顶层入口
# ---------------------------------------------------------------------------


def validate_paths(
    paths: list[str | Path],
    *,
    only_sheet: str | None = None,
) -> ValidationResult:
    """对多个 .xlsx 路径做扫描。

    paths 元素可以是文件或目录：
        - 目录：递归找 *.xlsx
        - 文件：直接处理
    only_sheet 非空时仅处理同名 sheet（多文件中第一个匹配的）。
    """
    xlsx_files = _expand_paths(paths)
    result = ValidationResult()
    already_done_for_only: set[str] = set()

    for xlsx_path in xlsx_files:
        try:
            raw_sheets = read_workbook(xlsx_path)
        except Exception as e:  # pragma: no cover - 罕见，由调用方报告
            # 把 read_workbook 的异常包装为单条错误，但不阻断整体扫描
            err = SheetError(
                sheet_name="<workbook>",
                row_idx=0,
                col_idx=0,
                column_name="",
                reason=f"无法打开 xlsx：{e}",
            )
            placeholder = SheetResult(
                sheet_name="<workbook>",
                source_file=str(xlsx_path),
                raw=RawSheet(sheet_name="<workbook>", source_file=str(xlsx_path)),
                agg=AggregatedSheet(sheet_name="<workbook>"),
                errors=[err],
            )
            result.sheets.append(placeholder)
            continue

        for raw in raw_sheets:
            if only_sheet is not None and raw.sheet_name != only_sheet:
                continue
            if only_sheet is not None and only_sheet in already_done_for_only:
                continue

            sr = _process_one_sheet(raw, str(xlsx_path))
            result.sheets.append(sr)
            if only_sheet is not None:
                already_done_for_only.add(only_sheet)
                break

    return result


def _process_one_sheet(raw: RawSheet, source_file: str) -> SheetResult:
    """单张 sheet 走 header 校验 + 聚合。"""
    warnings: list[SheetWarning] = []
    errors: list[SheetError] = []

    # 前三列 Warning
    for iss in raw.fixed_col_warnings:
        warnings.append(
            SheetWarning(
                sheet_name=raw.sheet_name,
                row_idx=iss.row_idx,
                col_idx=iss.col_idx,
                reason=iss.reason,
                source_file=source_file,
            )
        )

    # header_issues：用户字段名/类型错误 → Error
    for iss in raw.header_issues:
        errors.append(
            SheetError(
                sheet_name=raw.sheet_name,
                row_idx=iss.row_idx,
                col_idx=iss.col_idx,
                column_name="",
                reason=iss.reason,
            )
        )

    # 聚合（即使有 header_issue，已成功解析的字段也能继续聚合）
    agg, agg_errors = aggregate_sheet(raw)
    errors.extend(agg_errors)

    return SheetResult(
        sheet_name=raw.sheet_name,
        source_file=source_file,
        raw=raw,
        agg=agg,
        errors=errors,
        warnings=warnings,
    )


# ---------------------------------------------------------------------------
# Path 展开
# ---------------------------------------------------------------------------


def _expand_paths(paths: list[str | Path]) -> list[Path]:
    """把 paths 展开为具体的 .xlsx 文件列表（去重、按字典序排序，保证稳定）。"""
    out: set[Path] = set()
    for p in paths:
        path = Path(p)
        if not path.exists():
            # 缺失路径在上层会被忽略；此处不动声色，让调用方靠 result 判断
            continue
        if path.is_dir():
            for f in path.rglob("*.xlsx"):
                # 跳过 Excel 临时文件 ~$xxx.xlsx
                if f.name.startswith("~$"):
                    continue
                out.add(f.resolve())
        elif path.suffix.lower() == ".xlsx" and not path.name.startswith("~$"):
            out.add(path.resolve())
    return sorted(out)
