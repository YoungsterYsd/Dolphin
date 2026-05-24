"""excel2tres core 模块。

负责把 Excel sheet 解析为内存模型并最终落盘为 JSON。

模块组成：
    - type_parser : 类型字面量解析 + 单元格值校验/转换
    - sheet_reader: openpyxl 包装，读出 sheet 元信息与数据行
    - aggregator  : 按 id groupby + sub_id 聚合（方案 A）
    - validator   : Fail-collect 校验入口
    - json_writer : 按 sheet 输出 .json

详见 Plans/三期开发计划.md M10.3。
"""

__version__ = "0.1.0"
