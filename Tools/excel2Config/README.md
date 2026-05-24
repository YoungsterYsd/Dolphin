# excel2tres · Excel → JSON 配置转换工具

Dolphin 项目用：把 `Tools/Excel/*.xlsx` 里策划维护的配置数据转换为 `Data/FromExcel/*.csv`（或 `*.json`），供运行时业务类（ConfigCenter / FragmentRegistry / ItemConfigLoader / LootTableLoader / AffixPlanLoader 等）直接读取。

> **路径默认值**：`Data/FromExcel/`（与业务侧 ConfigCenter 引用的路径保持一致；GUI 默认目录 + CLI `-o` 默认值都是它）。
> 如需自定义个别 sheet 输出到别处，使用「路径映射」功能（见 §使用·GUI 与 §使用·CLI · `--path-map`）。

完整规约见 `Plans/三期开发计划.md` 第 M10.2 / M10.3 节。

---

## 安装

```powershell
# 进入工具目录
cd Tools/excel2tres

# 安装依赖（推荐 venv，但全局装也行）
pip install -r requirements.txt
```

需求：Python **3.11+**（推荐 3.12）。

---

## Excel 输入契约（速查）

每张 sheet 必须满足如下结构：

| 行/列  | A 列      | B 列     | C 列     | D 列起        |
|--------|-----------|----------|----------|---------------|
| 行 1   | `_export` | `id`     | `sub_id` | 字段名        |
| 行 2   | `Int`     | `Int`    | `Int`    | 字段类型      |
| 行 3+  | `1`/`0`   | id (Int) | 子项 id  | 数据          |

- `_export = 1` 才会被导出；`0` 跳过
- `id` 必填、非 0、Int；同 id 多行 + 不同 sub_id 表示该 id 下的子项
- `sub_id` 留空 = 主行；非空 = 子项；`(id, sub_id)` 联合键全表唯一

### 字段类型

| 类型            | 单元格写法     | 留空默认值      |
|-----------------|----------------|-----------------|
| `Int`           | `5`            | `0`             |
| `Float`         | `3.14`         | `0.0`           |
| `String`        | `Slime`        | `""`            |
| `Enum(A,B,C)`   | `B`            | 首项 `A`        |
| `List(Int)`     | `{1,2,3}`      | `[]`            |
| `List(Float)`   | `{1.5,2.5}`    | `[]`            |
| `List(String)`  | `{hello,world}`| `[]`            |
| `Ignore`        | 任意           | （不输出）      |

---

## 使用

### CLI

```powershell
# 转换：扫描目录下所有 .xlsx，每张 sheet 输出 1 个 .csv（默认 CSV 走业务侧 Loader 实际读取的 Data/FromExcel/）
python main.py convert -i ../Excel/ -o ../../Data/FromExcel/ --format csv

# 单文件
python main.py convert -i ../Excel/角色表.xlsx -o ../../Data/FromExcel/ --format csv

# 仅转换某张 sheet
python main.py convert -i ../Excel/ --only Hero_Data -o ../../Data/FromExcel/ --format csv

# 同时输出 JSON（如有业务模块按 .json 读取）
python main.py convert -i ../Excel/ -o ../../Data/FromExcel/ --format both

# 启用文件名 → 输出路径映射（如把对话 / NPC sheet 单独导出到 Data/Manual/）
python main.py convert -i ../Excel/ -o ../../Data/FromExcel/ --format csv --path-map dolphin_path_map.json

# 仅校验，不写文件
python main.py validate -i ../Excel/

# 即使有错也强制写出可成功的 sheet
python main.py convert -i ../Excel/ -o ../../Data/FromExcel/ --force
```

`dolphin_path_map.json` 范例（项目根仓库已附 `Tools/excel2Config/dolphin_path_map.example.json`）：

```json
[
  {"pattern": "Dialogue.csv", "output_dir": "Data/Manual/Dialogues"},
  {"pattern": "NPC.csv",      "output_dir": "Data/Manual/NPCs"},
  {"pattern": "Quests.csv",   "output_dir": "Data/Manual/Quests"},
  {"pattern": "*.csv",        "output_dir": "Data/FromExcel"}
]
```

匹配优先级：精确文件名 > 通配（`*` / `?`）；都不命中则使用 `-o` 默认目录。

退出码：`0`=clean / `1`=有 error / `2`=CLI 参数错误。

### GUI

```powershell
python gui.py
```

GUI 功能：
- 多文件 / 多目录添加（递归扫描）
- 默认输出目录可选
- **导出格式**：JSON / CSV / JSON+CSV 单选
- **最近导入**：自动记录最近 15 个 .xlsx 文件 / 目录，下拉快捷再加入；可一键清空记录
- **路径映射…** 按钮：为指定文件名（或通配）配置专属输出目录，命中规则即覆盖默认输出目录
- 「校验」按钮 fail-collect 列出所有问题；通过后再点「开始转换」写文件
- 日志区彩色（INFO 黑、WARN 黄、ERROR 红）
- 全部 UI 状态持久化到 `.last_session.json`（输入路径 / 默认输出目录 / 导出格式 / 最近导入 / 路径映射）

---

## 输出

每张 sheet 输出 1 个 `.json`（默认）/ `.csv`（`--format csv`）文件，默认落到
`Data/FromExcel/Generated/<sheet>.<ext>`：

**JSON**：
- 顶级是字典，key = id（字符串化）
- value 是该 id 的记录，含 `sub_entries: [...]`（子项数组，如有）
- 不写元信息

**CSV**：
- 第一行表头：`id, sub_id, <user_field_1>, <user_field_2>, ...`
- 主行：`sub_id` 留空；子行：填具体 `sub_id`，未在子行写过的字段会沿用主行值
- List 序列化为 `{a,b,c}`（与 Excel 单元格写法一致）
- 编码：UTF-8 with BOM（Windows Excel 双击可直接识别中文）

详细 JSON 示例见 `Plans/三期开发计划.md` M10.2「JSON 输出示例」。

---

## 开发

```powershell
# 单测
pytest

# 单测 + 详细输出
pytest -v
```

模块布局：

```
core/
├── type_parser.py   类型字面量解析 + 单元格值校验
├── sheet_reader.py  openpyxl 封装（PR2）
├── aggregator.py    id/sub_id 聚合方案 A（PR2）
├── validator.py     fail-collect 校验（PR3）
├── json_writer.py   .json 落盘（PR3）
└── csv_writer.py    .csv 落盘（PR4 增量）
main.py              CLI 入口（PR4）
gui.py               tkinter GUI（PR4）
```
