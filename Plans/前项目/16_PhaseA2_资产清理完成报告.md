# Phase A2 · 资产大扫除完成报告（v1.0）

> 落款日期：2026-05-13  
> 操作时长：约 4 小时（含主理人 13 资产建造 + AI 接力 S3~S7）  
> 配套文档：`13_裁剪完成报告.md` v1.5 / `15_资产大扫除与重建清单.md` / `15A_主理人执行清单.md`

---

## §1 目标回顾

A1（裁剪）阶段以"重命名 C++ 类 + CoreRedirects"完成基础改造，但留下了**资产层 Lyra 残留**——`B_LyraGameMode` / `B_LyraDefaultExperience` / `DefaultGameData` 等 Lyra Demo 资产依然在 Content 里。

A2 阶段目标：
1. **建 13 个 RPG 原生资产**取代 Lyra 资产
2. **物理删除所有"基于 Lyra C++ 类创建的蓝图实例"**
3. **保留所有美术/动画/音频/材质/纹理基础资产**（A3 占位用）
4. 让 Editor 启动 + PIE 0 Fatal / 0 PrimaryAssetType-Ignoring

---

## §2 完成数据

### 2.1 新建资产（14 项 = 13 主理人 + 1 AI 占位）

| # | 资产 | 路径 | 父类 | 建造方 |
|---|---|---|---|---|
| ① | DA_RPG_PawnData_Default | `/Game/Characters/Heroes/RPG/` | URPGPawnData | 主理人 |
| ② | DA_RPG_Team_Player | `/Game/System/Teams/` | URPGTeamDisplayAsset | 主理人 |
| ② | DA_RPG_Team_Enemy | `/Game/System/Teams/` | URPGTeamDisplayAsset | 主理人 |
| ② | DA_RPG_Team_Neutral | `/Game/System/Teams/` | URPGTeamDisplayAsset | 主理人 |
| ③ | B_RPG_UIPolicy | `/Game/UI/` | URPGUIPolicy（**新增 C++ 子类**） | 主理人 |
| ④ | B_RPG_PrimaryGameLayout | `/Game/UI/` | UPrimaryGameLayout | 主理人 |
| ⑤ | WBP_RPG_MainMenu | `/Game/UI/FrontEnd/` | URPGActivatableWidget | 主理人 |
| ⑥ | B_RPG_Experience_FrontEnd_Menu | `/Game/System/Experiences/` | URPGExperienceDefinition | 主理人 |
| ⑦ | B_RPG_Experience_TestArena | `/Game/System/Experiences/` | URPGExperienceDefinition | 主理人 |
| ⑧ | B_RPG_GameMode_Default | `/Game/` | ARPGGameMode | 主理人 |
| ⑨ | B_RPG_GameInstance | `/Game/` | URPGGameInstance | 主理人 |
| ⑩ | L_RPG_Frontend.umap | `/Game/Maps/` | World | 主理人 |
| ⑪ | L_TestArena01.umap | `/Game/Maps/` | World | 主理人 |
| 🆕 | DA_RPG_GameData_Default | `/Game/System/` | URPGGameData | AI Python 占位 |

### 2.2 删除资产（共 59 文件 / 9.78 MB）

| 档位 | 数量 | 说明 |
|---|---|---|
| 1A · Lyra 命名核心蓝图 | 13 | `B_LyraGameMode/GameInstance/UIPolicy/FrontendStateComponent` + 8 个 Lyra UI 控件 |
| 1B · 默认 Pawn / 触摸按钮 | 10 | Character_Default/Hero_Default/SimpleHeroPawn/PhysMat_Player + 触屏按钮 |
| 1C · 射击专属 GA + Weapon 基类 | 5 | B_Weapon/GA_Weapon_Fire/AutoReload/ReloadMagazine/B_ShootingTarget |
| 1D · Lyra Demo 关卡 | 5 | L_LyraFrontEnd / L_DefaultEditorOverview / TransitionMap + 2 BuiltData |
| 1E · 旧 GameData / Team / Playlist | 9 | DefaultGameData/DefaultGame_Label/DA_Frontend/DA_ExamplePlaylist + 4 TeamDA + 1 Texture |
| 改名 redirector | 1 | B_RPG_GameMode（改名 _Default 后留下的） |
| Resave 暴露的 broken BP | 16 | Lyra Demo 专属 UI（会话浏览器/录像/触屏 + 射击 Reload + Hero_Heal） |
| **总计** | **59** | **9.78 MB** |

### 2.3 保留资产（不影响功能）

- **5 个无害 Lyra* 通用按钮**（`W_LyraButton/Tab/SessionButton/LyraLogo_*`）—— 视觉占位符，A4 UI 重做时替换
- **2825 个其他资产**（Mannequin 770 + Effects 257 + Audio 947 + Tools 37 + UI Foundation 等）

---

## §3 关键修复

### 3.1 v1.5 已记录修复（13 文档 §9.8）

| 修复 | 文件 | 行为 |
|---|---|---|
| URPGUIPolicy 新增 | `RPG/Source/RPGGame/UI/Subsystem/RPGUIPolicy.h+cpp` | 修复 CommonGame `UGameUIPolicy::GetWorld()` 编辑 CDO 时 Fatal |
| 反射元标签 Lyra 清扫 | 38 个 .h 文件 | `Category=`/`DisplayName=` 共 135 处改名 |

### 3.2 A2 新增修复

**RPGAssetManager GameData 加载防御层**（`RPGAssetManager.cpp:179-205`）：
- 原行为：`LoadGameDataOfClass()` 找不到 GameData 资产 → `UE_LOG(Fatal, ...)` 直接崩
- 新行为：找不到时**先尝试 CDO 兜底**，只有 CDO 也拿不到才 Fatal
- 效果：删除旧 DefaultGameData 后 + 新 DA_RPG_GameData_Default 生成前的过渡期间 Editor 仍能启动，避免锁死

**Config 改造**（3 份 ini 共 13 处替换）：
| ini | 字段 | 新值 |
|---|---|---|
| DefaultEngine.ini | GlobalDefaultGameMode | `B_RPG_GameMode_Default_C` |
| DefaultEngine.ini | GameInstanceClass | `B_RPG_GameInstance_C` |
| DefaultEngine.ini | GameDefaultMap / EditorStartupMap | `L_RPG_Frontend` |
| DefaultEngine.ini | MapsToPIETest (×2) | `L_RPG_Frontend / L_TestArena01` |
| DefaultGame.ini | RPGGameDataPath | `DA_RPG_GameData_Default` |
| DefaultGame.ini | DefaultPawnData | `DA_RPG_PawnData_Default` |
| DefaultGame.ini | RPGGameData SpecificAssets | `DA_RPG_GameData_Default` |
| DefaultGame.ini | RPGExperienceDefinition SpecificAssets | `B_RPG_Experience_*`（×2） |
| DefaultGame.ini | DefaultUIPolicyClass | `B_RPG_UIPolicy_C` |
| DefaultGame.ini | MapsToCook (×2) | `L_RPG_Frontend / L_TestArena01` |
| DefaultEditorPerProjectUserSettings.ini | CommonEditorMaps (×2) | 同上 |

---

## §4 验证记录

### 4.1 编译

| 阶段 | 时长 | 错误/警告 |
|---|---|---|
| 初始编译（含 URPGUIPolicy 新增） | 6.81s | 0 / 0 |
| GameData 防御层编译 | 6.24s | 0 / 0 |
| 共 5 次编译，全部 Result: Succeeded | — | 0 fatal |

### 4.2 ResavePackages 全量

```
Total time:    295.8s
Packages:      2825
Saved:         2824/2825 (99.96%)
Errors:        4989（全部为 broken-cast Lyra 引用，预期内）
Fatals:        0
```

`broken-cast` 错误统计：29 个蓝图编译失败 → 删 16 / 保留 13（A4/A5 时手动修）

### 4.3 -game 12s 实测（最严格的红线）

```
Total log lines:        1597 ~ 1763
Fatal hits:             0 ✅
Experience-related:     0 ✅
PrimaryAssetType-Ignoring: 0 ✅
Process status:         alive 12s, killed by test runner（不是自己崩）
```

### 4.4 资产审计

```
Content 总量:           2936 files, 2,809 assets, 1.8 GB
13 RPG 资产:            14/14 OK（含 1 个 AI 占位 GameData）
剩余 Lyra* 命名:         5（全部为无害通用按钮 / Logo）
```

---

## §5 后续 13 个 broken BP 处理建议（A3-A5 各阶段处理）

| 阶段 | broken BP | 处理方式 |
|---|---|---|
| A3 主角 | `ABP_Mannequin_Base.uasset` | 打开 → AnimGraph 找 Cast<B_Hero_Default> 节点 → 改 Cast<B_RPG_Character_Base> |
| A3 战斗 | `GCNL_Character_DamageTaken.uasset` | 打开 → 找 Cast 节点 → 改为 RPG 等价类 |
| A4 阵营 | `GE_IsPlayer.uasset` | 同上 |
| A4 UI | `Indicators/NameplateManagerComponent.uasset` / `NameplateSource.uasset` | 同上 |
| A4 设置 | `W_SettingsListEntry_Action/Discrete/KBMBinding/SubCollection.uasset` + `GameSubtitleOptions.uasset` + `W_SafeZoneEditor.uasset` | 同上 |
| A4 BGM | `B_MusicManagerComponent_Base.uasset` | 删 Cast<B_LyraGameInstance> 节点（无功能损失） |
| A3 动画 | `FootstepEffectTagModifier.uasset` | 同上 |

---

## §6 经验沉淀

### 6.1 新增（v1.5 → v1.6 经验补充）

> 改名工程 5 层全清单（在 §6.2 列出）已经成熟。但本次 A2 暴露了**第 6 层**：

**第 6 层 · 加载链路防御层**：
- 像 `RPGAssetManager.LoadGameDataOfClass` 这种"硬错误就 Fatal"的关键加载入口，**应该在改造期间临时加 CDO 兜底**，避免删旧资产/建新资产之间的窗口期锁死 Editor。
- 完成 A2 后可以决定是否回退到 Fatal 行为（建议保留防御层 + 改 Warning，长期更友好）。

### 6.2 改名工程 6 层完整清单（A1+A2 合并经验）

1. **C++ 字符串字面量**（`FName/FString/FPrimaryAssetType` 硬编码）
2. **UPROPERTY Meta 标记**（`AllowedTypes/AllowedClasses/MetaClass`）
3. **资产元数据**（`PrimaryAssetIdRedirects` + `ResavePackages`）
4. **反射显示标签**（`Category=` / `DisplayName=` ~ 135 处）
5. **Editor CDO 行为**（`Within=` 强约束 UCLASS 编辑 CDO 时 GetWorld 崩溃，需 override）
6. **🆕 加载链路防御层**（关键 `Fatal` 加载点改 `Warning + CDO 兜底`，过渡期不锁死）

### 6.3 工具沉淀

`tools/_out/` 下保留以下脚本（供未来类似项目参考）：

| 脚本 | 用途 |
|---|---|
| `_purge_lyra_assets.ps1` | 物理删除资产（支持 -DryRun） |
| `_purge_broken_bps.ps1` | 删除 ResavePackages 暴露的 broken BP |
| `_resave_all.ps1` | ResavePackages 全量重写 |
| `_classify_broken.ps1` | 分类 broken BP（删/保留） |
| `_audit_a2_assets.ps1` | 13 资产位置审计 |
| `_final_audit.ps1` | Content 全局审计（剩余 Lyra* / 13 资产 / Resave 错误） |
| `a2_create_gamedata.py` | Python commandlet 自动建占位 RPGGameData |
| `_purge_lyra_meta.ps1` | 反射元标签 Lyra → RPG 批量清扫 |

---

## §7 变更日志

| 版本 | 日期 | 作者 | 说明 |
|---|---|---|---|
| v1.0 | 2026-05-13 | demo-director + ue-rpg-implementer | Phase A2 首版交付：14 资产 / 删 59 / Config 13 处改 / 0 Fatal / 0 Lyra-PrimaryAssetType-Ignoring |
