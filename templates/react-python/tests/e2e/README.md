// tests/e2e/ 说明

此目录用于存放**集成 / 端到端 / UI 测试**用例，由**独立测试智能体**编写与执行，
开发智能体不得修改本目录（见 docs/01 §2 角色权限）。

约定：
- 用例必须能追溯到 docs/requirements.md 的验收标准编号。
- 必须在隔离 staging 环境运行，绝不连生产。
- `scripts/e2e.sh` 检测到本目录存在时会调用 `npx playwright test`。

建议结构：
```
tests/e2e/
├── playwright.config.ts
├── specs/
│   ├── health.spec.ts
│   └── greeting.spec.ts
└── README.md
```

当前为空占位：`scripts/e2e.sh` 会明确输出"未配置，跳过"，而不是静默变绿。
