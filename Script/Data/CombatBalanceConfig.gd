## 战斗平衡配置（DamagePipeline + BlockComponent 等共用）。
##
## 旧案对齐（[code]Plans/前项目/角色系统_属性_旧案.md[/code] §基础数值公式）：
## - 第 8 步 承伤率 = 500 / (500 + 防御 * (1 - 防御穿透))  → DEFENSE_K = 500
## - 第 12 步 韧性减少值 = 基础破韧 * (1 + %击破加成)
##
## 所有"未来很可能调"的战斗系数都进本配置（R-DATA-02）。
class_name CombatBalanceConfig
extends Resource

# ─────────────────────────────────────────────────────────────
# 防御公式
# ─────────────────────────────────────────────────────────────

## 防御公式 K 值。承伤率 = K / (K + 有效防御)。旧案 §第 8 步默认 500。
@export var defense_k: float = 500.0

# ─────────────────────────────────────────────────────────────
# 完美格挡 buff
# ─────────────────────────────────────────────────────────────

## 完美格挡 buff 触发时的伤害加成倍率（旧值 0.5 = +50%）。
@export var perfect_block_buff_dmg_bonus: float = 0.5

## 完美格挡 buff 触发时的破韧加成倍率（旧值 3.0 = ×3）。
@export var perfect_block_buff_break_bonus: float = 3.0

# ─────────────────────────────────────────────────────────────
# 普通格挡
# ─────────────────────────────────────────────────────────────

## 普通格挡耐久消耗系数（命中伤害 × 此值入耐久；旧值 0.6）。
@export var block_durability_consume_ratio: float = 0.6

## 普通格挡减伤系数（命中伤害 × 此值落地；旧值 0.4）。
@export var block_damage_reduction: float = 0.4

## 破防硬直时长（秒）。耐久耗尽后施加 Combat.Block.Broken tag 的持续时间。
@export var block_broken_stun_sec: float = 1.2

# ─────────────────────────────────────────────────────────────
# 破韧（Break）
# ─────────────────────────────────────────────────────────────

## 基础破韧值占系数（base_damage × 此值；旧值 0.1）。旧案第 10 步基础破韧。
##
## 兼容用：当 [DamageNode.poise_damage] = 0 时，回退到 base_damage * 此值作为削韧量。
@export var break_base_ratio: float = 0.1

## 破韧期间受到的伤害倍率（Q1 决策：破韧期间受击伤害仍正常结算，且应用易伤倍率）。
##
## 1.0 = 无易伤；1.5 = +50% 输出窗口（默认）。
## 在 [DamagePipeline] 第 5 步（减伤）后检测目标 [code]Status.PoiseBroken[/code] tag 应用。
@export var poise_broken_damage_taken_mul: float = 1.5

## 破韧状态持续时长（秒）。
##
## 由 [BTAction_EnterPoiseBroken] 默认值读取。BTAsset 内可个别覆盖。
@export var poise_broken_duration_sec: float = 5.0

# ─────────────────────────────────────────────────────────────
# 硬度打断（Hit Poise / Cast Poise）
# ─────────────────────────────────────────────────────────────

## HitReact 轻反应 Timeline（impact_level < [member hit_react_heavy_threshold] 时使用）。
##
## 用于"被低/中等冲击打断"的硬直动画 + 小幅击退；通常 0.3s 左右。
## 可为 null（缺失时 [InterruptResolver] 退化为只 cancel ability + 加 Stagger tag，无视觉反馈）。
@export var hit_react_light_timeline: SkillTimeline = null

## HitReact 重反应 Timeline（impact_level >= [member hit_react_heavy_threshold] 时使用）。
##
## 用于"被强冲击打断"的硬直动画 + 大幅击退；通常 0.6s 左右。
@export var hit_react_heavy_timeline: SkillTimeline = null

## Heavy HitReact 阈值。impact_level >= 此值走 Heavy；否则走 Light。
##
## 默认 4：依 Dmg_Hardness 表（5%/10%/30%/50%/80%/100% → 1~6），
## 损失 ≥ 50% 血量的命中走 Heavy 反应。
@export var hit_react_heavy_threshold: int = 4
