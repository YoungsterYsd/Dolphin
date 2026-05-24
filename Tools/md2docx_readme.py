# -*- coding: utf-8 -*-
"""
把 Plans/项目README.md 转成同名 .docx。

直接复用 md2docx_07.py 的全部解析 / 渲染 / 样式逻辑，仅替换 SRC / DST 路径。
"""

from __future__ import annotations
import sys
from pathlib import Path

# 把 Tools/ 加入 sys.path，从 md2docx_07 导入解析器
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from md2docx_07 import (  # noqa: E402
    Document,
    parse_markdown,
    render,
    setup_document,
)


ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Plans" / "项目README.md"
DST = ROOT / "Plans" / "项目README.docx"


def main() -> int:
    if not SRC.exists():
        print(f"[ERROR] 源文件不存在：{SRC}", file=sys.stderr)
        return 1

    md_text = SRC.read_text(encoding="utf-8")
    blocks = parse_markdown(md_text)

    doc = Document()
    setup_document(doc)
    render(doc, blocks)

    DST.parent.mkdir(parents=True, exist_ok=True)
    target = DST
    try:
        doc.save(str(target))
    except PermissionError:
        from datetime import datetime
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        target = DST.with_name(f"{DST.stem}_{stamp}{DST.suffix}")
        doc.save(str(target))
        print(f"[WARN] 主文件被占用，已改写到副本：{target.name}")
    print(f"[OK] 已生成：{target}  ({target.stat().st_size / 1024:.1f} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
