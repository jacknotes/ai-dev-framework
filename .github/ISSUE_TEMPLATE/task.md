---
name: 功能任务
about: 由编排器拆解出的可独立验收任务
title: "[feat] "
labels: ["task"]
---

## 关联

- 需求编号：REQ-____（对应 `docs/requirements.md`）
- 依赖 Issue：#____

## 验收标准（必须可测）

- [ ] 
- [ ] 

## 归属

| 项 | 值 |
|---|---|
| 负责角色 | 前端 / 后端 / 架构 / 测试 / 安全 / 运维 |
| 可修改目录 | 例如 `frontend/` |
| 涉及契约 | `docs/api-spec.yaml` 中的 ____ 接口 |

## 门禁（由 CI 自动判定，勿手填）

- [ ] `scripts/lint.sh` 通过
- [ ] `scripts/build.sh` 通过
- [ ] `scripts/test.sh` 通过
- [ ] 独立评审通过（0 Critical/High）
