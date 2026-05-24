## 全局事件总线（Autoload 单例）。
##
## 所有跨模块全局信号集中声明在此（参见 R-EVENT-01）。
## 业务节点上的 signal 仅用于自身/父子作用域；跨模块通信一律走本类。
##
## 命名规则（R-NAME-01）：snake_case 过去式，如 [signal enemy_died]。
extends Node

# ─────────────────────────────────────────────────────────────
# 游戏状态
# ─────────────────────────────────────────────────────────────

## 顶层游戏状态发生切换。old_state/new_state 为 GameInstance.GameState 枚举值。
signal game_state_changed(old_state: int, new_state: int)


# ─────────────────────────────────────────────────────────────
# 输入层（来自 InputController · 见 Plans/Dolphin设计/01_战斗框架_输入映射）
# ─────────────────────────────────────────────────────────────
# - combat_* / ui_panel_build 走这里；ui_pause 由 GameInstance Autoload 直接接管，不走本信号。
# - 业务方按 action 名（StringName）分发，避免每个动作都新增专用信号。
# - InputController 在 PROCESS_MODE_PAUSABLE 下运行，game tree paused 时本信号不再发射。

## 玩家按下了某个 InputMap action（边沿，just_pressed）。
signal player_input_action_pressed(action: StringName)

## 玩家松开了某个 InputMap action（边沿，just_released）。
signal player_input_action_released(action: StringName)

## 移动输入向量变化（XY 平面：X=move_left/right，Y=move_up/down 上为 -1）。
## 业务方一般转 Vector3(x, 0, y) 用于 XZ 平面。
signal player_move_vector_changed(vec: Vector2)


# ─────────────────────────────────────────────────────────────
# 战斗状态（CombatStateService 后续实装；先预留信号）
# ─────────────────────────────────────────────────────────────

## 战斗状态变化（5s 内伤害 ∪ 8m 仇恨怪 → active=true）。
signal combat_state_changed(active: bool)



# ─────────────────────────────────────────────────────────────
# GAS · 属性 / 技能 / 效果
# ─────────────────────────────────────────────────────────────

## AttributeSet 中任一属性发生变化时广播。
## owner 为持有该 AttributeSet 的节点（一般是 ASC 所在节点）。
signal attribute_changed(owner: Node, attr_name: StringName, old_value: float, new_value: float)

## 技能成功激活。
signal ability_activated(owner: Node, ability_id: StringName)

## 技能因 cost / cd / tag 拦截而激活失败。
signal ability_activation_failed(owner: Node, ability_id: StringName, reason: String)

## 技能正常结束（无论成功命中与否）。
signal ability_ended(owner: Node, ability_id: StringName)

## 技能被外部强制中止（被打断 / 主动 cancel 等）。
##
## 派发方：[method AbilitySystemComponent.cancel_active_abilities]。
## 与 [signal ability_ended] 区别：本信号专表"非正常收尾"，
## 上层（HUD / AI / SkillTimelinePlayerHost / Cue）可据此做不同表现。
##
## 设计：本信号 emit 后紧接着 ability_ended 也会 emit 一次，订阅 ended 的清理逻辑无需双订阅。
signal ability_interrupted(owner: Node, ability_id: StringName)

## GameplayEffect 应用到目标。
signal effect_applied(target: Node, effect: Resource, source: Node)

## GameplayEffect 从目标移除（含到期、被驱散）。
signal effect_removed(target: Node, effect: Resource)


# ─────────────────────────────────────────────────────────────
# 战斗
# ─────────────────────────────────────────────────────────────

## 一次伤害结算完成。amount 为最终扣血数值。
signal damage_dealt(source: Node, target: Node, amount: float, damage_type: StringName)

## 扩展版伤害事件：携带 DamageNode 引用 + 暴击标记，给表现层（飘字 / HitFlash / VFX）订阅用。
## 注：旧 damage_dealt 信号仍保留（HitDamageResolver 也仍 emit）；表现层优先订阅本信号。
signal damage_dealt_v2(source: Node, target: Node, amount: float, damage_node: Resource, is_crit: bool)

## 四样式版本伤害事件（DamagePipeline 第 13 步派发）。
## - is_crit：暴击 → 金色加大字号
## - is_block：普通格挡 → 灰色 + 数值减半显示
## - is_perfect_block：完美格挡（dealt=0）→ 银色"完美格挡"文字（不显数值）
## 表现层（DamagePopupPool）按 4 状态选样式。
##
## 设计说明：保留 v2 兼容老订阅方（HitVignetteWidget / ComboTracker / CombatStateService / EnergyComponent），
## v3 让 DamagePopup 能区分 4 种飘字。两个信号同时派发，不重复显示（DamagePopup 切到订阅 v3）。
signal damage_dealt_v3(source: Node, target: Node, amount: float, is_crit: bool, is_block: bool, is_perfect_block: bool, tags: Array)

## 完美格挡触发（DamagePipeline 第 7 步广播；UI 银色"完美格挡"飘字订阅）。
signal damage_perfect_blocked(attacker: Node, target: Node, would_dealt: float)

## 玩家完美格挡触发刷 buff 时广播（BlockComponent.trigger_perfect_block_buff 派发）。
## 与 [signal damage_perfect_blocked] 区别：本信号在 buff apply 后，前者在受击当帧。
signal block_perfect_triggered(blocker: Node)

## 格挡耐久耗尽 → 破防硬直信号。
## ASC.consume_block 在 stamina 归零时 emit；BlockComponent 自己订阅并 stop_block。
## R-ARCH-04：替代 ASC 反向调 BlockComponent.stop_block 的越权耦合。
signal block_broken(blocker: Node)

## 怪物韧性归零 → 进入破韧状态。
## EnemyCharacter._trigger_poise_broken 在 poise_current<=0 时 emit；
## EnemyCharacter._on_poise_broken_signal 写自身 BTPlayer 黑板键 [code]&"event_poise_broken"[/code]，
## LimboAI 行为树高优先级分支（BTCondition_OnEvent）响应。
## 同时 ASC 添加 [code]Status.PoiseBroken[/code] tag，DamagePipeline 检测后施加易伤倍率。
signal poise_broken(target: Node)

## 破韧状态结束（默认 5s）→ 韧性条恢复满。
## BTAction_EnterPoiseBroken._on_exit 派发；HUD 韧性条接入后可订阅本信号刷新视觉。
signal poise_recovered(target: Node)

## 角色被打断（高硬度命中触发）。
##
## 派发方：[InterruptResolver.try_interrupt]。
## 表现层（CueManager / VFX / SFX）/ AI（敌人 BT 高优分支）/ HUD（受击 vignette）可订阅。
##
## - target：被打断方（受击者）
## - attacker：施加打断的攻击方（可能为 null，如陷阱伤害）
## - impact_level：本次冲击硬度等级（来自 [DamageNode.hit_poise] 或 [PoiseImpactTable] 反查）
signal character_interrupted(target: Node, attacker: Node, impact_level: int)

## 玩家死亡。
signal player_died()

## 怪物死亡。
signal enemy_died(enemy: Node)

## 怪物生成（供 OverheadHealthBarManager 监听并自动挂血条）。
## 由 EnemyCharacter._ready 在初始化完成后 emit。
signal enemy_spawned(enemy: Node)

## HealthSet HP 归零事件。
## 由 HealthSet 元属性管道在 health 触底时派发；
## 业务侧（EnemyCharacter / PlayerCharacter）订阅本信号桥接到 enemy_died / player_died。
##
## 设计上 out_of_health 是"低层属性事件"，enemy_died / player_died 是"高层语义事件"。
signal out_of_health(asc: Node)

## 角色 8 步初始化完成事件（spawn 时由 ASC.bootstrap_from_entity 末尾派发）。
## 业务侧（HUD 头顶血条 Manager / CombatStateService 等）按需订阅。
signal character_initialized(character: Node)

## 玩家切换池能量变化（EnergyComponent.add_switch_energy / consume_switch_energy 派发）。
## HUD 切换池 widget 订阅本信号刷新进度条。
signal switch_energy_changed(character: Node, current: float, max_value: float)


# ─────────────────────────────────────────────────────────────
# 玩家成长（LevelComponent 派发）
# ─────────────────────────────────────────────────────────────

## 玩家升级（每升一级派发一次；多级跨越时连续派发多次，每次 new_level=old_level+1）。
##
## 设计要点：经验本身的变化复用 [signal attribute_changed]（attr=&"experience"）；
## 等级变化也走 [signal attribute_changed]（attr=&"level"，LevelUpWidget 已订阅显示横幅）；
## 本信号是"升级语义事件"补充，给业务侧（属性点奖励 / 技能解锁 / SFX / 任务节点）订阅，
## 避免它们跟踪 attribute_changed 时反复判断"new>old 才是升级而不是配置写入"。
##
## 派发方：[LevelComponent]。
signal player_leveled_up(player: Node, old_level: int, new_level: int)


# ─────────────────────────────────────────────────────────────
# 关卡 / Boss
# ─────────────────────────────────────────────────────────────

## 关卡切换完成。
signal level_changed(level_id: StringName)

## 关卡通关。
signal level_completed(level_id: StringName)

## 关卡加载开始（LevelManager 异步流程入口）。
## from_level_id 可能为空（启动场景 / 首次进入）。
signal level_loading_started(from_level_id: StringName, to_level_id: StringName)

## 关卡加载完成（场景已切换 + fade in 完毕）。
signal level_loading_finished(level_id: StringName)

## Boss 进入新阶段。
signal boss_phase_changed(boss: Node, phase: int)


# ─────────────────────────────────────────────────────────────
# UI / 物品
# ─────────────────────────────────────────────────────────────

## 背包内容变化（增删改）。
signal inventory_changed(owner: Node)

## 装备变化。
signal equipment_changed(owner: Node, slot: int)

## 物品成功添加到背包（拾取 / 商店 / 任务奖励 / 调试命令）。
## owner 为持有方角色；def 为 ItemDefinition；count 为本次添加数量。
## HUD 拾取飘字 widget 订阅本信号。
signal item_added(owner: Node, def: Resource, count: int)

## 任务道具被使用。任务系统订阅此信号判断是否触发任务节点。
## def_id 为道具主键 id；quest_id 为 Frag_Quest.Quest_ID；user 为使用方角色。
signal quest_item_used(def_id: int, quest_id: int, user: Node)

## 货币余额变更。
## currency_id 为 ItemDefinition.item_id（含 [Fragment_Currency] 的物品 id）；
## new_amount 为变更后总持有量；
## 派发方：[CurrencyManager]（**唯一发射源**，符合 R-EVENT-01）。
## CurrencyBarWidget / 商店 UI / 飘字 HUD 订阅本信号。
signal currency_changed(currency_id: int, new_amount: int)

## 道具丢弃。
## owner 为持有方角色；def 为 ItemDefinition；count 为丢弃数量；
## instance 仅装备类有值（带词条）；其它（药水/任务道具）为 null。
## 派发方：[InventoryUI] 拖出面板触发的丢弃流程（Phase 1 仅广播信号，
## 不在场景内生成 Pickup 实体；后续可由 PickupArea 订阅本信号在玩家脚下重生成实体）。
signal item_dropped(owner: Node, def: Resource, count: int, instance: Resource)

## 通用 HUD 提示请求。
signal hud_toast_requested(text: String, duration: float)


# ─────────────────────────────────────────────────────────────
# HUD 系统（Phase 0+ 接入；HUDStateMachine / InputContextManager / HUDManager 订阅）
# ─────────────────────────────────────────────────────────────

## 输入上下文栈顶切换（InputContextManager 派发）。
signal hud_input_context_changed(old_id: StringName, new_id: StringName)

## HUD 顶层状态变化（HUDStateMachine 派发；状态枚举值见 HUDStateMachine.State）。
signal hud_state_changed(old_state: int, new_state: int)

## 一个 widget 被 push 到指定层（HUDManager 派发）。
signal hud_widget_pushed(layer: StringName, widget: Control)

## 一个 widget 从指定层被 pop（HUDManager 派发）。
signal hud_widget_popped(layer: StringName, widget: Control)

## 连击数变化（ComboTracker 派发）。count=0 表示清零。
signal combo_changed(count: int)

## 拾取提示（业务侧调用，PickupNotificationWidget 订阅）。
signal pickup_displayed(item_id: StringName, qty: int)

## 全屏大字横幅请求（业务侧调用，BigBannerWidget 订阅）。
## banner_id 取值约定：&"you_died" / &"victory" / &"boss_intro" / &"level_up" / 自定义。
signal hud_big_banner_requested(banner_id: StringName)

## **【M12 重写】**任务系统采用 (quest_id, sub_id) 二元组（int+int），同 quest_id 多 sub_id 顺序串行。
## 信号设计上**每个步骤即为一个独立任务**（HUD 同时只显示当前 active 那一个）。

## 步骤启动（接受 / 自动接下一 sub 时派发）。
signal quest_step_started(quest_id: int, sub_id: int)

## 步骤进度变化（含 0/N 的初始派发）。
signal quest_step_progress(quest_id: int, sub_id: int, current: int, target: int)

## 步骤进入"待交付"中间态（目标已达成 + Deliver_Dialogue_ID > 0）。
signal quest_step_pending_deliver(quest_id: int, sub_id: int)

## 步骤完成（已发奖；自动接下一 sub）。
signal quest_step_completed(quest_id: int, sub_id: int)

## 任务系列完成（最后一个 sub_id 完成时派发）。
signal quest_series_completed(quest_id: int)

## 任务系列放弃。
signal quest_abandoned(quest_id: int)


# ─────────────────────────────────────────────────────────────
# 对话系统（M12；DialogueRunner 派发，DialogueWidget / 业务侧订阅）
# ─────────────────────────────────────────────────────────────

## 对话开始（graph_id 来自 Dialogue.csv，npc_id 来自 NPC_Data.csv；npc_id<=0 表示无关联 NPC）。
signal dialogue_started(graph_id: int, npc_id: int)

## 当前节点变化（每次 _enter_node 派发；DialogueWidget 据此渲染）。
signal dialogue_node_changed(node: Resource)

## 选项呈现（已过滤 cond_id；options 元素为 ChoiceOption；DialogueWidget 按 index 调 select_choice）。
signal dialogue_choice_presented(options: Array)

## 对话自然结束（业务侧应订阅此信号做"任务交付推进"等推进逻辑）。
signal dialogue_ended(graph_id: int, npc_id: int)

## 对话被强制中断（玩家死亡 / 关卡切换 / 进入战斗等）。**不应**触发任务推进。
signal dialogue_aborted(graph_id: int, npc_id: int)

## NPC 对话菜单请求（≥2 个可见 Diapack 选项时由 NPCActor 派发）。
##
## options 元素为 Dictionary（来自 NPC_Diapack.csv 行；含 [code]Talk_Text[/code] / [code]Dialogue_ID[/code] 等）。
## **业务侧**（[code]NPCDiapackMenuWidget[/code]，Phase 3.5 实装）订阅此信号渲染菜单。
signal npc_dialogue_menu_requested(npc_id: int, options: Array)


# ─────────────────────────────────────────────────────────────
# 交互系统（M11 NPC；InteractableTarget 派发，InteractionPromptWidget 订阅）
# ─────────────────────────────────────────────────────────────

## 玩家进入某个交互目标范围。提示 widget 据此显示。
signal interaction_target_entered(target: Node)

## 玩家离开交互目标范围。提示 widget 据此隐藏。
signal interaction_target_left(target: Node)


# ─────────────────────────────────────────────────────────────
# 技能时间轴（SkillTimeline · EventTrack 派发）
# ─────────────────────────────────────────────────────────────
# 6 种"广播类"事件 Kind（SkillEventKind）通过这里转发给各 Manager 订阅；
# 2 种"直管类"（HITBOX_ENABLE/HITBOX_DISABLE）由 SkillTimelinePlayerHost 内部直接处理，不走 EventBus。
# R-EVENT-01：跨模块全局信号集中声明在此。

## 技能播放开始（一份 timeline 进入活动列表）。
signal skill_timeline_started(skill_id: StringName, caster: Node, handle_id: int)

## 技能播放结束（duration 到时间或 stop 主动终止）。
signal skill_timeline_ended(skill_id: StringName, caster: Node, handle_id: int)

## 音频播放请求（payload: {sfx_id: StringName, ...}）。AudioManager 订阅。
signal skill_event_sfx(sfx_id: StringName, caster: Node, payload: Dictionary)

## 特效生成请求。VFXSpawner 订阅。
signal skill_event_vfx(vfx_id: StringName, caster: Node, payload: Dictionary)

## 投掷物生成请求。ProjectileSpawner 订阅。
signal skill_event_projectile(projectile_id: StringName, caster: Node, payload: Dictionary)

## 屏幕震动请求。CameraRig 订阅。
signal skill_event_camera_shake(intensity: float, duration: float, caster: Node)

## 冻帧请求（duration_ms 毫秒）。HitStopHost 订阅。
signal skill_event_hit_stop(duration_ms: float, caster: Node)

## 自定义信号（业务可订阅 signal_name 做扩展）。
signal skill_event_custom(signal_name: StringName, caster: Node, data: Dictionary)


# ─────────────────────────────────────────────────────────────
# Cue 系统（CueManager 派发；表现层订阅）
# ─────────────────────────────────────────────────────────────

## CueManager 完成一次 cue 派发后广播。
## 仅作"调用点诊断"用途（rule-keeper 可 grep cue 调用密度），不承担表现层订阅职责
## ——表现层（VFX/Audio/Camera）仍订阅各自的 [signal skill_event_*] 信号。
signal cue_executed(cue_tag: StringName, instigator: Node, payload: Dictionary)


# ─────────────────────────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	GameLogger.info("Core", "EventBus ready")
