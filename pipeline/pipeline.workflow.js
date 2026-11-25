// ============================================================
// AI 多智能体协同开发 —— 最小闭环编排脚本（DSH Workflow）
//
// 用途：串起「需求→架构→编码→评审→测试→安全→部署→交付」。
//
// 如何使用：
//   1. 在 DSH 中新建 workflow，把【本文件全部内容】粘进 script。
//   2. meta 不要写在脚本里（本文件已按 DSH 要求去掉 export），
//      而是在工具的 meta 参数中提供：
//        { name: "ai-dev-pipeline",
//          description: "AI 多智能体协同开发最小闭环",
//          phases: [{title:"需求澄清"}, ...] }
//   3. args 传入：{ requirement: "你的需求", projectRoot: "D:/path/to/project" }
//
// 与旧版的关键区别：
//   - 旧版 gatePass() 恒返回 true —— 门禁形同虚设。
//   - 新版 gate() 真实执行 <projectRoot>/scripts/*.sh，
//     由【真实退出码】推出 passed，编排器无法绕过。
//   - 补上 e2e 门禁（旧版漏了，验收门禁形同不存在）。
//   - 补上真实的"失败退回重试"循环（旧版只 return false，没有重试）。
//   详见 docs/04-门禁与命令契约.md
// ============================================================

// ---------- 可调参数 ----------
const MAX_RETRY = 3;                 // 每道门禁最多重试次数（docs/04 §3）
const ROOT = (args && args.projectRoot) || ".";

// ---------- 角色提示词（精简内联版；生产建议改为读取 prompts/ 原文）----------
const ROLE = {
  pm: `你是产品经理智能体。阅读原始需求，产出含"可测验收标准"的需求文档，写入 docs/requirements.md。只产出文档，不写代码。`,
  architect: `你是架构师智能体。基于 docs/requirements.md 完成技术选型、系统架构图(Mermaid)、接口契约(OpenAPI)，写入 docs/architecture.md 和 docs/api-spec.yaml。只产出设计，不写实现代码。`,
  frontend: `你是前端开发智能体。严格遵循 docs/api-spec.yaml，只修改 frontend/ 目录，编写代码与单元测试，跑通 scripts/lint.sh、scripts/build.sh、scripts/test.sh 后提交。不碰后端与测试用例。`,
  backend: `你是后端开发智能体。严格遵循 docs/api-spec.yaml，只修改 backend/ 目录，编写代码与单元测试，跑通 scripts/lint.sh、scripts/build.sh、scripts/test.sh 后提交。不碰前端与测试用例。`,
  reviewer: `你是独立代码评审智能体。只读代码，按正确性/契约/安全/质量/测试/性能六维审查，分级 Critical/High/Medium/Low，产出评审报告。Critical/High 必须驳回。`,
  qa: `你是独立测试智能体。只读代码+可执行测试，在隔离 staging 环境做功能/集成/UI/性能测试，产出报告。绝不修改业务代码，绝不让用例"变绿"。`,
  security: `你是安全红队智能体。以黑盒方式对 staging 做 OWASP Top 10 扫描、依赖审计、渗透，产出安全报告。你拿不到源码，只能从外部探测。绝不接触生产。`,
  devops: `你是运维智能体。用声明式方式把已验证产物部署到 staging，做健康检查，产出可复用 runbook。不修改业务逻辑，生产需人类审批。`,
};

// ---------- 门禁结果的结构化 schema ----------
const GATE_SCHEMA = {
  type: "object",
  properties: {
    passed: { type: "boolean" },
    exitCode: { type: "number" },
    summary: { type: "string" },
    failures: { type: "array", items: { type: "string" } },
  },
  required: ["passed", "exitCode", "summary", "failures"],
  additionalProperties: false,
};

// ---------- 真实门禁执行器 ----------
// 关键：workflow 脚本本身无进程权限，所以让一个子智能体去跑，并强制返回结构化结果。
// passed 由真实 exitCode 推出，不由智能体"觉得"。
async function runScript(script, label) {
  const r = await agent(
    `你是一个门禁执行器，只做一件事：在目录 ${ROOT} 下执行下面的命令，并如实回报结果。

命令：bash ${script}

严格要求：
1. 必须真实执行，绝不臆测结果、绝不跳过、绝不用 "看起来应该通过" 代替执行。
2. passed 必须等于 (exitCode === 0)，不得为了"让流程继续"而修改。
3. summary 写一句话结论；若失败，failures 里逐条列出失败的检查项或关键报错行。
4. 如果命令不存在或脚本缺失，exitCode 记为 127 或 1，passed 为 false，并在 failures 说明。`,
    { label: `门禁:${script}`, schema: GATE_SCHEMA, phase: label }
  );
  return r || { passed: false, exitCode: -1, summary: "门禁执行器无输出", failures: ["agent 未返回结构化结果"] };
}

// 单次门禁（不重试）
async function gateOnce(script, stageLabel) {
  const r = await runScript(script, stageLabel);
  const ok = r.passed === true && r.exitCode === 0;
  log(`[门禁] ${stageLabel} ← ${script} : ${ok ? "通过" : "失败"} (exit=${r.exitCode}) ${r.summary}`);
  return { ok, script, stageLabel, ...r };
}

// 门禁 + 真实重试（docs/04 §3：最多重试 N 次，失败携带报告退回上一环节）
// repairPrompt 存在时，重试前会先让开发智能体按失败清单修一次。
async function gate(script, stageLabel, repairPrompt) {
  let last = null;
  for (let attempt = 1; attempt <= MAX_RETRY; attempt++) {
    if (attempt > 1) log(`[门禁] ${stageLabel} 第 ${attempt}/${MAX_RETRY} 次尝试`);
    last = await gateOnce(script, stageLabel);
    if (last.ok) return last;

    if (attempt < MAX_RETRY && repairPrompt) {
      log(`[退回] ${stageLabel} 失败，携失败清单退回修复：${last.failures.join("；").slice(0, 300)}`);
      await agent(
        `${repairPrompt}

上一轮门禁失败，必须修复根因，不得绕过门禁、不得放宽阈值、不得删除测试用例。

失败清单：
${last.failures.map((f) => `- ${f}`).join("\n")}

失败摘要：${last.summary}（exit=${last.exitCode}）

修复后用 bash ${script} 自测通过，再返回改动摘要。`,
        { label: `退回修复:${stageLabel}` }
      );
    }
  }
  return last;
}

// 任一失败即中断整条流水线（携带可归因的失败清单）
function abortOn(at, gates) {
  const bad = gates.filter((g) => !g.ok);
  if (bad.length === 0) return null;
  return {
    ok: false,
    at,
    reason: bad.map((g) => `${g.stageLabel}：${g.summary}（exit=${g.exitCode}）`).join("；"),
    failures: bad.flatMap((g) => g.failures),
    nextAction: "携带上述 failures 退回对应开发智能体修复后重跑",
  };
}

// ---------- 主流程 ----------
phase("需求澄清");
const requirements = await agent(
  `${ROLE.pm}\n\n原始需求：${args.requirement}\n\n完成后返回需求文档摘要（含验收标准清单）。`
);
log(`需求文档产出：${requirements?.slice(0, 200) || "（无输出，需检查）"}`);
if (!requirements) return { ok: false, at: "需求澄清", reason: "PM 未产出需求文档" };

phase("架构设计");
const architecture = await agent(
  `${ROLE.architect}\n\n需求文档：${requirements}\n\n完成后返回架构设计与接口契约摘要。`
);
log(`架构产出：${architecture?.slice(0, 200) || "（无输出）"}`);
if (!architecture) return { ok: false, at: "架构设计", reason: "架构师未产出设计" };

phase("任务拆解");
const tasks = await agent(
  `你是编排器。基于以下架构与需求，拆解成可独立验收的任务 Issue 列表（含验收标准、依赖关系）。\n\n需求：${requirements}\n架构：${architecture}`
);
log(`任务拆解：${tasks?.slice(0, 200) || "（无输出）"}`);

phase("并行编码");
const [frontendResult, backendResult] = await parallel([
  () => agent(`${ROLE.frontend}\n\n接口契约与架构：${architecture}\n\n任务：${tasks}\n\n完成后返回改动摘要与自测结果。`, { label: "前端开发", phase: "并行编码" }),
  () => agent(`${ROLE.backend}\n\n接口契约与架构：${architecture}\n\n任务：${tasks}\n\n完成后返回改动摘要与自测结果。`, { label: "后端开发", phase: "并行编码" }),
]);
log(`前端：${frontendResult?.slice(0, 150) || "（无输出）"}`);
log(`后端：${backendResult?.slice(0, 150) || "（无输出）"}`);

// —— 编码门禁：三道真实脚本，带重试，任一失败即退回 ——
phase("编码门禁");
const gLint = await gate("scripts/lint.sh", "编码-静态检查",
  `你是开发智能体。前端改动：${frontendResult}\n后端改动：${backendResult}`);
const gBuild = await gate("scripts/build.sh", "编码-构建",
  `你是开发智能体。前端改动：${frontendResult}\n后端改动：${backendResult}`);
const gTest = await gate("scripts/test.sh", "编码-单元测试",
  `你是开发智能体。前端改动：${frontendResult}\n后端改动：${backendResult}`);

const codingAbort = abortOn("编码门禁", [gLint, gBuild, gTest]);
if (codingAbort) return codingAbort;

phase("代码评审");
const review = await agent(
  `${ROLE.reviewer}\n\n前端改动：${frontendResult}\n后端改动：${backendResult}\n\n完成后返回评审结论（通过/驳回）与问题清单。`,
  { label: "代码评审", phase: "代码评审" }
);
log(`评审结论：${review?.slice(0, 200) || "（无输出）"}`);

phase("集成测试");
const testReport = await agent(
  `${ROLE.qa}\n\n在隔离 staging 环境执行功能/集成/UI 测试。评审与改动：${review}\n\n完成后返回测试报告结论。`,
  { label: "集成测试", phase: "集成测试" }
);
log(`测试结论：${testReport?.slice(0, 200) || "（无输出）"}`);

// —— 验收门禁：e2e 必须真实执行（旧版漏了这道，验收形同不存在）——
phase("验收门禁");
const gE2E = await gate("scripts/e2e.sh", "验收-e2e",
  `你是测试智能体。测试结论：${testReport}\n\n修复 e2e 失败用例或让其明确暴露真实缺陷（绝不修改断言让其变绿）。`);
if (!gE2E.ok) {
  return {
    ok: false,
    at: "验收门禁",
    reason: `${gE2E.summary}（exit=${gE2E.exitCode}）`,
    failures: gE2E.failures,
    nextAction: "退回开发/测试修复；交付前 e2e 必须真实通过，不能是『未配置即跳过』",
  };
}

phase("安全测试");
const securityReport = await agent(
  `${ROLE.security}\n\n对 staging 环境黑盒扫描（你拿不到源码）。完成后返回安全报告结论。`,
  { label: "安全测试", phase: "安全测试" }
);
log(`安全结论：${securityReport?.slice(0, 200) || "（无输出）"}`);

phase("部署");
const deploy = await agent(
  `${ROLE.devops}\n\n部署已验证产物到 staging，健康检查，产出 runbook。完成后返回部署状态与 runbook 摘要。`,
  { label: "部署 staging", phase: "部署" }
);
log(`部署：${deploy?.slice(0, 200) || "（无输出）"}`);

// —— 部署门禁：真实健康检查 ——
phase("部署门禁");
const gHealth = await gate("scripts/health.sh", "部署-健康检查",
  `你是运维智能体。部署状态：${deploy}\n\n修复启动/健康检查问题，不得放宽探针、不得跳过迁移校验。`);
if (!gHealth.ok) {
  return {
    ok: false,
    at: "部署门禁",
    reason: gHealth.summary,
    failures: gHealth.failures,
    nextAction: "自动回滚上一稳定版本，保留现场日志，并通知人类",
  };
}

phase("交付");
const delivery = await agent(
  `你是编排器。汇总以下全部产出，生成交付报告：Release 说明 + CHANGELOG + 文档清单 + 待人类验收清单。\n\n需求：${requirements}\n架构：${architecture}\n评审：${review}\n测试：${testReport}\n安全：${securityReport}\n部署：${deploy}`,
  { phase: "交付" }
);

return {
  ok: true,
  pipeline: "完整闭环已跑通",
  gates: {
    lint: gLint.passed,
    build: gBuild.passed,
    test: gTest.passed,
    e2e: gE2E.passed,
    health: gHealth.passed,
  },
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
