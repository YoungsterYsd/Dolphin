"""json_writer 单测。重点：输出可复现 + 字节级稳定。"""
from __future__ import annotations

import json
from pathlib import Path

from openpyxl import Workbook

from core.json_writer import build_json_payload, write_all, write_sheet
from core.validator import validate_paths


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


class TestBuildPayload:
    def test_id_keys_are_strings(self, tmp_path):
        p = _make_xlsx(
            tmp_path,
            {
                "X": [
                    ["_export", "id", "sub_id", "v"],
                    ["Int", "Int", "Int", "Int"],
                    [1, 1, None, 10],
                    [1, 100, None, 20],
                ]
            },
        )
        result = validate_paths([p])
        payload = build_json_payload(result.sheets[0].agg)
        assert set(payload.keys()) == {"1", "100"}

    def test_id_keys_in_ascending_numeric_order(self, tmp_path):
        # 即使 Excel 行序乱，输出 key 也按数值升序（"2" 在 "100" 之前）
        p = _make_xlsx(
            tmp_path,
            {
                "X": [
                    ["_export", "id", "sub_id", "v"],
                    ["Int", "Int", "Int", "Int"],
                    [1, 100, None, 1],
                    [1, 2, None, 2],
                    [1, 50, None, 3],
                ]
            },
        )
        result = validate_paths([p])
        payload = build_json_payload(result.sheets[0].agg)
        assert list(payload.keys()) == ["2", "50", "100"]

    def test_sub_entries_present(self, tmp_path):
        p = _make_xlsx(
            tmp_path,
            {
                "Growth": [
                    ["_export", "id", "sub_id", "v"],
                    ["Int", "Int", "Int", "Float"],
                    [1, 1001, 1, 30.0],
                    [1, 1001, 2, 8.0],
                ]
            },
        )
        result = validate_paths([p])
        payload = build_json_payload(result.sheets[0].agg)
        rec = payload["1001"]
        assert "sub_entries" in rec
        assert len(rec["sub_entries"]) == 2
        assert rec["sub_entries"][0]["sub_id"] == 1


class TestWriteSheet:
    def test_file_created_with_correct_name(self, tmp_path):
        p = _make_xlsx(
            tmp_path,
            {
                "Characters": [
                    ["_export", "id", "sub_id", "v"],
                    ["Int", "Int", "Int", "Int"],
                    [1, 1, None, 10],
                ]
            },
        )
        result = validate_paths([p])
        out_dir = tmp_path / "out"
        out_path = write_sheet(result.sheets[0].agg, out_dir)
        assert out_path.exists()
        assert out_path.name == "Characters.json"

    def test_json_content_round_trip(self, tmp_path):
        p = _make_xlsx(
            tmp_path,
            {
                "X": [
                    ["_export", "id", "sub_id", "v", "f"],
                    ["Int", "Int", "Int", "Int", "Float"],
                    [1, 1, None, 10, 1.5],
                ]
            },
        )
        result = validate_paths([p])
        out_dir = tmp_path / "out"
        out_path = write_sheet(result.sheets[0].agg, out_dir)
        data = json.loads(out_path.read_text(encoding="utf-8"))
        assert data == {"1": {"v": 10, "f": 1.5, "sub_entries": []}}

    def test_byte_level_stability_across_runs(self, tmp_path):
        """重复跑两次 → 输出字节级一致（防 git diff 抖动）。"""
        p = _make_xlsx(
            tmp_path,
            {
                "X": [
                    ["_export", "id", "sub_id", "v"],
                    ["Int", "Int", "Int", "Float"],
                    [1, 3, None, 1.1],
                    [1, 1, None, 2.2],
                    [1, 100, None, 3.3],
                ]
            },
        )
        out_dir = tmp_path / "out"

        result1 = validate_paths([p])
        path1 = write_sheet(result1.sheets[0].agg, out_dir)
        bytes1 = path1.read_bytes()

        result2 = validate_paths([p])
        path2 = write_sheet(result2.sheets[0].agg, out_dir)
        bytes2 = path2.read_bytes()

        assert bytes1 == bytes2

    def test_lf_line_ending(self, tmp_path):
        p = _make_xlsx(
            tmp_path,
            {"X": [["_export", "id", "sub_id", "v"], ["Int", "Int", "Int", "Int"], [1, 1, None, 1]]},
        )
        result = validate_paths([p])
        out_dir = tmp_path / "out"
        out_path = write_sheet(result.sheets[0].agg, out_dir)
        raw = out_path.read_bytes()
        # 不应该出现 CRLF
        assert b"\r\n" not in raw
        # 应该有 LF
        assert b"\n" in raw

    def test_unicode_preserved(self, tmp_path):
        p = _make_xlsx(
            tmp_path,
            {
                "X": [
                    ["_export", "id", "sub_id", "name"],
                    ["Int", "Int", "Int", "String"],
                    [1, 1, None, "史莱姆"],
                ]
            },
        )
        result = validate_paths([p])
        out_dir = tmp_path / "out"
        out_path = write_sheet(result.sheets[0].agg, out_dir)
        text = out_path.read_text(encoding="utf-8")
        # 中文应该原样出现（ensure_ascii=False）
        assert "史莱姆" in text


class TestWriteAll:
    def test_skip_errored_sheets(self, tmp_path):
        # 一个干净 sheet + 一个有错的 sheet
        p = _make_xlsx(
            tmp_path,
            {
                "Good": [
                    ["_export", "id", "sub_id", "v"],
                    ["Int", "Int", "Int", "Int"],
                    [1, 1, None, 10],
                ],
                "Bad": [
                    ["_export", "id", "sub_id", "v"],
                    ["Int", "Int", "Int", "Int"],
                    [1, 0, None, 10],  # id=0 → Error
                ],
            },
        )
        result = validate_paths([p])
        out_dir = tmp_path / "out"
        written = write_all(result, out_dir, skip_errored=True)
        assert len(written) == 1
        assert written[0].name == "Good.json"
        assert not (out_dir / "Bad.json").exists()
