// ============================================================
// 最小闭环流水线编排脚本（DSH Workflow）
// 用途：串起 "需求→架构→编码→评审→测试→安全→部署→交付" 的 POC 闭环
//
// 使用说明：
//   1. 在 DSH 中新建 workflow，粘贴本文件内容（去掉本注释亦可保留）。
//   2. 将 meta 替换为你的项目名；args 传入你的项目信息。
//   3. 运行：workflow 会依次调度各角色子智能体，每个智能体按 prompts/ 下的模板工作。
//
// 注意：本脚本是"编排骨架"。真实执行时，每个 agent() 的 prompt 应引用
//   prompts/ 目录里对应角色模板 + 传入项目上下文。这里为可读性内联了要点。
// ============================================================

export const meta = {
  name: "ai-dev-pipeline",
  description: "AI 多智能体协同开发最小闭环：需求→架构→编码→评审→测试→安全→部署→交付",
  phases: [
    { title: "需求澄清" },
    { title: "架构设计" },
    { title: "任务拆解" },
    { title: "并行编码" },
    { title: "代码评审" },
    { title: "集成测试" },
    { title: "安全测试" },
    { title: "部署" },
    { title: "交付" },
  ],
};

// ---- 各角色提示词（从 prompts/ 目录加载后的精简内联版）----
// 生产使用建议：让 agent() 读取文件内容，而不是硬编码在这里。

const ROLE = {
  pm: `你是产品经理智能体。阅读原始需求，产出含"可测验收标准"的需求文档，写入 docs/requirements.md。只产出文档，不写代码。`,
  architect: `你是架构师智能体。基于 docs/requirements.md 完成技术选型、系统架构图(Mermaid)、接口契约(OpenAPI)，写入 docs/architecture.md 和 docs/api-spec.yaml。只产出设计，不写实现代码。`,
  frontend: `你是前端开发智能体。严格遵循 docs/api-spec.yaml，只修改 frontend/ 目录，编写代码与单元测试，跑通 lint/build/单测后提交 PR。不碰后端与测试用例。`,
  backend: `你是后端开发智能体。严格遵循 docs/api-spec.yaml，只修改 backend/ 目录，编写代码与单元测试，跑通 lint/build/单测后提交 PR。不碰前端与测试用例。`,
  reviewer: `你是独立代码评审智能体。只读代码，按正确性/契约/安全/质量/测试/性能六维审查，分级 Critical/High/Medium/Low，产出评审报告。Critical/High 必须驳回。`,
  qa: `你是独立测试智能体。只读代码+可执行测试，在隔离 staging 环境做功能/集成/UI/性能测试，产出报告。绝不修改业务代码，绝不让用例"变绿"。`,
  security: `你是安全红队智能体。以黑盒方式对 staging 做 OWASP Top 10 扫描、依赖审计、渗透，产出安全报告。绝不接触生产，绝不修改代码。`,
  devops: `你是运维智能体。用声明式方式把已验证产物部署到 staging，做健康检查，产出可复用 runbook。不修改业务逻辑，生产需人类审批。`,
};

// ---- 门禁检查函数：简化版，真实项目应调用 CI/工具 ----
function gatePass(stage, detail) {
  log(`[门禁] ${stage}: ${detail}`);
  return true; // POC 阶段默认通过；真实项目接入 lint/test/scan 结果
}

// ---- 主流程 ----
phase("需求澄清");
const requirements = await agent(
  `${ROLE.pm}\n\n原始需求：${args.requirement}\n\n完成后返回需求文档摘要。`
);
log(`需求文档产出：${requirements?.slice(0, 200) || "（无输出，需检查）"}`);
if (!gatePass("需求澄清", "含可测验收标准")) return { ok: false, at: "需求澄清" };

phase("架构设计");
const architecture = await agent(
  `${ROLE.architect}\n\n需求文档：${requirements}\n\n完成后返回架构设计与接口契约摘要。`
);
log(`架构产出：${architecture?.slice(0, 200) || "（无输出）"}`);
if (!gatePass("架构设计", "契约一致性")) return { ok: false, at: "架构设计" };

phase("任务拆解");
const tasks = await agent(
  `你是编排器。基于以下架构与需求，拆解成可独立验收的任务 Issue 列表（含验收标准、依赖）。\n\n需求：${requirements}\n架构：${architecture}`
);
log(`任务拆解：${tasks?.slice(0, 200) || "（无输出）"}`);

phase("并行编码");
// 前后端并行开发（各自独立，互不阻塞）
const [frontendResult, backendResult] = await parallel([
  () => agent(`${ROLE.frontend}\n\n接口契约与架构：${architecture}\n\n任务：${tasks}\n\n完成后返回改动摘要与自测结果。`, { label: "前端开发" }),
  () => agent(`${ROLE.backend}\n\n接口契约与架构：${architecture}\n\n任务：${tasks}\n\n完成后返回改动摘要与自测结果。`, { label: "后端开发" }),
]);
log(`前端：${frontendResult?.slice(0, 150) || "（无输出）"}`);
log(`后端：${backendResult?.slice(0, 150) || "（无输出）"}`);
if (!gatePass("编码", "lint/build/单测")) return { ok: false, at: "编码" };

phase("代码评审");
const review = await agent(
  `${ROLE.reviewer}\n\n前端改动：${frontendResult}\n后端改动：${backendResult}\n\n完成后返回评审结论（通过/驳回）。`
);
log(`评审结论：${review?.slice(0, 200) || "（无输出）"}`);
if (!gatePass("代码评审", "无 Critical/High")) return { ok: false, at: "代码评审" };

phase("集成测试");
const testReport = await agent(
  `${ROLE.qa}\n\n在 staging 环境执行功能/集成/UI 测试。评审与改动：${review}\n\n完成后返回测试报告结论。`
);
log(`测试结论：${testReport?.slice(0, 200) || "（无输出）"}`);
if (!gatePass("集成测试", "用例 100% 通过")) return { ok: false, at: "集成测试" };

phase("安全测试");
const securityReport = await agent(
  `${ROLE.security}\n\n对 staging 环境黑盒扫描。完成后返回安全报告结论。`
);
log(`安全结论：${securityReport?.slice(0, 200) || "（无输出）"}`);
if (!gatePass("安全测试", "无 Critical/High 漏洞")) return { ok: false, at: "安全测试" };

phase("部署");
const deploy = await agent(
  `${ROLE.devops}\n\n部署已验证产物到 staging，健康检查，产出 runbook。完成后返回部署状态与 runbook 摘要。`
);
log(`部署：${deploy?.slice(0, 200) || "（无输出）"}`);
if (!gatePass("部署", "健康检查通过")) return { ok: false, at: "部署" };

phase("交付");
const delivery = await agent(
  `你是编排器。汇总以下全部产出，生成交付报告：Release 说明 + CHANGELOG + 文档清单 + 待人类验收清单。\n\n需求：${requirements}\n架构：${architecture}\n评审：${review}\n测试：${testReport}\n安全：${securityReport}\n部署：${deploy}`
);

// 最终返回：交付报告 + 请求人类审批
return {
  ok: true,
  pipeline: "完整闭环已跑通",
  delivery: delivery,
  nextAction: "请人类在关键门禁（生产发布/最终验收）审批",
  artifacts: [
    "docs/requirements.md",
    "docs/architecture.md",
    "docs/api-spec.yaml",
    "docs/review/",
    "docs/test/",
    "docs/runbook.md",
    "CHANGELOG.md",
  ],
};
