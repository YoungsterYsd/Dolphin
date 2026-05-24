"""Excel → JSON / CSV 转换工具 CLI 入口。

用法：
    python main.py convert -i ../Excel/ -o ../../Data/FromExcel/Generated/
    python main.py convert -i ../Excel/Combat.xlsx --format csv
    python main.py convert -i ../Excel/ --format both
    python main.py convert -i ../Excel/ --path-map mapping.json
    python main.py validate -i ../Excel/

`mapping.json` 格式（与 GUI 的 .last_session.json `path_mappings` 字段一致）：
    [
      {"pattern": "Combat.json", "output_dir": "Data/Combat/Generated"},
      {"pattern": "*.csv",       "output_dir": "Data/Excel_CSV"}
    ]

退出码：
    0  全部 clean（或仅有 warning）
    1  存在 error
    2  CLI 参数错误（click 自动处理）
"""
from __future__ import annotations

import json
import sys
from fnmatch import fnmatchcase
from pathlib import Path

import click

from core.csv_writer import write_sheet_csv
from core.json_writer import write_sheet
from core.validator import ValidationResult, validate_paths


DEFAULT_OUTPUT = Path("Data/FromExcel")

FMT_JSON = "json"
FMT_CSV = "csv"
FMT_BOTH = "both"
FORMAT_CHOICES = (FMT_JSON, FMT_CSV, FMT_BOTH)


# ---------------------------------------------------------------------------
# 日志打印（带 ANSI 颜色）
# ---------------------------------------------------------------------------


def _echo_summary(result: ValidationResult) -> None:
    click.echo(result.summary())


def _echo_warnings(result: ValidationResult) -> None:
    for w in result.all_warnings:
        click.secho(f"[WARN]  {w.format()}", fg="yellow")


def _echo_errors(result: ValidationResult) -> None:
    for e in result.all_errors:
        sheet_result = next(
            (sr for sr in result.sheets if sr.sheet_name == e.sheet_name), None
        )
        prefix = ""
        if sheet_result and sheet_result.source_file:
            prefix = f"{Path(sheet_result.source_file).name}::"
        click.secho(f"[ERROR] {prefix}{e.format()}", fg="red")


def _echo_sheet_stats(result: ValidationResult) -> None:
    for sr in result.sheets:
        if sr.sheet_name == "<workbook>":
            continue
        n_rows = len(sr.agg.records)
        n_subs = sum(len(r.sub_entries) for r in sr.agg.records.values())
        msg = (
            f"[INFO]  {Path(sr.source_file).name}::{sr.sheet_name} "
            f"→ {n_rows} records, {n_subs} sub-entries"
        )
        click.secho(msg, fg=None)


# ---------------------------------------------------------------------------
# 路径映射
# ---------------------------------------------------------------------------


def _load_path_mappings(path: Path | None) -> list[dict]:
    if path is None:
        return []
    try:
        # utf-8-sig 同时兼容带 BOM（Windows 记事本/PowerShell Out-File）和不带 BOM
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as e:
        click.secho(f"[ERROR] 读取 path-map 失败：{e}", fg="red")
        sys.exit(2)
    if not isinstance(data, list):
        click.secho("[ERROR] path-map 必须是 JSON 数组。", fg="red")
        sys.exit(2)
    out: list[dict] = []
    for m in data:
        if (
            isinstance(m, dict)
            and isinstance(m.get("pattern"), str)
            and isinstance(m.get("output_dir"), str)
        ):
            out.append({"pattern": m["pattern"], "output_dir": m["output_dir"]})
    return out


def _resolve_output_dir(
    file_name: str, default_dir: Path, mappings: list[dict]
) -> Path:
    for m in mappings:
        if m["pattern"] == file_name:
            return Path(m["output_dir"])
    for m in mappings:
        if fnmatchcase(file_name, m["pattern"]):
            return Path(m["output_dir"])
    return default_dir


# ---------------------------------------------------------------------------
# CLI 命令组
# ---------------------------------------------------------------------------


@click.group()
@click.version_option(version="0.2.0")
def cli() -> None:
    """Dolphin Excel → JSON / CSV 配置转换工具。"""


@cli.command("convert")
@click.option(
    "-i", "--input", "input_paths",
    multiple=True, required=True,
    type=click.Path(exists=True, path_type=Path),
    help="输入 .xlsx 文件或目录（可多次指定）。",
)
@click.option(
    "-o", "--output", "output_dir",
    type=click.Path(path_type=Path),
    default=DEFAULT_OUTPUT, show_default=True,
    help="默认输出目录（被 --path-map 命中时会被覆盖）。",
)
@click.option(
    "-f", "--format", "fmt",
    type=click.Choice(FORMAT_CHOICES, case_sensitive=False),
    default=FMT_JSON, show_default=True,
    help="导出格式：json / csv / both。",
)
@click.option(
    "--path-map", "path_map",
    type=click.Path(exists=True, dir_okay=False, path_type=Path),
    default=None,
    help="JSON 文件，按文件名规则把指定输出文件路由到特定目录。",
)
@click.option(
    "--only", "only_sheet",
    default=None,
    help="仅转换指定 sheet 名（多文件中匹配第一个）。",
)
@click.option(
    "--force", is_flag=True, default=False,
    help="即使存在错误也写出已成功的 sheet（默认有错则不写）。",
)
def cmd_convert(
    input_paths: tuple[Path, ...],
    output_dir: Path,
    fmt: str,
    path_map: Path | None,
    only_sheet: str | None,
    force: bool,
) -> None:
    """扫描输入并写出 .json / .csv 到输出目录。"""
    fmt = fmt.lower()
    mappings = _load_path_mappings(path_map)

    result = validate_paths(list(input_paths), only_sheet=only_sheet)

    _echo_sheet_stats(result)
    _echo_warnings(result)
    _echo_errors(result)
    _echo_summary(result)

    if not result.is_clean and not force:
        click.secho(
            "存在错误：未写出任何文件（如需强制写出，加 --force）。", fg="red"
        )
        sys.exit(1)

    want_json = fmt in (FMT_JSON, FMT_BOTH)
    want_csv = fmt in (FMT_CSV, FMT_BOTH)

    written: list[Path] = []
    for sr in result.sheets:
        if sr.sheet_name == "<workbook>":
            continue
        if not sr.is_clean and not force:
            continue
        agg = sr.agg
        if want_json:
            target = _resolve_output_dir(
                f"{agg.sheet_name}.json", output_dir, mappings
            )
            written.append(write_sheet(agg, target))
        if want_csv:
            target = _resolve_output_dir(
                f"{agg.sheet_name}.csv", output_dir, mappings
            )
            written.append(write_sheet_csv(agg, target))

    click.secho(f"已写出 {len(written)} 个文件（格式：{fmt}）", fg="green")
    for p in written:
        click.echo(f"  {p}")

    sys.exit(0 if result.is_clean else 1)


@cli.command("validate")
@click.option(
    "-i", "--input", "input_paths",
    multiple=True, required=True,
    type=click.Path(exists=True, path_type=Path),
    help="输入 .xlsx 文件或目录（可多次指定）。",
)
@click.option(
    "--only", "only_sheet",
    default=None,
    help="仅校验指定 sheet 名。",
)
def cmd_validate(
    input_paths: tuple[Path, ...],
    only_sheet: str | None,
) -> None:
    """仅校验，不写文件。"""
    result = validate_paths(list(input_paths), only_sheet=only_sheet)
    _echo_sheet_stats(result)
    _echo_warnings(result)
    _echo_errors(result)
    _echo_summary(result)
    sys.exit(0 if result.is_clean else 1)


if __name__ == "__main__":
    cli()
