# 按键映射为 Escape 时关闭遥控器收音

> 相关: `specs/remote-button-gestures.md`（双击与长按，本次在其之上叠加，未改动其判定逻辑）

## 目标

遥控器的语音键并不总是可靠（X6 第一次短按不产生可靠 HID 边沿，见 `main.swift` 注释）。用户要一个**可靠的刹车键**：不管遥控器当前在不在收音，按它就一定是「没在收音」。

规则：**任何遥控器上的任何按键，只要它的映射目标是 Escape，按下时除了照常发 ESC，还会关闭遥控器语音会话** —— 停止收音、卸掉音频路由、并发出语音输入快捷键让语音 App 停止听写。

**这个键只负责关，不负责开。** 开录音仍由遥控器语音键负责。

## 范围

只改遥控器按键映射这条链路。语音键本身（`voiceKeyPressed`）、X6 的手势分类器、录音（WAV 落盘）、两个 HID 桥接文件全部一行不动。

## 决策记录

| 决策 | 结论 | 依据 |
|---|---|---|
| ESC 还要不要照常发？ | **两个都做**：先发 ESC，再关闭收音 | 用户明确选择 |
| 这个键是「开关」还是「只关」？ | **只关** | 第一版做成了开关（切换），用户验收后指出需求是「无论是否在收音，都关闭」。见下方「一次返工」 |
| 没在收音时按下做什么？ | **什么都不做** | 用户选择。发快捷键"兜底"会往当前 App 里打一个右 Command，可能被误读成别的操作 |
| 开录音由谁负责？ | 遥控器语音键（保持原设计） | 用户选择 |
| 钩子放在哪一层？ | `RemoteMappingStore.fire()` | TypeSafe `jev_decide` 0.95。`RemoteGestureArbiter.begin` 首次以 0.95 胜出，但复核源码后发现它**漏掉了快路**（未配双击/长按时 `edge` 直接调 `store.fire`，不经过 `begin`），补正证据后改判 |
| 怎么进会话状态机？ | `X6SessionCoordinator` 新增 `mappedKeyPressed()` | TypeSafe `jev_decide` 1.00。复用 `voiceKeyPressed` 会继承两道对映射按键不成立的门槛 |

### 一次返工

第一版做成了**切换**：没在收音就开麦，正在收音就关。用户真机验收后明确需求是「只要触发了 Escape 的按键，无论当前遥控器是否处于录音状态，都关闭录音」。

返工带出两个必改的连带问题（见下一节）。

## 关键取舍

### ESC 与关闭是两件事，不是一件事

用户要求 ESC 照发。所以 Escape 映射**不是**被替换掉的动作，而是一个附带副作用的动作。代价：在 Finder 里按返回键会同时返回并关掉遥控器收音。这是有意为之。

### 为什么不能复用 `voiceKeyPressed`

`voiceKeyPressed` 开头有两道门槛：

1. `isPhysicalPress(remote:reason:)` —— Chromecast 只认 reason `0x03`、X6 只认 `0x00`。映射按键没有 BLE reason，伪造不了；硬造一个会让 Chromecast 上的 Escape **完全不生效**。
2. `pressEdgeDebounce` 0.25 秒 —— 这道去重是为「一次物理按压经 BLE audio 和 HID 双通道同时上报」设计的。映射按键不存在双通道问题。

所以新方法只复用后面的状态机（`beginClosing`），两道门槛都不经过。

### 「只关」让两道守卫失去意义，删掉

第一版的 `mappedKeyPressed()` 开头有：

```swift
guard triggerAvailable() else { ... }        // 没配快捷键就不干活
guard let remote = preferredRemoteProvider?() else { ... }  // 没遥控器就不干活
```

这两道都是为**打开**准备的：开麦要把快捷键打出去，而且要指定给哪只遥控器。改成只关之后它们都是错的：

- **关闭不需要语音输入快捷键**。关麦、卸路由是本地动作；`triggerTap()` 自己有 `guard AppStorage.shortcut else { return }`，没配快捷键时它自己会安静地跳过。保留外层守卫会让"没配快捷键就关不掉"。
- **关闭不需要知道是哪只遥控器**。`beginClosing` 走 `closeAllRemoteMicrophones()`，把所有遥控器都关掉。所以遥控器刚断开也不影响刹车能用。

两道守卫已删除，`mappedKeyPressed()` 现在只剩一个 `switch`。

### 为什么放在 `fire()` 而不是 `begin()`

`RemoteGestureArbiter` 有两条路：

- **快路** —— 用户没给这个键配双击/长按时（绝大多数情况），`edge()` 直接 `store.fire(...)`，**不经过 `begin`**
- **手势路** —— 配了手势才走 `begin(button:slot:)`

`store.fire(button:remote:gesture:)` 是「一次完整按压」在两条路上**唯一的共同出口**。放这里，「无论哪个键、哪种手势都生效」就由结构保证，而不是靠记得两处都改。

**长按连发不走 `fire`**（它直接调 `post(isDown:)`），所以按住不会每秒关 60 次。

### 线程

映射按键从遥控器的 HID 队列进来，语音键从主队列进来。会话的 `phase` 是共享状态，钩子在 `main.swift` 里 `DispatchQueue.main.async` 一次，保证两条路从同一个队列进入。

## 文件

| 文件 | 改动 |
|---|---|
| `Sources/vRemote/RemoteMappingSupport.swift` | 新增静态钩子 `onEscapeMapped`；`fire()` 里判断 target == .escape |
| `Sources/vRemote/X6SessionCoordinator.swift` | 新增 `mappedKeyPressed()`（只关） |
| `Sources/vRemote/main.swift` | 启动时把钩子接到 `x6Session`，并切到主队列 |
| `Sources/vRemote/VoiceSessionSelfTest.swift` | 4 条用例 |

`X6HIDBridge` / `ChromecastRemoteHIDBridge` / `RemoteGestureClassifier` / `RemoteGestureArbiter` 未改动。

## 行为变更（需要注意）

1. **所有映射为 Escape 的按键（两种遥控器，含出厂默认的「返回」键）现在每次按下都会关闭遥控器收音。** 对已发布版本是行为变更：此前按下只发 ESC。
2. **这个键不再能打开录音。** 开录音仍靠遥控器语音键。如果语音键本身不可靠，用户需要换一个能可靠上报的键映射成 Escape——但那个键只能关，不能开。
3. `.closing` 阶段的按下被忽略，避免把语音输入快捷键重复打进前台 App。
4. `.closed` 阶段的按下是纯空操作，不发任何按键。

## 自测覆盖

4 条用例覆盖：录音中按下会关闭（语音键开、Escape 关）、没在录音时按下什么都不做、关闭途中的第二次按下不发第二次快捷键、遥控器刚断开也能关闭且最终落到 closed。

**未被覆盖**：`RemoteMappingStore.fire` 的钩子本身需要 `UserDefaults` + `CGEvent`，无框架自测跑不到。真机见下。

## 顺带发现（未修改）

`X6SessionCoordinator.finishClosing()` 先调 `closeRouteAndTransports()`，随后 `finalizeClosed()` 里又调一次，于是 `setRemoteRouteActive(false)` 会走两遍。`setRemoteActive` 是幂等的，线上无影响，但它是既有冗余、不在本次范围内，因此未动。自测里对路由的断言因此只检查「最终为 false」而非「恰好两次数组」。

## 已验证（真机）

第一版（切换语义）在真机上验过一次：Chromecast Remote，映射 `chromecast.08`（静音键）= escape，按下后日志出现 `[VOICE-SESSION] begin closing reason=mapped key toggle`，证明映射按键确实走进了新路径并关掉了会话与音频路由。证据存于 `.verification/20261019T063656Z/`。

**改为「只关」之后尚未重新真机验证。** 需要确认的行为：

- 录音中按 Escape → 真的关闭收音，语音 App 停止听写
- 没在收音时按 Escape → 什么都没发生（不会反向打开录音）
- 两种遥控器都生效（X6 走的是 `s%02X` / `c%X` 报告，Chromecast 走另一条）

按 `.pi/skills/verify-vremoter/SKILL.md` 走。
