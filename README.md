# MemPulse

macOS 原生应用内存排行榜。SwiftUI + AppKit + libproc，无第三方依赖，支持 macOS 13+。

## 使用

需要 Xcode 或含 macOS SDK 的 Swift 工具链。

```sh
swift run MemPulse --snapshot
swift run MemPulse --snapshot --json
swift run MemPulse
```

构建可双击的本机应用：

```sh
sh scripts/build-app.sh
open dist/MemPulse.app
```

产物：`dist/MemPulse.app`。仅做本机 ad-hoc 签名；对外分发还需开发者签名和公证。未开启 App Sandbox，无需 root、辅助功能或屏幕录制权限。

## 统计规则

- 总量为已归属进程的 `ri_phys_footprint` 之和，包含内核记账中的压缩内存等负担；不是 RSS，也不是关闭 App 必然释放的 RAM。
- 所有进程优先继承父进程的应用归属，沿有效父链解析到最上层可识别的 App；Python.app 等中间运行时包不会截断归属。UI 标注“父进程优先”和归属祖先 PID。
- 父链无法提供归属时，才用自身可执行路径中的最外层 `.app` 兜底。父进程缺失、启动时间异常或循环会中断追溯。
- 统计反映当前父子关系：终端直接启动的程序也会计入终端；被 launchd 接管的进程无法恢复原启动者。
- 同名应用按安装路径区分；每个进程只计一次。
- 系统 WebKit/XPC 等无可靠归属的服务留在“未归属进程”。第一版不保证 Safari 完整覆盖。
- 不可读内存保持未知，分组标记统计不完整；基础信息读取失败、退出或采样间 PID 重用的进程跳过并计数。
- 使用 PID 和启动时间标识进程，内存读取前后验证身份；整机快照不是原子的。
- 默认每轮结束后 2 秒再采样，窗口隐藏或最小化时降为 10 秒。暂停保留上次数据。
- 搜索匹配应用、进程名或 PID，保留命中应用的完整明细和总量。

## 应用图标

图标采用深紫底、青到品红渐变的霓虹内存芯片与发光心电脉冲线，源图为 `Assets/MemPulse.png`，macOS 图标为 `Assets/MemPulse.icns`。构建脚本自动打包图标。

重新绘制（使用 AppKit 矢量几何，无第三方依赖）：

```sh
swift scripts/draw-icon.swift
iconutil -c icns Assets/MemPulse.iconset -o Assets/MemPulse.icns
```

## 测试

```sh
swift test
swift build -c release
```

测试覆盖 Helper 合并、外部后代、父进程优先、Python 包继承、缺失父进程兜底、祖先循环、PID 重用、不完整统计和不同安装路径。
CLI JSON 包含原始内存字节数、进程身份、路径、归属理由及错误码，可用于逐进程核对。活动监视器可能有采样时刻与口径差异，不能要求数值完全相同。
