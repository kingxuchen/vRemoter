# 按键映射为 Escape 时，同时切换遥控器收音

> 相关: `specs/remote-button-gestures.md`（双击与长按，本次在其之上叠加，未改动其判定逻辑）

## 目标

遥控器的语音键并不总是可靠（X6 第一次短按不产生可靠 HID 边沿，见 `main.swift` 注释）。用户希望有一个**普通按键**也能控制遥控器自己的收音状态，用来顶替语音键。

规则：**任何遥控器上的任何按键，只要它的映射目标是 Escape，按下时除了照常发 ESC，还会切换一次遥控器语音会话** —— 没在收音就开麦并发出语音输入快捷键，正在收音就取消。

## 范围

只改遥控器按键映射这条链路。语音键本身（`voiceKeyPressed`）、X6 的手势分类器、录音（WAV 落盘）、两个 HID 桥接文件全部一行不动。

## 决策记录

| 决策 | 结论 | 依据 |
|---|---|---|
| ESC 还要不要照常发？ | **两个都做**：先发 ESC，再切一次收音 | 用户明确选择。TypeSafe 首次判断只有 0.51 置信度（平局不算决策），已向用户确认 |
| 「录音」是哪一个？ | 遥控器语音会话（开麦 + 语音输入快捷键） | 用户确认，即等同按一下语音键 |
| 要不要留关闭开关？ | 不要，默认生效 | 用户选择；也符合不为单一用例造配置项 |
| 钩子放在哪一层？ | `RemoteMappingStore.fire()` | TypeSafe `jev_decide` 0.95。`RemoteGestureArbiter.begin` 首次以 0.95 胜出，但复核源码后发现它**漏掉了快路**（未配双击/长按时 `edge` 直接调 `store.fire`，不经过 `begin`），补正证据后改判 |
| 怎么进会话状态机？ | `X6SessionCoordinator` 新增 `mappedKeyPressed()` | TypeSafe `jev_decide` 1.00。复用 `voiceKeyPressed` 会继承两道对映射按键不成立的门槛 |

## 关键取舍

### ESC 与切换是两件事，不是一件事

用户要求 ESC 照发。所以 Escape 映射**不是**被替换掉的动作，而是一个附带副作用的动作。代价：在 Finder 里按返回键会同时返回并切一次收音。这是有意为之，不是 bug。

### 为什么不能复用 `voiceKeyPressed`

`voiceKeyPressed` 开头有两道门槛，对映射按键都不成立：

1. `isPhysicalPress(remote:reason:)` —— Chromecast 只认 reason `0x03`、X6 只认 `0x00`。映射按键没有 BLE reason，伪造不了；硬造一个会让 Chromecast 上的 Escape **完全不生效**。
2. `pressEdgeDebounce` 0.25 秒 —— 这道去重是为「一次物理按压经 BLE audio 和 HID 双通道同时上报」设计的。映射按键的两次快速连按是**两次真实按压**，复用会让第二下被吞掉，按键表现得像要故意停顿才有用。

所以新方法只复用后面的状态机（`beginOpening` / `beginClosing`），两道门槛都不经过。`triggerAvailable()` 与「没有遥控器就什么都不做」这两条守卫保留，与语音键一致。

### 为什么放在 `fire()` 而不是 `begin()`

`RemoteGestureArbiter` 有两条路：

- **快路** —— 用户没给这个键配双击/长按时（绝大多数情况），`edge()` 直接 `store.fire(...)`，**不经过 `begin`**
- **手势路** —— 配了手势才走 `begin(button:slot:)`

`store.fire(button:remote:gesture:)` 是「一次完整按压」在两条路上**唯一的共同出口**。放这里，「无论哪个键、哪种手势都生效」就由结构保证，而不是靠记得两处都改。

**长按连发不走 `fire`**（它直接调 `post(isDown:)`），所以按住不会每秒切 60 次会话。这是把钩子放在 `fire` 而不是 `post` 的原因。

### 线程

映射按键从遥控器的 HID 队列进来，语音键从主队列进来。会话的 `phase` 是共享状态，钩子在 `main.swift` 里 `DispatchQueue.main.async` 一次，保证两条路从同一个队列进入。

## 文件

| 文件 | 改动 |
|---|---|
| `Sources/vRemote/RemoteMappingSupport.swift` | 新增静态钩子 `onEscapeMapped`；`fire()` 里判断 target == .escape |
| `Sources/vRemote/X6SessionCoordinator.swift` | 新增 `mappedKeyPressed()` |
| `Sources/vRemote/main.swift` | 启动时把钩子接到 `x6Session`，并切到主队列 |
| `Sources/vRemote/VoiceSessionSelfTest.swift` | 5 条用例 |

`X6HIDBridge` / `ChromecastRemoteHIDBridge` / `RemoteGestureClassifier` 未改动。

## 行为变更（需要注意）

1. **所有映射为 Escape 的按键（两种遥控器，含出厂默认的「返回」键）现在每次按下都会额外切换一次语音会话。** 这是用户明确要的，但对已发布版本是行为变更：此前按下只发 ESC。
2. 未配置语音输入快捷键时，映射按键的行为**完全不变**（只发 ESC，不切会话）—— 没有快捷键时开麦没有意义，与语音键同规则。
3. `.closing` 阶段内的按下被忽略（与语音键一致）。因此「开 → 立刻关」是有效的，但「开 → 关 → 立刻再开」的最后一下会被忽略，需要等关闭落定（约 0.1s，设备被占用时最多 2s）。

## 自测覆盖

5 条用例覆盖：Chromecast 上没有 reason 也能开（回归：无 reason 门槛）、录音中按下会取消且真的关闭麦克风并关掉音频路由、0.05 秒内连按两次都算数（回归：0.25 秒去重不适用于映射按键）、没有遥控器时是安全的空操作、没有快捷键时什么都不发生。

**未被覆盖**：`RemoteMappingStore.fire` 的钩子本身需要 `UserDefaults` + `CGEvent`，无框架自测跑不到。`RemoteGestureArbiter` 同理。真机验证见下。

## 顺带发现（未修改）

`X6SessionCoordinator.finishClosing()` 先调 `closeRouteAndTransports()`，随后 `finalizeClosed()` 里又调一次，于是 `setRemoteRouteActive(false)` 会走两遍。`setRemoteActive` 是幂等的，线上无影响，但它是既有冗余、不在本次范围内，因此未动。自测里对路由的断言因此只检查「最终为 false」而非「恰好两次数组」。

## 已验证（真机）

Chromecast Remote，配对状态，映射 `chromecast.08`（静音键）= escape，语音触发键 = 右 Command，`remoteInputEnabled=1`、`macInputEnabled=0`。

按静音键，`~/Library/Logs/vRemote/vRemote.log` 实际记录：

```
[CAST-MAP] 静音 DOWN -> Escape
[VOICE-SESSION] begin closing reason=mapped key toggle trigger=synthetic
[VOICE-SESSION] audio route OFF
[VOICE-SESSION] closed reason=route closed
[CAST-MAP] 静音 UP -> Escape
```

`reason=mapped key toggle` 只可能来自新增的 `mappedKeyPressed()`，证明映射按键确实走到了新路径并关掉了会话与音频路由。连续两次按下都出现该行（06:38:03、06:38:08）。证据存于 `.verification/20261019T063656Z/`。

该次记录里 `audio route OFF` 连续出现两行，正是上文「顺带发现」的既有重复调用。

**仍未验证**：X6 遥控器上的同样行为（X6 未配对，且走的是另一条 HID 报告路径 `s%02X` 而非 `c%X`）。
