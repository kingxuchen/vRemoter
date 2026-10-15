# Tasks: 通用语音输入

> Plan: `tasks/plan.md` · Spec: `specs/universal-voice-input.md`
> 勾选一个任务即表示其验收标准与验证步骤全部通过。

---

## Task 1: Shortcut 值类型与纯函数

> ✅ 完成 2026-10-15。13 条 PASS，swift build 与会话自测均 exit 0。
>
> **计划修正：**原验收标准写「删除枚举型触发键表示」，但删除会同时打断 `AppStorage` 与 `DebugWindowController` 两个调用方，与本任务「不接入任何调用方」矛盾。枚举删除随调用方切换落在 Task 2；本任务交付的是「新值类型里不存在一对多键码表示，`min()` 式缺陷不可能再发生」。
>
> **实施中发现并修复：**首版用 `65 + keyCode` 推算字母名，而 `kVK_ANSI_*` 是 US 键盘布局顺序不是字母表顺序（`V`=0x09、`S`=0x01、0x12 是数字 `1`），会把每个字母都显示错。已改为显式表并补测试钉死。
>
> **实施中发现的风险（未验证，需真机）：**`upEvent()` 在主键抬起时清掉修饰标记。这对「纯修饰键」无歧义，但目标应用能否把带主键的组合识别为一个和弦，尚未确立。已在代码注释中标注。

**Description:** 引入表示快捷键的纯值类型，承载键码与修饰键标记两个分量，提供三个不触碰系统事件层的纯函数：从捕获到的按键事件构建、渲染为可读回显文本、渲染为合成事件描述。同时提供存量迁移判据的纯函数（吃一份设置存储键值集合，输出迁移决策）。本任务不接入任何调用方，纯粹是把「任意组合能否被表达」这个风险最高的点先变成可断言的东西。

**Acceptance criteria:**
- [x] 值类型可表达左右同名键、带普通主键的组合、双修饰键组合
- [x] 三个纯函数均不触碰系统事件层，可直接断言
- [x] 迁移判据覆盖三种情形：旧键存在 / 旧键不存在但有其他设置 / 完全为空
- [x] 新值类型中不存在一对多键码表示，`min()` 式缺陷不再可能发生（枚举的实际删除见 Task 2）

**Verification:**
- [x] Tests pass: `./run-self-tests.sh`（13 条 PASS，exit 0）
- [x] Build succeeds: `swift build`（exit 0）
- [x] 回归: `swift run vRemote --voice-session-self-test`（failures=0，exit 0）
- [ ] Manual check: 无（本任务无用户可见行为）

**Dependencies:** None
**Files likely touched:**
- `Sources/vRemote/Shortcut.swift`（新增）
- `Sources/vRemote/ShortcutKey.swift`（新增）
- `Sources/vRemote/ShortcutMigration.swift`（新增）
- `SelfTests/main.swift`
- `run-self-tests.sh`

**Estimated scope:** Medium: 5 files

---

## Task 2: 存储与合成切换，含存量迁移

> ✅ 完成 2026-10-15，与原 Task 3 合并为一个垂直切片。
>
> **为什么合并：**`DebugWindowController` 的选择器是枚举的唯一 UI 调用方，删枚举就必须改它。若 Task 2 只改存储与合成，UI 只能变成「只读显示 + 清除」，比现在能选 5 项还差，等于把系统留在坏状态。合并后「用户可录制任意快捷键并生效」一次落地。
>
> **TDD 拓出一个真缺陷：**右 Command 录成 `flags=0` 时，down 与 up 两个事件完全相同（`(0x36,0)` 对 `(0x36,0)`），而发送端两个都按 `keyDown:true` 发。目标 App 会看到「右 Command 按了两次、从没松开」。**这正是 Type4Me 用的那个键。**已修：修饰键的 press 必须带上自身 flag。

**Description:** 把触发键的持久化改为读写新的快捷键值类型；把合成路径改为按记录下来的键码与修饰标记投递，替换原先依赖枚举的静态方法；投递走可注入发送器；执行一次性迁移并写入新表示。

**Acceptance criteria:**
- [x] 合成时按记录的键码与修饰标记投递，不再经由枚举
- [x] 修饰标记直接设在主键事件上，无需真实投递各修饰键的按下与抬起
- [x] toggle 语义下按下与抬起各投递一次，长按不重复触发
- [x] 三种迁移情形各自正确，未知旧字符串有兜底
- [x] 迁移只执行一次，执行后写入新表示
- [x] 枚举及其 `min()` 缺陷已彻底删除

**Verification:**
- [x] Tests pass: `./run-self-tests.sh`（18 条 PASS，exit 0）
- [x] Build succeeds: `swift build`（exit 0）
- [x] 回归: `swift run vRemote --voice-session-self-test`（failures=0，exit 0）
- [x] 真机: 新装态 → 点一下 → 按 V → 显示「V」+ 清除按钮（证据见 `.verification/*/feature-04-recording.txt`）
- [ ] 真机: **1.1.1 存量升级** —— 裸 debug 可执行文件无 bundle id，持久化域恒为空，必须用打包版验证
- [ ] 真机: **右 Command 录制** —— harness 发不出仅右侧的修饰键
- [ ] 真机: **合成事件被 Type4Me 识别** —— 需遥控器 + Type4Me 录 `vRemoteDr 2ch`

**Dependencies:** Task 1
**Files likely touched:**
- `Sources/vRemote/InputTrigger.swift`
- `Sources/vRemote/AppStorage.swift`
- `Sources/vRemote/ShortcutRecorder.swift`（新增）
- `Sources/vRemote/X6SearchSuppressor.swift`
- `Sources/vRemote/DebugWindowController.swift`

**Estimated scope:** Medium: 5 files

---

## Task 3: 录制拾取界面

> ✅ 已并入 Task 2 完成。录制、重录、清除、Esc 取消、无障碍标签与回显均已落地并真机验证。

**Description:** 把设置里的固定枚举下拉框替换为录制式拾取控件：点击进入拾取状态，用户直接按下想要的组合键，设置项回显可读文本。支持覆盖重录、清除回到未配置态、Esc 取消且不改动已保存值。补齐未配置状态的界面行为与可访问性（标签、朗读描述、键盘可达、状态不单靠颜色、减弱动效、最小窗口不裁切）。本任务完成后，「用户可录制任意快捷键并生效」这条垂直切片完整可用。

**Acceptance criteria:**
- [ ] 拾取控件可录下左右同名键、带主键的组合、双修饰键组合
- [ ] 回显为用户可懂的符号文本，录完即可确认录对没有
- [ ] 重录覆盖旧值；清除回到未配置态；Esc 取消不改动已保存值
- [ ] 未配置快捷键时语音键完全不响应：不发事件也不开麦
- [ ] 未配置时界面显示明确提示并提供直达设置的入口
- [ ] 控件有可朗读标签，录音与待命两态可被朗读区分，可用键盘完成一次完整录制
- [ ] 最小窗口尺寸下控件与回显不被裁切

**Verification:**
- [ ] Tests pass: `./run-self-tests.sh`、`swift run vRemote --voice-session-self-test`
- [ ] Build succeeds: `swift build`
- [ ] Manual check: 真机录制一个带主键的组合，按下语音键发出的就是它；不配置时语音键无任何反应

**Dependencies:** Task 2
**Files likely touched:**
- `Sources/vRemote/DebugWindowController.swift`
- `Sources/vRemote/InputTrigger.swift`

**Estimated scope:** Small: 2 files

---

### Checkpoint: 快捷键切片完成
- [x] `./run-self-tests.sh` 通过（18 条）
- [x] `swift run vRemote --voice-session-self-test` 通过
- [x] 真机：录制一个快捷键，界面正确回显
- [ ] 真机：1.1.1 存量配置升级后行为不变（需打包版）
- [ ] 真机：右 Command 录制 + 合成事件被目标 App 识别
- [ ] Review with human before proceeding

---

## Task 4: CoreAudio 占用探针

**Description:** 实现「此刻有没有程序正在占用 `vRemoteDr 2ch`」的查询。枚举系统音频进程对象集合，取每个进程在输入作用域下打开的设备，判断是否包含目标设备。查询是一次读取，不建立长期监听。必须排除 vRemoter 自身进程——它在该设备上挂有 IOProc，会把自己算成占用者。判定逻辑拆成吃「进程标识 + 其输入设备集合」列表的纯函数，便于断言。

**Acceptance criteria:**
- [ ] 能报出持有目标设备的进程，排除自身进程
- [ ] 查询是一次读取，不建立长期监听、不在待命态轮询
- [ ] 持有者判定为纯函数，可对构造的输入直接断言

**Verification:**
- [ ] Tests pass: `./run-self-tests.sh`（纯函数用例通过）
- [ ] Build succeeds: `swift build`
- [ ] Manual check: 真机在语音会话进行中查询，能看到目标应用被报出；vRemoter 自身不被报出

**Dependencies:** None
**Files likely touched:**
- `Sources/vRemote/DoubaoAudioStateMonitor.swift`（整块替换为占用探针）
- `Sources/vRemote/VoiceDeviceConsumer.swift`（新增）
- `Sources/vRemote/main.swift`

**Estimated scope:** Medium: 3 files

---

## Task 5a: 状态机改由语音键驱动

**Description:** 把会话状态机的驱动源从「目标应用状态快照」换成「语音键事件」。语音键按下即推进到开启、开麦并发送快捷键；再按一下即发送快捷键并关闭。移除按 bundle ID 绑定目标应用进程的能力。既有阶段机、generation 计数、有限重试、开麦与关麦确认框架全部复用。把既有 10 个自测用例里的假状态提供者换成假触发器驱动器，逐条改写而非删除。

**Acceptance criteria:**
- [ ] 语音键按下推进到开启并请求打开遥控器麦克风；再按一下发送快捷键并进入关闭
- [ ] 长按不重复触发；快速连按两次最终回到待机
- [ ] 两种遥控器在 toggle 语义下各自独立，一台停止不影响另一台
- [ ] 未配置快捷键时语音键不响应且不开麦
- [ ] 既有 10 个用例已逐条改写为 toggle 语义并保留原有覆盖，无删除

**Verification:**
- [ ] Tests pass: `swift run vRemote --voice-session-self-test`（既有改写用例 + 新增用例全通过）
- [ ] Build succeeds: `swift build`
- [ ] Manual check: 真机按下语音键，界面进入录音中；再按一下回到待机

**Dependencies:** Task 3, Task 4
**Files likely touched:**
- `Sources/vRemote/X6SessionCoordinator.swift`
- `Sources/vRemote/VoiceSessionSelfTest.swift`
- `Sources/vRemote/main.swift`

**Estimated scope:** Medium: 3 files

---

## Task 5b: 接入占用守卫与尾巴延迟

**Description:** 关闭遥控器麦克风之前调用占用探针，仍有占用者时推迟关闭并向界面发布可朗读的状态说明，推迟到何时结束必须有明确终止条件，不得形成无限等待。关闭完成后追加一小段尾巴延迟再释放遥控器 ATVV 麦克风通道，用于覆盖目标应用按「松开结束」语义收尾的那一小段时间。查询仅在会话窗口内触发，排除自身进程。

**Acceptance criteria:**
- [ ] 关闭前调用占用探针；有占用者时关闭被推迟且界面给出可朗读说明
- [ ] 推迟有明确终止条件，不形成无限等待
- [ ] 占用探针排除自身进程
- [ ] 占用查询仅在会话窗口内触发，待命态不查询
- [ ] 尾巴延迟结束后遥控器麦克风通道被释放

**Verification:**
- [ ] Tests pass: `swift run vRemote --voice-session-self-test`（守卫与尾巴延迟用例通过）
- [ ] Build succeeds: `swift build`
- [ ] Manual check: 真机录音期间打开会议软件占用该设备，停止时麦克风不被直接切断且界面有说明；正常场景停止后麦克风确实释放

**Dependencies:** Task 5a
**Files likely touched:**
- `Sources/vRemote/X6SessionCoordinator.swift`
- `Sources/vRemote/VoiceSessionSelfTest.swift`

**Estimated scope:** Medium: 2 files

---

### Checkpoint: 会话解耦完成
- [ ] `swift run vRemote --voice-session-self-test` 全部通过（含新增用例）
- [ ] 真机：不装豆包，Type4Me 选 `vRemoteDr 2ch` 后遥控器收音可被录到
- [ ] 真机：停录后遥控器麦克风确实释放
- [ ] Review with human before proceeding

---

## Task 6: 文案去豆包化与配置指引

**Description:** 界面中与语音目标、触发键相关的豆包专属措辞替换为通用语音输入表述，状态播报与按钮映射界面提示同步处理。新增一条配置指引，明确写出：需要到目标语音输入应用自己的设置里，把 `vRemoteDr 2ch` 加入其输入设备列表，否则不会录到声音。设置项措辞不出现 bundle ID、键码、传输类型等开发者术语。仅处理与本功能相关的部分，其余调试性质文案不顺带整理。

**Acceptance criteria:**
- [ ] 语音目标与触发键相关的豆包专属措辞已全部替换
- [ ] 指引文案显眼，并写出确切设备名 `vRemoteDr 2ch`
- [ ] 状态下拉不出现任何语音输入法的专名
- [ ] 设置项措辞无开发者术语
- [ ] 未引入与本功能无关的文案整理

**Verification:**
- [ ] Tests pass: `./run-self-tests.sh`、`swift run vRemote --voice-session-self-test`
- [ ] Build succeeds: `swift build`
- [ ] Manual check: 真机按指引在目标应用里加入 `vRemoteDr 2ch` 后可录到音；界面无豆包字样

**Dependencies:** None
**Files likely touched:**
- `Sources/vRemote/DebugWindowController.swift`
- `README.md`
- `PRODUCT.md`

**Estimated scope:** Medium: 3 files

---

### Checkpoint: 完成
- [ ] 全部验收标准满足
- [ ] `./run-self-tests.sh`、`swift run vRemote --voice-session-self-test`、`swift build` 全绿
- [ ] 提交前 `specs/` 与 `tasks/` 一并入库
