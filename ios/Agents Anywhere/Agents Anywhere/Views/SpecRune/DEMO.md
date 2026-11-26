# 任务流视觉 Demo（保留分支，不合并）

SpecRune「任务流」视图的 iOS 视觉复刻。作为**跨端美术资产**长期保留，Android / Web 后续按同一份数值实现。

## 怎么打开

- App 右下角「任务流 Demo」按钮；或
- 启动参数 `--flow-demo` 直接进入 demo，可叠加：
  - `--flow-demo-panel` 自动弹出一个节点的面板
  - `--flow-demo-compose` 面板直接进 Message 输入态

## 资产文档

- 完整清单、Compose 对照表、与原版的已知差异：Agents-Anywhere 仓库 `.specrune/tasks/11-25-ios-specrune-workflow-graph/visual-assets.md`
- 机器可读 token（色板 / 尺寸 / 动效 / 波形基准点）：同目录 `flow-visual-tokens.json`
- 上游来源：`affectui-showcase/src/components/pro/agent-crew.tsx`（minified 原组件）、SpecRune `plugins/dsh/panel/lib/client.js` 的 `FLOW_THEME_CSS`、`.specrune/spec/backend/dsh-panel-visual.md`

## 关键实现位置

| 文件 | 内容 |
| --- | --- |
| `SpecRuneFlowTokens.swift` | 两套主题色、阶段色、尺寸、动效参数 |
| `SpecRuneFlowDemoView.swift` | 画布（UIScrollView）、节点卡、连线 / 8 层光带 / 三向地面闪光、节点面板（含 Message 输入框） |
| `Views/RootView.swift` | demo 入口按钮与启动参数 |

## 注意

**不要合并到 main。** 正式实现时以 `flow-visual-tokens.json` 为准重新落地，本分支只作视觉参考与回归对照。
