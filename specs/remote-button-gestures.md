# 遥控器按键映射支持双击与长按

> 分支: `hotkey-double-tap-longpress`
> 相关: `specs/universal-voice-input.md`（语音触发快捷键，本次**不改动**）

## 目标

调音台（Studio Mixer）里的每个可映射按键，目前只有「按一下」一种触发方式。本次给它加两种：

- **按住连发** — 按住删除键一直删除、按住方向键一直移动，像真键盘。**Delete 和四个方向键，任一槽位映射到就连发**
- **双击** — 一个键当两种键用，遥控器上键少时最实用
- **长按** — 长按才触发的动作（打开菜单、切静音等）

同时补齐映射目标里真实存在的空缺。

## 范围

**只做遥控器按键映射。** 语音触发快捷键（全局监听的那个键）不参与，它走 `X6SessionCoordinator`，且 X6 的语音手势（0.28s 确认 / 0.12s 延迟释放）是已验证路径，本次一行不动。

## 决策记录

| 决策 | 结论 | 依据 |
|---|---|---|
| 单击什么时候发？ | 只配了手势的键才进判定窗口；纯单击的键保持零延迟 | TypeSafe `jev_decide` 选 `instant_tap_unless_configured`，置信度 0.95。`uniform_resolve`（全部键统一等 250ms）被判定为违背「单击不能变慢」，得 0 分 |
| 连发和长按同时存在时？ | 长按优先：配了手势的键不连发 | TypeSafe `jev_decide` 选 `long_press_wins`，置信度 0.96。`repeat_wins` 被判定为「一次按压发出两个动作」，得 0 分 |
| 哪些键连发？ | **映射到 Delete 或四个方向键的**，与遥控器实体键无关；前进删除不算 | 用户确认（先定「所有键默认连发」，后改为只管 Delete，再扩到方向键） |
| 判定逻辑放哪层？ | 新建共享仲裁器，两种遥控器共用 | `jev_decide` 只有 0.41 置信度（`generalize_voice_classifier` 0.51 vs `shared_arbiter` 0.48），**平局不算决策**。按「不碰已验证的语音路径」定夺：映射按键走新仲裁器，X6 的语音分类器保持原样 |
| 新增哪些映射目标？ | A+B+C 共 9 个 | 用户确认。常量全部核对 SDK（`ev_keymap.h` / `Events.h`），未凭记忆取值 |
| 界面形态？ | 每键三个下拉框 | 用户确认 |

## 关键取舍

### 单击零延迟不是免费的

已经 post 给前台应用的按键**无法撤回**。所以「双击时补发一次双击」这条路被否决（`jev_decide` 给 `double_supplement` 0.01，且它会让用户收到两次单击）。代价是：**给某个键配了双击后，它的单击必须等到判定窗口关闭才发出**，多约 0.28s。

这是必然的取舍 —— 第一次按下时无法知道后面还有没有第二次。

### 双击窗口按「抬起→按下」量，不按「按下→按下」

按下→按下的窗口会让**一次快速单击**看起来像双击的前半段。两拍之间必然有抬起，所以抬起→按下是唯一无歧义的量法。

### 长按在按住阈值就发，不等抬手

`tick` 到点即发，用户按住时就有反馈。释放再晚也不补发单击。

### 时钟和释放的竞态

释放发生在阈值后一点点、定时器还没跑时，`release` 必须自己也能判定成长按，否则同一个按压会在单击/长按之间抖动。这条有专门的用例（见 `SelfTests`）。

### 一个键只有一条路径

仲裁器里两条路径互斥，判据是 `repeatingGesture(for:remote:)`：

| 条件 | 走哪条 | 按住行为 |
|---|---|---|
| 单击槽或长按槽映射到 **Delete / 上 / 下 / 左 / 右**（且没配双击） | Hold | 按下即发一次，随后每 60ms 重复一次，抬头发 key-up |
| 其他一切情况 | Gesture | 按现有手势语义判定，**不连发** |

**连发跟映射走，不跟遥控器实体键走。** 把 Home 键改成后退删除，它就开始连发删除；把 Delete 键改成别的，它就恢复单击。代价是「连发」不是一个可以在界面上看到的属性，只是一个映射结果带来的行为 —— 界面上用绿色的「长按·连发」标出长按槽，其余不标。

**长按槽说了就算，不用管单击槽。** 「长按 = 方向左」而「单击 = Escape」是完全合理的搭配：点一下返回，按住连续左移。仲裁器回报的是**槽位**而不是动作，所以连发时发的是长按槽那个动作，单击槽保留自己的含义。

**只有这两类动作会连发。** 其余是开关型动作（音量、播放、显示桌面），按住重复只是噪声。**前进删除明确排除**：它一次删一个词，连发会把文本拆碎。

**配了双击的键不连发。** 双击必须等判定窗口，而按住永远走不到窗口结束那一刻。

**配了其他长按动作的键也不连发。** 那个长按是独立动作，它优先（TypeSafe `long_press_wins`，0.96）。

### 两条路径都能用同一套 down/up 语义

`RemoteMappingTarget.post(isDown:)` 天然适配两种形态，不需要分支：

- **键盘类** — `post(true)` 只发 keyDown。持住 = 一次 down + N 次额外 down（中间无 up，目标应用就把它读成自动重复）+ 一次 up
- **媒体类** — `post(true)` 自身就把 0xA/0xB 一对发完，`post(false)` 是空操作。连发 = 重复调 `post(true)`，音量＋就是一级一级上去

`RemoteCustomShortcut.post(isDown:)` 是同一套语义，所以录制任意组合键（比如 ⌘⌫）也能连发。

### 手势的存储：零迁移

单击继续用原来那个不带后缀的 key（`remoteMapping.<remote>.<button>`），双击/长按才加后缀。存量用户打开就是原样，不需要做任何迁移，也不碰已发布的配置。

未设置的双击/长按**回落到单击映射**，而不是什么都不做 —— 免得用户配了长按就把短按弄丢了。

## 新增映射目标（9）

常量来自 SDK，不是记忆：

| Target | 中文 | 值 | 来源 |
|---|---|---|---|
| `nextTrack` | 下一曲 | `NX_KEYTYPE_NEXT` = 17 | `ev_keymap.h` |
| `previousTrack` | 上一曲 | `NX_KEYTYPE_PREVIOUS` = 18 | `ev_keymap.h` |
| `fastForward` | 快进 | `NX_KEYTYPE_FAST` = 19 | `ev_keymap.h` |
| `rewind` | 快退 | `NX_KEYTYPE_REWIND` = 20 | `ev_keymap.h` |
| `launchPanel` | 调度中心 | `NX_KEYTYPE_LAUNCH_PANEL` = 13 | `ev_keymap.h` |
| `eject` | 推出 | `NX_KEYTYPE_EJECT` = 14 | `ev_keymap.h` |
| `mediaMenu` | 菜单 | `NX_KEYTYPE_MENU` = 25 | `ev_keymap.h` |
| `forwardDelete` | 前进删除 | `kVK_ForwardDelete` = 0x75 | `Events.h` |
| `contextKey` | 菜单键 | `kVK_ContextualMenu` = 0x6E | `Events.h` |

> 注意：没有「停止」——`NX_KEYTYPE_STOP` 不存在，17 是 NEXT。
> B 组（调度中心/推出/菜单）在 macOS 上的实际响应**需要真机验证**，自测覆盖不到。

## 文件

| 文件 | 作用 |
|---|---|
| `Sources/vRemote/RemoteGesture.swift`（新） | `RemoteGesture` + `RemoteGestureClassifier`。**纯 Foundation、无时钟**，所以能被无框架自测覆盖 |
| `Sources/vRemote/RemoteGestureArbiter.swift`（新） | 计时外壳：喂边沿、按 deadline 问一次 |
| `RemoteMappingSupport.swift` | 9 个新 target；手势感知的 `explicitTarget` / `target(…gesture:)` / `armedGestures` / `clearGesture`；`fire(...)` 一次发完 down+up |
| `ChromecastRemoteHIDBridge.swift` / `X6HIDBridge.swift` | `apply()` 改为喂仲裁器 |
| `DebugWindowController.swift` | `MappingRow` 变成三行 |
| `SelfTests/main.swift` + `run-self-tests.sh` | 8 条分类器用例 |

## 行为变更（需要注意）

1. **按住 Delete 和方向键现在会连发。** 这是用户明确要的，但对已发布版本是行为变更：此前两个 bridge 都对重复上报去重，按住只会触发一次。**其他按键的行为完全不变**。
2. **按下与抬起的边界变了。** 连发路径下 `post(true)` 在物理按下时发、`post(false)` 在物理抬起时发（和之前一样），但手势路径的 `fire` 仍在一个瞬间发完 down+up —— 因为长按是在按钮还按着的时候判定的。若将来接入支持连发的设备，需要把手势路径也改成持有 down。
3. **断连时如果键正被按住，会补发 key-up。** 否则目标应用里那个键会永久卡在按下状态。遥控器拔电池 / 蓝牙断开都走 `arbiter.reset()`。
4. **应用在按住状态下退出，key-up 不会发出。** 已知缺口，尚未处理（影响极小：没有任何目标应用会残留状态，且下次该键按下会重新触发）。移除条件：真机验证发现确实有残留。

## 自测覆盖

`RemoteGestureClassifier` 的 8 条用例覆盖：零延迟单击、双击只发一次、未配对的按下最终仍发一次单击、长按在按住时发、阈值竞态、未配长按时长按不冒充长按、长按优先于挂起的单击、窗口外的按下算新手势。

**未被覆盖**：Hold（连发）路径。它需要 Dispatch 定时器 + `UserDefaults` + `CGEvent`，无框架自测跑不到。目前靠三处代码审查保证：按下必发 down、抬起必发 up、`reset()` 会对仍按住的键补发 key-up。`RemoteMappingStore` 同理无法被无框架自测覆盖。

## 未验证

- 0.45s 初延迟 / 60ms 重复间隔是否手感合适（常量在 `RemoteGestureArbiter.repeatDelay` / `repeatInterval`，本机 `KeyRepeat` 与 `InitialKeyRepeat` 均未设置，走 macOS 默认，所以只能靠手感定）
- B 组三个系统键在 macOS 上的真实响应
- 两种遥控器实际按下/抬起的边沿时序是否都足够干净
- 遥控器拔电池 / 走远断连时，key-up 补发是否真的落到了目标应用
- 前进删除不连发这个判断是否也被用户接受（若将来有人抱怨删除太慢，需先区分是后退还是前进删除）

以上都需要真机，按 `.pi/skills/verify-vremoter/SKILL.md` 走。
