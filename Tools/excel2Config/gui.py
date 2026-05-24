"""Excel → JSON / CSV 转换工具 · tkinter GUI 独立窗口。

直接运行：
    python gui.py
或：
    python -m excel2tres.gui

特性：
- 输入：可批量添加 .xlsx 文件 / 目录（递归扫描）
- 导出格式：JSON / CSV / Both（同时）
- 最近导入：自动记录最近 15 项，可从下拉快捷再加入
- 默认输出目录 + 文件名映射：可为指定输出文件名（如 `Combat.json`）配置
  「特定输出路径」，命中则覆盖默认输出目录
- 会话持久化：上述所有配置写在 `.last_session.json`
"""
from __future__ import annotations

import json
import sys
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, scrolledtext, ttk

# 允许从工程根目录直接运行 gui.py
ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from core.csv_writer import write_all_csv, write_sheet_csv  # noqa: E402
from core.json_writer import write_all, write_sheet  # noqa: E402
from core.validator import ValidationResult, validate_paths  # noqa: E402


SESSION_FILE = ROOT / ".last_session.json"
# 业务侧（ConfigCenter / Loader）实际读取路径就是 Data/FromExcel，
# 不再在中间套 Generated/ 子目录（避免每次导出后还要手动搬运）。
DEFAULT_OUTPUT = "Data/FromExcel"
RECENT_LIMIT = 15  # 最近导入条目最大数量

# 导出格式选项
FMT_JSON = "JSON"
FMT_CSV = "CSV"
FMT_BOTH = "JSON+CSV"
EXPORT_FORMATS = (FMT_JSON, FMT_CSV, FMT_BOTH)


# ---------------------------------------------------------------------------
# 路径映射管理对话框
# ---------------------------------------------------------------------------


class PathMappingDialog(tk.Toplevel):
    """编辑「输出文件名 → 特定输出路径」映射的弹窗。"""

    def __init__(self, master: tk.Misc, mappings: list[dict]) -> None:
        super().__init__(master)
        self.title("导出路径映射")
        self.geometry("680x400")
        self.transient(master)
        self.grab_set()

        # 复制一份编辑用，确认后回写
        self._mappings: list[dict] = [dict(m) for m in mappings]
        self.result: list[dict] | None = None  # 用户取消则保持 None

        # 上方说明
        tip = ttk.Label(
            self,
            text=(
                "为指定的输出文件名配置专属输出目录；命中规则后将覆盖主界面的默认输出目录。\n"
                "匹配方式：精确匹配 + 通配（* 表示任意字符）。例：Combat.json、*.csv、Effects.*"
            ),
            foreground="gray",
            justify="left",
        )
        tip.pack(fill=tk.X, padx=8, pady=(8, 4))

        # 表格
        table_frame = ttk.Frame(self, padding=4)
        table_frame.pack(fill=tk.BOTH, expand=True, padx=8)

        cols = ("pattern", "output_dir")
        self.tree = ttk.Treeview(
            table_frame, columns=cols, show="headings", height=10
        )
        self.tree.heading("pattern", text="文件名 / 通配")
        self.tree.heading("output_dir", text="输出目录")
        self.tree.column("pattern", width=200, anchor="w")
        self.tree.column("output_dir", width=440, anchor="w")
        self.tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        sb = ttk.Scrollbar(table_frame, orient="vertical", command=self.tree.yview)
        sb.pack(side=tk.LEFT, fill=tk.Y)
        self.tree.configure(yscrollcommand=sb.set)

        # 编辑区
        edit = ttk.LabelFrame(self, text="编辑", padding=6)
        edit.pack(fill=tk.X, padx=8, pady=4)

        self.var_pattern = tk.StringVar()
        self.var_output = tk.StringVar()
        ttk.Label(edit, text="文件名 / 通配：").grid(row=0, column=0, sticky="w")
        ttk.Entry(edit, textvariable=self.var_pattern, width=24).grid(
            row=0, column=1, sticky="we", padx=4
        )
        ttk.Label(edit, text="输出目录：").grid(row=0, column=2, sticky="w")
        ttk.Entry(edit, textvariable=self.var_output).grid(
            row=0, column=3, sticky="we", padx=4
        )
        ttk.Button(edit, text="选择…", command=self._on_browse).grid(
            row=0, column=4, padx=2
        )
        edit.columnconfigure(3, weight=1)

        btns = ttk.Frame(self, padding=(8, 4))
        btns.pack(fill=tk.X)
        ttk.Button(btns, text="新增", command=self._on_add).pack(side=tk.LEFT, padx=2)
        ttk.Button(btns, text="更新选中", command=self._on_update).pack(
            side=tk.LEFT, padx=2
        )
        ttk.Button(btns, text="删除选中", command=self._on_delete).pack(
            side=tk.LEFT, padx=2
        )
        ttk.Button(btns, text="确定", command=self._on_ok).pack(side=tk.RIGHT, padx=2)
        ttk.Button(btns, text="取消", command=self.destroy).pack(side=tk.RIGHT, padx=2)

        self.tree.bind("<<TreeviewSelect>>", self._on_select)
        self._refresh()

    # ------------------------- helpers -------------------------

    def _refresh(self) -> None:
        for iid in self.tree.get_children():
            self.tree.delete(iid)
        for i, m in enumerate(self._mappings):
            self.tree.insert(
                "", tk.END, iid=str(i), values=(m.get("pattern", ""), m.get("output_dir", ""))
            )

    def _selected_index(self) -> int | None:
        sel = self.tree.selection()
        if not sel:
            return None
        try:
            return int(sel[0])
        except ValueError:
            return None

    def _on_select(self, _event: object = None) -> None:
        idx = self._selected_index()
        if idx is None:
            return
        m = self._mappings[idx]
        self.var_pattern.set(m.get("pattern", ""))
        self.var_output.set(m.get("output_dir", ""))

    def _on_browse(self) -> None:
        d = filedialog.askdirectory(title="选择输出目录", parent=self)
        if d:
            self.var_output.set(d)

    def _on_add(self) -> None:
        p = self.var_pattern.get().strip()
        o = self.var_output.get().strip()
        if not p or not o:
            messagebox.showwarning("提示", "请填写文件名和输出目录。", parent=self)
            return
        self._mappings.append({"pattern": p, "output_dir": o})
        self._refresh()

    def _on_update(self) -> None:
        idx = self._selected_index()
        if idx is None:
            messagebox.showwarning("提示", "请先选中一行。", parent=self)
            return
        p = self.var_pattern.get().strip()
        o = self.var_output.get().strip()
        if not p or not o:
            messagebox.showwarning("提示", "请填写文件名和输出目录。", parent=self)
            return
        self._mappings[idx] = {"pattern": p, "output_dir": o}
        self._refresh()

    def _on_delete(self) -> None:
        idx = self._selected_index()
        if idx is None:
            messagebox.showwarning("提示", "请先选中一行。", parent=self)
            return
        del self._mappings[idx]
        self._refresh()

    def _on_ok(self) -> None:
        self.result = self._mappings
        self.destroy()


# ---------------------------------------------------------------------------
# 主应用
# ---------------------------------------------------------------------------


class App:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        root.title("Excel → JSON / CSV 转换器")
        root.geometry("900x720")

        self.input_paths: list[Path] = []
        self.output_dir = tk.StringVar(value=DEFAULT_OUTPUT)
        self.export_format = tk.StringVar(value=FMT_JSON)
        self.recent_files: list[str] = []  # 最近导入的 .xlsx 文件 / 目录
        self.path_mappings: list[dict] = []  # [{pattern, output_dir}, ...]

        self._build_ui()
        self._load_session()
        self._refresh_recent_combo()

    # ----------------------------- UI 构建 -----------------------------

    def _build_ui(self) -> None:
        # 上方：输入区
        top = ttk.Frame(self.root, padding=8)
        top.pack(fill=tk.X)

        ttk.Label(top, text="Excel 文件 / 目录：").grid(row=0, column=0, sticky="w")
        btn_frame = ttk.Frame(top)
        btn_frame.grid(row=0, column=1, sticky="e")
        ttk.Button(btn_frame, text="添加文件", command=self.on_add_file).pack(
            side=tk.LEFT, padx=2
        )
        ttk.Button(btn_frame, text="添加目录", command=self.on_add_dir).pack(
            side=tk.LEFT, padx=2
        )
        ttk.Button(btn_frame, text="清空", command=self.on_clear).pack(
            side=tk.LEFT, padx=2
        )
        top.columnconfigure(0, weight=1)

        # 最近导入快捷区
        recent_row = ttk.Frame(self.root, padding=(8, 0))
        recent_row.pack(fill=tk.X)
        ttk.Label(recent_row, text="最近导入：").pack(side=tk.LEFT)
        self.recent_var = tk.StringVar()
        self.recent_combo = ttk.Combobox(
            recent_row,
            textvariable=self.recent_var,
            values=[],
            state="readonly",
            width=80,
        )
        self.recent_combo.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=4)
        ttk.Button(recent_row, text="加入", command=self.on_recent_add).pack(
            side=tk.LEFT, padx=2
        )
        ttk.Button(recent_row, text="清空记录", command=self.on_recent_clear).pack(
            side=tk.LEFT, padx=2
        )

        # 已添加列表
        self.list_frame = ttk.LabelFrame(self.root, text="已添加", padding=4)
        self.list_frame.pack(fill=tk.BOTH, expand=False, padx=8, pady=(4, 8))
        self.listbox = tk.Listbox(self.list_frame, height=6)
        self.listbox.pack(fill=tk.BOTH, expand=True)

        # 输出区
        out = ttk.Frame(self.root, padding=8)
        out.pack(fill=tk.X)
        ttk.Label(out, text="默认输出目录：").grid(row=0, column=0, sticky="w")
        ttk.Entry(out, textvariable=self.output_dir).grid(
            row=0, column=1, sticky="we", padx=4
        )
        ttk.Button(out, text="浏览", command=self.on_browse_output).grid(
            row=0, column=2, padx=2
        )

        ttk.Label(out, text="导出格式：").grid(row=1, column=0, sticky="w", pady=(4, 0))
        fmt_frame = ttk.Frame(out)
        fmt_frame.grid(row=1, column=1, sticky="w", pady=(4, 0))
        for fmt in EXPORT_FORMATS:
            ttk.Radiobutton(
                fmt_frame, text=fmt, value=fmt, variable=self.export_format
            ).pack(side=tk.LEFT, padx=2)
        ttk.Button(out, text="路径映射…", command=self.on_edit_mappings).grid(
            row=1, column=2, padx=2, pady=(4, 0)
        )
        out.columnconfigure(1, weight=1)

        # 路径映射摘要
        self.mapping_summary = tk.StringVar(value="（无路径映射）")
        ttk.Label(
            self.root, textvariable=self.mapping_summary, foreground="gray", padding=(8, 0)
        ).pack(fill=tk.X)

        # 操作按钮
        action = ttk.Frame(self.root, padding=(8, 4))
        action.pack(fill=tk.X)
        ttk.Button(action, text="校验", command=self.on_validate).pack(
            side=tk.LEFT, padx=2
        )
        ttk.Button(action, text="开始转换", command=self.on_convert).pack(
            side=tk.LEFT, padx=2
        )
        self.status_var = tk.StringVar(value="就绪")
        ttk.Label(action, textvariable=self.status_var, foreground="gray").pack(
            side=tk.RIGHT
        )

        # 日志区
        log_frame = ttk.LabelFrame(self.root, text="日志", padding=4)
        log_frame.pack(fill=tk.BOTH, expand=True, padx=8, pady=8)
        self.log = scrolledtext.ScrolledText(log_frame, height=20, wrap="word")
        self.log.pack(fill=tk.BOTH, expand=True)
        # 彩色 tag
        self.log.tag_config("INFO", foreground="black")
        self.log.tag_config("WARN", foreground="#b07000")
        self.log.tag_config("ERROR", foreground="#c00000")
        self.log.tag_config("OK", foreground="#007000")
        self.log.tag_config("SUMMARY", foreground="#000080", font=("TkDefaultFont", 9, "bold"))
        self.log.configure(state="disabled")

    # ----------------------------- 会话持久化 -----------------------------

    def _load_session(self) -> None:
        if not SESSION_FILE.exists():
            return
        try:
            data = json.loads(SESSION_FILE.read_text(encoding="utf-8"))
        except Exception:
            return
        for p in data.get("input_paths", []):
            path = Path(p)
            if path.exists():
                self.input_paths.append(path)
        self._refresh_listbox()
        out = data.get("output_dir")
        if out:
            # 一次性迁移：旧默认值 "Data/FromExcel/Generated" → "Data/FromExcel"
            # 让升级了 gui.py 的现有用户启动后立刻拿到正确默认；用户改过的自定义路径不动
            if out.replace("\\", "/").rstrip("/").endswith("Data/FromExcel/Generated"):
                out = DEFAULT_OUTPUT
            self.output_dir.set(out)
        fmt = data.get("export_format")
        if fmt in EXPORT_FORMATS:
            self.export_format.set(fmt)
        self.recent_files = [
            str(p) for p in data.get("recent_files", []) if isinstance(p, str)
        ][:RECENT_LIMIT]
        self.path_mappings = [
            m for m in data.get("path_mappings", [])
            if isinstance(m, dict) and m.get("pattern") and m.get("output_dir")
        ]
        self._refresh_mapping_summary()

    def _save_session(self) -> None:
        try:
            SESSION_FILE.write_text(
                json.dumps(
                    {
                        "input_paths": [str(p) for p in self.input_paths],
                        "output_dir": self.output_dir.get(),
                        "export_format": self.export_format.get(),
                        "recent_files": self.recent_files[:RECENT_LIMIT],
                        "path_mappings": self.path_mappings,
                    },
                    ensure_ascii=False,
                    indent=2,
                ),
                encoding="utf-8",
            )
        except Exception:
            pass

    # ----------------------------- 最近导入 -----------------------------

    def _push_recent(self, path: Path) -> None:
        s = str(path)
        if s in self.recent_files:
            self.recent_files.remove(s)
        self.recent_files.insert(0, s)
        del self.recent_files[RECENT_LIMIT:]
        self._refresh_recent_combo()

    def _refresh_recent_combo(self) -> None:
        # 过滤掉已不存在的项
        self.recent_files = [s for s in self.recent_files if Path(s).exists()]
        self.recent_combo["values"] = self.recent_files
        if self.recent_files:
            self.recent_var.set(self.recent_files[0])
        else:
            self.recent_var.set("")

    def on_recent_add(self) -> None:
        s = self.recent_var.get().strip()
        if not s:
            return
        path = Path(s)
        if not path.exists():
            self._log(f"路径不存在：{s}", "ERROR")
            self._refresh_recent_combo()
            return
        if path not in self.input_paths:
            self.input_paths.append(path)
        self._push_recent(path)
        self._refresh_listbox()
        self._save_session()

    def on_recent_clear(self) -> None:
        if not self.recent_files:
            return
        if not messagebox.askyesno("确认", "确定清空最近导入记录吗？", parent=self.root):
            return
        self.recent_files.clear()
        self._refresh_recent_combo()
        self._save_session()

    # ----------------------------- 路径映射 -----------------------------

    def on_edit_mappings(self) -> None:
        dlg = PathMappingDialog(self.root, self.path_mappings)
        self.root.wait_window(dlg)
        if dlg.result is not None:
            self.path_mappings = dlg.result
            self._refresh_mapping_summary()
            self._save_session()

    def _refresh_mapping_summary(self) -> None:
        if not self.path_mappings:
            self.mapping_summary.set("（无路径映射）")
            return
        self.mapping_summary.set(
            f"路径映射：已配置 {len(self.path_mappings)} 条规则"
        )

    def _resolve_output_dir(self, file_name: str) -> Path:
        """根据导出文件名（如 `Combat.json`）查找对应输出目录；
        匹配优先级：精确 > 通配；找不到则返回默认输出目录。"""
        from fnmatch import fnmatchcase

        default_dir = Path(self.output_dir.get().strip() or DEFAULT_OUTPUT)

        # 第一遍：精确匹配
        for m in self.path_mappings:
            if m["pattern"] == file_name:
                return Path(m["output_dir"])
        # 第二遍：通配匹配
        for m in self.path_mappings:
            if fnmatchcase(file_name, m["pattern"]):
                return Path(m["output_dir"])
        return default_dir

    # ----------------------------- 按钮回调 -----------------------------

    def on_add_file(self) -> None:
        paths = filedialog.askopenfilenames(
            title="选择 .xlsx 文件",
            filetypes=[("Excel", "*.xlsx"), ("All", "*.*")],
        )
        for p in paths:
            path = Path(p)
            if path not in self.input_paths:
                self.input_paths.append(path)
            self._push_recent(path)
        self._refresh_listbox()
        self._save_session()

    def on_add_dir(self) -> None:
        d = filedialog.askdirectory(title="选择目录（递归扫描 .xlsx）")
        if d:
            path = Path(d)
            if path not in self.input_paths:
                self.input_paths.append(path)
            self._push_recent(path)
            self._refresh_listbox()
            self._save_session()

    def on_clear(self) -> None:
        self.input_paths.clear()
        self._refresh_listbox()
        self._save_session()

    def on_browse_output(self) -> None:
        d = filedialog.askdirectory(title="选择输出目录")
        if d:
            self.output_dir.set(d)
            self._save_session()

    def on_validate(self) -> None:
        self._run_async(self._task_validate)

    def on_convert(self) -> None:
        self._run_async(self._task_convert)

    # ----------------------------- 任务 -----------------------------

    def _task_validate(self) -> None:
        result = self._run_scan()
        if result is None:
            return
        if result.is_clean:
            self._log("校验通过 ✓", "OK")
        else:
            self._log(f"校验失败：{len(result.all_errors)} 个错误", "ERROR")

    def _task_convert(self) -> None:
        result = self._run_scan()
        if result is None:
            return
        if not result.is_clean:
            self._log("存在错误：未写出任何文件。", "ERROR")
            return

        default_out = self.output_dir.get().strip()
        if not default_out:
            self._log("默认输出目录为空，已取消。", "ERROR")
            return

        fmt = self.export_format.get()
        want_json = fmt in (FMT_JSON, FMT_BOTH)
        want_csv = fmt in (FMT_CSV, FMT_BOTH)

        written: list[Path] = []
        for sr in result.sheets:
            if sr.sheet_name == "<workbook>":
                continue
            if not sr.is_clean:
                continue
            agg = sr.agg
            if want_json:
                target_dir = self._resolve_output_dir(f"{agg.sheet_name}.json")
                p = write_sheet(agg, target_dir)
                written.append(p)
                self._log(f"  [JSON] {p}", "INFO")
            if want_csv:
                target_dir = self._resolve_output_dir(f"{agg.sheet_name}.csv")
                p = write_sheet_csv(agg, target_dir)
                written.append(p)
                self._log(f"  [CSV ] {p}", "INFO")

        if not written:
            self._log("没有任何 sheet 被写出。", "WARN")
        else:
            self._log(f"已写出 {len(written)} 个文件（格式：{fmt}）", "OK")

    def _run_scan(self) -> ValidationResult | None:
        if not self.input_paths:
            self._log("尚未添加任何 Excel 文件 / 目录。", "ERROR")
            return None
        self._set_status("扫描中…")
        result = validate_paths(self.input_paths)

        for sr in result.sheets:
            if sr.sheet_name == "<workbook>":
                continue
            n_rows = len(sr.agg.records)
            n_subs = sum(len(r.sub_entries) for r in sr.agg.records.values())
            self._log(
                f"{Path(sr.source_file).name}::{sr.sheet_name} "
                f"→ {n_rows} records, {n_subs} sub-entries",
                "INFO",
            )
        for w in result.all_warnings:
            self._log(w.format(), "WARN")
        for e in result.all_errors:
            self._log(e.format(), "ERROR")
        self._log(result.summary(), "SUMMARY")
        self._set_status("就绪")
        return result

    # ----------------------------- 辅助 -----------------------------

    def _refresh_listbox(self) -> None:
        self.listbox.delete(0, tk.END)
        for p in self.input_paths:
            label = str(p)
            if p.is_dir():
                label += "  (目录)"
            self.listbox.insert(tk.END, label)

    def _log(self, msg: str, tag: str = "INFO") -> None:
        prefix = {
            "INFO": "[INFO]  ",
            "WARN": "[WARN]  ",
            "ERROR": "[ERROR] ",
            "OK": "[OK]    ",
            "SUMMARY": "",
        }.get(tag, "")
        self.log.configure(state="normal")
        self.log.insert(tk.END, prefix + msg + "\n", tag)
        self.log.see(tk.END)
        self.log.configure(state="disabled")
        self.root.update_idletasks()

    def _set_status(self, msg: str) -> None:
        self.status_var.set(msg)
        self.root.update_idletasks()

    def _run_async(self, fn) -> None:
        """后台线程跑任务，避免阻塞 UI。Tkinter 不严格线程安全，
        但我们的 _log/_set_status 都做了 update_idletasks，且仅在该线程内写。"""
        # 简化：本工具任务通常 <1s，直接同步跑即可；如未来变慢可改 threading
        try:
            fn()
        except Exception as e:
            self._log(f"任务异常：{e}", "ERROR")


def main() -> None:
    root = tk.Tk()
    App(root)
    root.mainloop()


if __name__ == "__main__":
    main()
