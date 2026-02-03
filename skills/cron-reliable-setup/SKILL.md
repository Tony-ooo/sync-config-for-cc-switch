---
name: cron-reliable-setup
description: 创建符合 OpenClaw “五重保险”高可靠标准的定时任务。当需要添加一次性提醒或周期性 Cron 任务时使用，确保任务在隔离会话执行。触发词包含：'提醒我几点...'、'多少(分钟/小时)后提醒我...'、'帮我添加一个定时任务...' 等。包含强制的时区设置 (Asia/Shanghai)、秒级触发 (wake now) 以及 Telegram 强推配置。
---

# Cron Reliable Setup (五重保险规范)

本技能旨在将 OpenClaw 定时任务的添加流程标准化，确保在任何高负载或心跳冲突场景下，任务均能准时触发并成功触达用户。

## 核心原则：五重保险 (The Five Layers)

执行任何 `openclaw cron add` 命令时，必须包含以下五个维度：

1.  **隔离执行 (`--session isolated`)**：
    由于主会话（main）在心跳爆发或长任务期间会产生 Lane 阻塞，**所有**定时任务必须在独立子代理中运行。
2.  **秒级触发 (`--wake now`)**：
    强制将 `wakeMode` 设为 `now`，确保任务到点立即唤醒，不受系统默认心跳轮询周期（next-heartbeat）的延迟干扰。
3.  **结果回传 (`--post-mode full`)**：
    开启隔离会话的完整回传模式，确保子代理执行任务的过程和结果能立即“投递”回主聊天窗口。
4.  **强力触达 (`--deliver --channel telegram`)**：
    在 Payload 中显式配置渠道强推，即便会话同步链路出现瞬时波动，消息依然能穿透网关直达手机。
5.  **时区锚定 (`--tz Asia/Shanghai`)**：
    无论任务是相对时长还是具体时刻，强制锁定上海时区，防止基础设施漂移导致时间偏差。

## 使用指南

### 1. 添加一次性提醒
适用于“20分钟后提醒我喝水”或“今天 18:00 记得打卡”等场景。

**模板(严格遵守，所有参数都是必备参数，不可遗漏)：**
```bash
openclaw cron add \
  --name "任务名称" \
  --at "+相对时间 or 精确时间" \
  --tz "Asia/Shanghai" \
  --agent main \
  --session isolated \
  --message "提醒/指令内容" \
  --wake now \
  --deliver \
  --channel telegram \
  --delete-after-run \
  --post-mode full
```

### 2. 添加周期性 Cron 任务
适用于日常自动化运维、定时推送简报等场景。

**模板(严格遵守，所有参数都是必备参数，不可遗漏)：**
```bash
openclaw cron add \
  --name "任务名称" \
  --cron "分 时 日 月 周" \
  --tz "Asia/Shanghai" \
  --agent main \
  --session isolated \
  --message "指令/任务内容" \
  --wake now \
  --deliver \
  --channel telegram \
  --post-mode full
```

## 注意事项
- **严格遵循模版**: 对应上述两类定时任务模版中的所有参数都是必备参数，不可遗漏。
- **拒绝口头完成**：技能执行者在添加任务后，必须立即运行 `openclaw cron list` 确认任务已物理挂载。
- **Payload 完整性**：确保 `--message` 后的指令足够清晰，因为独立子代理将基于此消息完全自治地完成任务。
- **Agent 锁定**：必须显式使用 `--agent main`，确保调度器正确识别发起主体。
- **强制验证**：任务添加成功后，必须配合 `openclaw cron list` 物理核验 ID、触发时间及参数准确性。

