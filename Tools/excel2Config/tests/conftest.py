"""pytest 配置：把工程根加入 sys.path，方便 `from core import ...` 直接 import。"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
