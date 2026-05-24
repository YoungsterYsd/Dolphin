"""CLI 集成测试：convert / validate 子命令。"""
from __future__ import annotations

import json
from pathlib import Path

from click.testing import CliRunner
from openpyxl import Workbook

from main import cli


def _make_xlsx(tmp_path, sheets, name="t.xlsx"):
    wb = Workbook()
    wb.remove(wb.active)
    for sname, rows in sheets.items():
        ws = wb.create_sheet(title=sname)
        for r in rows:
            ws.append(r)
    path = tmp_path / name
    wb.save(path)
    return path


class TestCLIConvert:
    def test_convert_clean(self, tmp_path):
        xlsx = _make_xlsx(
            tmp_path,
            {
                "Characters": [
                    ["_export", "id", "sub_id", "level"],
                    ["Int", "Int", "Int", "Int"],
                    [1, 1, None, 1],
                ]
            },
        )
        out = tmp_path / "gen"
        runner = CliRunner()
        result = runner.invoke(
            cli, ["convert", "-i", str(xlsx), "-o", str(out)]
        )
        assert result.exit_code == 0, result.output
        assert (out / "Characters.json").exists()
        data = json.loads((out / "Characters.json").read_text(encoding="utf-8"))
        assert data == {"1": {"level": 1, "sub_entries": []}}

    def test_convert_with_errors_returns_1(self, tmp_path):
        xlsx = _make_xlsx(
            tmp_path,
            {
                "X": [
                    ["_export", "id", "sub_id", "v"],
                    ["Int", "Int", "Int", "Int"],
                    [1, 0, None, 1],  # id=0 → error
                ]
            },
        )
        out = tmp_path / "gen"
        runner = CliRunner()
        result = runner.invoke(cli, ["convert", "-i", str(xlsx), "-o", str(out)])
        assert result.exit_code == 1
        assert not (out / "X.json").exists()

    def test_only_filter(self, tmp_path):
        xlsx = _make_xlsx(
            tmp_path,
            {
                "A": [["_export", "id", "sub_id", "v"], ["Int", "Int", "Int", "Int"], [1, 1, None, 1]],
                "B": [["_export", "id", "sub_id", "v"], ["Int", "Int", "Int", "Int"], [1, 1, None, 2]],
            },
        )
        out = tmp_path / "gen"
        runner = CliRunner()
        result = runner.invoke(
            cli, ["convert", "-i", str(xlsx), "-o", str(out), "--only", "B"]
        )
        assert result.exit_code == 0
        assert (out / "B.json").exists()
        assert not (out / "A.json").exists()


class TestCLIValidate:
    def test_validate_clean(self, tmp_path):
        xlsx = _make_xlsx(
            tmp_path,
            {"X": [["_export", "id", "sub_id", "v"], ["Int", "Int", "Int", "Int"], [1, 1, None, 1]]},
        )
        runner = CliRunner()
        result = runner.invoke(cli, ["validate", "-i", str(xlsx)])
        assert result.exit_code == 0

    def test_validate_with_errors(self, tmp_path):
        xlsx = _make_xlsx(
            tmp_path,
            {"X": [["_export", "id", "sub_id", "v"], ["Int", "Int", "Int", "Int"], [1, 0, None, 1]]},
        )
        runner = CliRunner()
        result = runner.invoke(cli, ["validate", "-i", str(xlsx)])
        assert result.exit_code == 1


class TestCLIEndToEndGrowth:
    """模拟 M10.3 验收：Growth sheet 完整 round-trip。"""

    def test_growth_table_round_trip(self, tmp_path):
        xlsx = _make_xlsx(
            tmp_path,
            {
                "Growth": [
                    ["_export", "id", "sub_id", "attribute", "base_value", "per_level_delta"],
                    ["Int", "Int", "Int", "String", "Float", "Float"],
                    [1, 1001, 1, "max_health", 30.0, 5.0],
                    [1, 1001, 2, "max_health", 30.0, 8.0],
                    [1, 1001, 3, "attack", 5.0, 1.0],
                    [1, 2001, 1, "max_health", 200.0, 50.0],
                ]
            },
        )
        out = tmp_path / "gen"
        runner = CliRunner()
        result = runner.invoke(cli, ["convert", "-i", str(xlsx), "-o", str(out)])
        assert result.exit_code == 0
        data = json.loads((out / "Growth.json").read_text(encoding="utf-8"))
        assert list(data.keys()) == ["1001", "2001"]
        assert len(data["1001"]["sub_entries"]) == 3
        assert data["1001"]["sub_entries"][0]["attribute"] == "max_health"
        assert data["2001"]["sub_entries"][0]["base_value"] == 200.0
