# Implementation Plan: 通用语音输入（语音目标解耦 + 可录制语音触发键）

> Spec: `specs/universal-voice-input.md`
> 任务清单: `tasks/todo.md`（项目未指定外部 tracker，故用默认文件清单）

## Overview

vRemoter 现有能力已能把遥控器麦克风与 MacBook 麦克风混合送进 CoreAudio 输入设备 `vRemoteDr 2ch`，但会话状态机把「豆包输入法进程是否在录音」当成唯一真相来源，导致换任何其他语音输入法都完全不可用。同时语音键发哪个快捷键是写死的 5 项枚举，且因取值缺陷永远发不出右 Control。本次把会话所有权收回 vRemoter 自己，把快捷键改成用户录制任意组合，并加一道「关闭前确认设备仍被占用」的安全网。

## 已验证的构建与测试命令

| 命令 | 用途 | 实测 |
|---|---|---|
| `./run-self-tests.sh` | 无框架纯逻辑自测（ATVV 协议 + 本次新增） | exit 0，3 项 |
| `swift run vRemote --voice-session-self-test` | 会话状态机自测（DEBUG，退出码即结果） | exit 0，10 项 |
| `swift build` | 编译 | exit 0 |
| `./package-app.sh` | 发布构建 + app bundle + ad-hoc 签名 | 未实跑 |

## 依赖图

```
T1  Shortcut 值类型 + 3 个纯函数 + 迁移判据纯函数
      │
      ├── T2  存储 / 合成切换 / 迁移执行
      │         │
      │         └── T3  录制拾取 UI + 回显 + 未配置态   ◄── 垂直切片完成
      │
T4  占用探针（CoreAudio 枚举 + 排除自身）
      │
      ├── T5a 状态机改由语音键驱动（脱离豆包状态）
      │         │
      │         └── T5b 接入占用守卫 + 尾巴延迟
      │
T6  文案去豆包化 + 配置指引
```

T6 不依赖任何任务，可全程并行。

## 架构决策

- **会话所有权归 vRemoter。** 语音键按下即开麦并发快捷键，再按一下即发快捷键并关麦。不再由任何目标应用的进程状态驱动。既有阶段机、generation 计数、有限重试框架全部复用，只换驱动信号。
- **快捷键是用户录进来的数据，不是代码常量。** 引入 `(keyCode, modifierFlags)` 纯值类型替代 5 项枚举。删除枚举同时消除了 `min()` 永远取左键码的缺陷——不是单独修 bug，是结构上不再存在一对多表示。
- **占用检查限定在会话窗口内。** 若 `vRemoteDr 2ch` 被设为系统默认输入，菜单栏与 Siri 会持续持有它，无限定会导致麦克风永远无法关闭。
- **注入契约不变。** 会话协调器今天已把全部协作者以注入契约接收，既有测试装配方式不受影响。这是本次最大的省力点。
- **零新缝优先。** 会话状态机复用既有自测缝；只新开 2 个缝（Shortcut 纯值、迁移纯函数），理由见 spec Testing Decisions。

## Task List

### Phase 1: 快捷键值模型

- [ ] Task 1: Shortcut 值类型与纯函数
- [ ] Task 2: 存储与合成切换，含存量迁移
- [ ] Task 3: 录制拾取界面

### Checkpoint: 快捷键切片完成

- [ ] `./run-self-tests.sh` 通过
- [ ] `swift run vRemote --voice-session-self-test` 通过
- [ ] 真机：录制一个带主键的组合，语音键按下发出的是它
- [ ] 真机：1.1.1 存量配置升级后行为不变
- [ ] 人工评审

### Phase 2: 占用探针与会话解耦

- [ ] Task 4: CoreAudio 占用探针
- [ ] Task 5a: 状态机改由语音键驱动
- [ ] Task 5b: 接入占用守卫与尾巴延迟

### Checkpoint: 会话解耦完成

- [ ] `swift run vRemote --voice-session-self-test` 全部通过（含新增用例）
- [ ] 真机：不装豆包，Type4Me 选 `vRemoteDr 2ch` 后遥控器收音可被录到
- [ ] 真机：停录后遥控器麦克风确实释放（指示灯灭）
- [ ] 人工评审

### Phase 3: 文案

- [ ] Task 6: 文案去豆包化与配置指引

### Checkpoint: 完成

- [ ] 全部验收标准满足
- [ ] `./run-self-tests.sh`、`swift run vRemote --voice-session-self-test`、`swift build` 全绿
- [ ] 提交前 `specs/` 与 `tasks/` 一并入库

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| 存量用户判据不可靠（「有无其他 vRemoter 设置」） | 高 — 存量豆包用户升级后突然失灵 | 1.1.1 的触发键下拉框默认值不写存储，绝大多数存量用户会被误判为全新安装。Task 2 必须先跑通判据；若真机上不可靠，**立即停下问用户，不得静默改变行为**（spec 已写明） |
| 状态机改写造成回归 | 高 — 1.1.1 已发布，既有 10 个测试覆盖已验证行为 | 既有测试**逐条改写而非删除**；Task 5a 单独成任务，改完立刻跑自测；不与守卫混在同一次改动 |
| 占用探针枚举不到全部持设备进程 | 中 — 安全网失效 | Task 4 单独落地先验证。若枚举不可靠，安全网降级为尾巴延迟（spec 已将尾巴列为补充而非替代），并在 Further Notes 记录 |
| 合成任意组合不被目标应用识别 | 中 — 自测无法覆盖 | CGEvent 把修饰标记设在主键事件上，理论上等效，但必须在真机上用 Type4Me 验证（spec User Stories 26）。这是自测的盲区，走真机验收 |
| 用户未在目标应用里选 `vRemoteDr 2ch` | 高 — 上线后最可能被误报为 bug | Task 6 的指引文案必须显眼并写出确切设备名。这步应用代劳不了 |
| 尾巴延迟时长未定 | 低 | spec 只写「一小段」，实现时按实测录音收尾时长定；若拿不到实测值则先取保守值并在 Further Notes 标注为待调 |

## Open Questions

- 占用探针能否可靠枚举到所有持有 `vRemoteDr 2ch` 的进程？（Task 4 会给出答案）
- 「有无其他 vRemoter 设置」能否在真机上稳定区分存量与全新安装？（Task 2 会给出答案；不成立则停下问用户）
- 尾巴延迟具体时长需要一次真机录音收尾时长的实测，目前无数据。

## Parallelization

- Task 6 与其余任务无依赖，可全程并行。
- Task 4 与 Task 1–3 无依赖，可并行。
- Task 2 必须先于 Task 3：没有存储与合成切换，录制界面没有生效对象，且迁移必须与切换同批落地，否则存量用户会在中途失灵。
- Task 5a 与 5b 必须串行：守卫接入的前提是状态机已由语音键驱动。
