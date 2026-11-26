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
//   3. args 传入：
//        { requirement: "你的需求",
//          projectRoot: "D:/path/to/project",
//          team: "quickfix" | "feature" | "full",   // 可选，默认 feature
//          scope: "frontend" | "backend" | "both"   // 可选，仅 quickfix 生效，默认 both }
//
// 团队预设（docs/03 §1.4 裁剪规则的工程落地——不每次全量上智能体）：
//   路由规则（选档参考）：
//     触碰鉴权/密码/支付/数据存储、对外接口、发版前 → full
//     涉及 docs/api-spec.yaml 的常规功能           → feature（默认）
//     纯 bug 修复/文案/无契约变更的小改动          → quickfix
//
// 三条铁律不因降档而裁剪：
//   1. 门禁必须真实退出码——所有档位都真实执行 scripts/*.sh；
//   2. 写代码的智能体不得验收自己的代码——quickfix 也保留轻量独立评审；
//   3. 失败退回重试——gate() 的重试循环所有档位一致。
//
// 与旧版的关键区别：
//   - 旧版 gatePass() 恒返回 true —— 门禁形同虚设。
//   - 新版 gate() 真实执行 <projectRoot>/scripts/*.sh，
//     由【真实退出码】推出 passed，编排器无法绕过。
//   - 补上 e2e 门禁（旧版漏了，验收门禁形同不存在）。
//   - 补上真实的"失败退回重试"循环（旧版只 return false，没有重试）。
//   - 新增团队预设：quickfix 档跳过 PM/架构/QA/安全/部署，省 ~70% token。
//   详见 docs/04-门禁与命令契约.md
// ============================================================

// ---------- 可调参数 ----------
const MAX_RETRY = 3;                 // 每道门禁最多重试次数（docs/04 §3）
const ROOT = (args && args.projectRoot) || ".";

// ---------- 团队预设 ----------
// 裁剪依据 = docs/03 §1.4 切角色的三个必要条件：
//   权限边界不同 / 产物形态不同 / 需要并行——三条都不满足就合并或省略。
// 永不裁剪：真实门禁、独立验收方（评审）、失败退回。
const TEAMS = {
  quickfix: {
    desc: "小修复档：单开发智能体 + 轻量评审；跳过 PM/架构/拆解/QA/安全/部署",
    pm: false,
    architect: false,
    tasks: false,
    coding: "single",      // single：一个开发智能体（scope 由 args.scope 限定）
    review: "light",       // light：只读本次改动摘要，聚焦正确性+安全两维
    qa: false,             // 集成测试智能体（e2e 门禁仍真实执行）
    security: false,
    deploy: false,         // 部署智能体与 health 门禁一并跳过
  },
  feature: {
    desc: "常规功能档：PM+架构+并行编码+评审+QA+部署；跳过安全红队",
    pm: true,
    architect: true,
    tasks: true,
    coding: "parallel",    // parallel：前端+后端两个智能体并行
    review: "full",        // full：六维评审
    qa: true,
    security: false,
    deploy: true,
  },
  full: {
    desc: "全量档：全部角色 + 安全红队；鉴权/支付/数据模型变更、发版前必用",
    pm: true,
    architect: true,
    tasks: true,
    coding: "parallel",
    review: "full",
    qa: true,
    security: true,
    deploy: true,
  },
};

const teamKey = (args && args.team) || "feature";
const TEAM = TEAMS[teamKey];
if (!TEAM) {
  return {
    ok: false,
    at: "启动",
    reason: `未知团队预设: ${teamKey}（可选 quickfix / feature / full，缺省 feature）`,
  };
}
log(`[团队] ${teamKey} — ${TEAM.desc}`);
const skipped = [];

// ---------- 角色提示词（精简内联版；生产建议改为读取 prompts/ 原文）----------
const ROLE = {
  pm: `你是产品经理智能体。阅读原始需求，产出含"可测验收标准"的需求文档，写入 docs/requirements.md。只产出文档，不写代码。`,
  architect: `你是架构师智能体。基于 docs/requirements.md 完成技术选型、系统架构图(Mermaid)、接口契约(OpenAPI)，写入 docs/architecture.md 和 docs/api-spec.yaml。只产出设计，不写实现代码。`,
  frontend: `你是前端开发智能体。严格遵循 docs/api-spec.yaml，只修改 frontend/ 目录，编写代码与单元测试，跑通 scripts/lint.sh、scripts/build.sh、scripts/test.sh 后提交。不碰后端与测试用例。`,
  backend: `你是后端开发智能体。严格遵循 docs/api-spec.yaml，只修改 backend/ 目录，编写代码与单元测试，跑通 scripts/lint.sh、scripts/build.sh、scripts/test.sh 后提交。不碰前端与测试用例。`,
  reviewer: `你是独立代码评审智能体。只读代码，按正确性/契约/安全/质量/测试/性能六维审查，分级 Critical/High/Medium/Low，产出评审报告。Critical/High 必须驳回。`,
  reviewerLight: `你是独立代码评审智能体（轻量档）。只读本次改动相关代码，聚焦【正确性】与【安全】两维（边界条件、注入/泄漏/越权），分级 Critical/High/Medium/Low，产出简短评审报告。Critical/High 必须驳回。`,
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

// ---------- 阶段 0：需求澄清 ----------
phase("需求澄清");
let requirements = "";
if (TEAM.pm) {
  requirements = await agent(
    `${ROLE.pm}\n\n原始需求：${args.requirement}\n\n完成后返回需求文档摘要（含验收标准清单）。`
  );
  log(`需求文档产出：${requirements?.slice(0, 200) || "（无输出，需检查）"}`);
  if (!requirements) return { ok: false, at: "需求澄清", reason: "PM 未产出需求文档" };
} else {
  // quickfix：人类已直接给出明确需求，PM 不参与（省一次智能体调用）
  requirements = String(args.requirement || "");
  skipped.push("需求澄清(PM)");
  log(`[quickfix] 跳过 PM：需求直接取自 args.requirement`);
}

// ---------- 阶段 1：架构设计 ----------
let architecture = "";
if (TEAM.architect) {
  phase("架构设计");
  architecture = await agent(
    `${ROLE.architect}\n\n需求文档：${requirements}\n\n完成后返回架构设计与接口契约摘要。`
  );
  log(`架构产出：${architecture?.slice(0, 200) || "（无输出）"}`);
  if (!architecture) return { ok: false, at: "架构设计", reason: "架构师未产出设计" };
} else {
  // quickfix：前提是本次改动不涉及 docs/api-spec.yaml（路由规则），故无架构师
  architecture = "（quickfix 档：无契约变更，跳过架构设计；改动不得触碰 docs/api-spec.yaml）";
  skipped.push("架构设计");
  log("[quickfix] 跳过架构设计");
}

// ---------- 阶段 2：任务拆解 ----------
let tasks = "";
if (TEAM.tasks) {
  phase("任务拆解");
  tasks = await agent(
    `你是编排器。基于以下架构与需求，拆解成可独立验收的任务 Issue 列表（含验收标准、依赖关系）。\n\n需求：${requirements}\n架构：${architecture}`
  );
  log(`任务拆解：${tasks?.slice(0, 200) || "（无输出）"}`);
} else {
  tasks = "（quickfix 档：单任务，无需拆解）";
  skipped.push("任务拆解");
  log("[quickfix] 跳过任务拆解");
}

// ---------- 阶段 3：并行编码 ----------
phase("并行编码");
let frontendResult = null;
let backendResult = null;
if (TEAM.coding === "parallel") {
  [frontendResult, backendResult] = await parallel([
    () => agent(`${ROLE.frontend}\n\n接口契约与架构：${architecture}\n\n任务：${tasks}\n\n完成后返回改动摘要与自测结果。`, { label: "前端开发", phase: "并行编码" }),
    () => agent(`${ROLE.backend}\n\n接口契约与架构：${architecture}\n\n任务：${tasks}\n\n完成后返回改动摘要与自测结果。`, { label: "后端开发", phase: "并行编码" }),
  ]);
  log(`前端：${frontendResult?.slice(0, 150) || "（无输出）"}`);
  log(`后端：${backendResult?.slice(0, 150) || "（无输出）"}`);
} else {
  // quickfix：单开发智能体，scope 限定可触碰的目录（最小权限）
  const scope = (args && args.scope) || "both";
  const scopeRule =
    scope === "frontend" ? "只允许修改 frontend/ 目录" :
    scope === "backend" ? "只允许修改 backend/ 目录" :
    "允许修改 frontend/ 与 backend/ 目录";
  frontendResult = await agent(
    `你是开发智能体（quickfix 档）。${scopeRule}，不碰 tests/ 与 scripts/ 与 docs/。
需求/缺陷描述：${requirements}

完成后：跑通 bash scripts/lint.sh && bash scripts/build.sh && bash scripts/test.sh（全 exit 0），返回改动摘要与自测结果。`,
    { label: "开发(quickfix)", phase: "并行编码" }
  );
  backendResult = frontendResult; // 门禁退回提示共用同一改动摘要
  log(`开发：${frontendResult?.slice(0, 150) || "（无输出）"}`);
}

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

// ---------- 阶段 4：代码评审（所有档位保留独立验收方——铁律 2）----------
phase("代码评审");
let review = null;
if (TEAM.review === "full") {
  review = await agent(
    `${ROLE.reviewer}\n\n前端改动：${frontendResult}\n后端改动：${backendResult}\n\n完成后返回评审结论（通过/驳回）与问题清单。`,
    { label: "代码评审", phase: "代码评审" }
  );
} else if (TEAM.review === "light") {
  review = await agent(
    `${ROLE.reviewerLight}\n\n本次改动摘要：${frontendResult}\n\n完成后返回评审结论（通过/驳回）与问题清单。`,
    { label: "轻量评审", phase: "代码评审" }
  );
} else {
  skipped.push("代码评审");
  log("[配置] 跳过代码评审（不建议：写代码方不得自我验收）");
}
log(`评审结论：${review?.slice(0, 200) || "（无输出）"}`);
// 评审驳回 = 评审门禁不通过（docs/01 §4：高危问题必须打回，不可带病合入）
if (review && /驳回/.test(review)) {
  return {
    ok: false,
    at: "代码评审",
    reason: `评审驳回：${String(review).slice(0, 300)}`,
    failures: [String(review).slice(0, 500)],
    nextAction: "携带评审问题清单退回开发智能体修复后重跑",
  };
}

// ---------- 阶段 5：集成测试 ----------
let testReport = "";
if (TEAM.qa) {
  phase("集成测试");
  testReport = await agent(
    `${ROLE.qa}\n\n在隔离 staging 环境执行功能/集成/UI 测试。评审与改动：${review}\n\n完成后返回测试报告结论。`,
    { label: "集成测试", phase: "集成测试" }
  );
  log(`测试结论：${testReport?.slice(0, 200) || "（无输出）"}`);
} else {
  testReport = "（quickfix 档：跳过独立集成测试智能体）";
  skipped.push("集成测试(QA)");
  log("[quickfix] 跳过集成测试智能体（e2e 门禁仍真实执行）");
}

// —— 验收门禁：e2e 必须真实执行（旧版漏了这道，验收形同不存在）——
// 所有档位都跑：脚本在无用例时明确跳过（exit 0 但注明"跳过≠通过"），成本极低。
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

// ---------- 阶段 6：安全测试（仅 full 档）----------
let securityReport = "";
if (TEAM.security) {
  phase("安全测试");
  securityReport = await agent(
    `${ROLE.security}\n\n对 staging 环境黑盒扫描（你拿不到源码）。完成后返回安全报告结论。`,
    { label: "安全测试", phase: "安全测试" }
  );
  log(`安全结论：${securityReport?.slice(0, 200) || "（无输出）"}`);
} else {
  securityReport = "（本次未执行安全红队扫描）";
  skipped.push("安全测试");
  log(`[${teamKey}] 跳过安全红队——若本次触碰鉴权/密码/支付/数据存储，请改用 full 档重跑`);
}

// ---------- 阶段 8：部署 + 部署门禁 ----------
let deploy = "";
let gHealth = null;
if (TEAM.deploy) {
  phase("部署");
  deploy = await agent(
    `${ROLE.devops}\n\n部署已验证产物到 staging，健康检查，产出 runbook。完成后返回部署状态与 runbook 摘要。`,
    { label: "部署 staging", phase: "部署" }
  );
  log(`部署：${deploy?.slice(0, 200) || "（无输出）"}`);

  // —— 部署门禁：真实健康检查 ——
  phase("部署门禁");
  gHealth = await gate("scripts/health.sh", "部署-健康检查",
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
} else {
  deploy = "（quickfix 档：跳过 staging 部署）";
  skipped.push("部署+health门禁");
  log("[quickfix] 跳过部署与健康检查门禁");
}

// ---------- 阶段 10：交付 ----------
phase("交付");
let delivery = "";
if (TEAM.deploy) {
  delivery = await agent(
    `你是编排器。汇总以下全部产出，生成交付报告：Release 说明 + CHANGELOG + 文档清单 + 待人类验收清单。\n\n需求：${requirements}\n架构：${architecture}\n评审：${review}\n测试：${testReport}\n安全：${securityReport}\n部署：${deploy}`,
    { phase: "交付" }
  );
} else {
  // quickfix：编排器直接汇总，不再花一次智能体调用
  delivery = `quickfix 交付摘要——改动：${frontendResult}；评审：${review}；门禁：lint/build/test/e2e 全 exit 0。未执行：${skipped.join("、") || "无"}。`;
  log(`交付：${delivery.slice(0, 200)}`);
}

return {
  ok: true,
  team: teamKey,
  pipeline: "闭环已跑通（按团队预设裁剪）",
  gates: {
    lint: gLint.passed,
    build: gBuild.passed,
    test: gTest.passed,
    e2e: gE2E.passed,
    ...(gHealth ? { health: gHealth.passed } : {}),
  },
  skippedPhases: skipped,
  delivery: delivery,
  nextAction:
    teamKey === "quickfix"
      ? "quickfix 交付：未执行 PM/架构/QA/安全/部署。若本次改动影响面超出预期（触碰契约/鉴权/存储），请用 feature 或 full 档重跑完整验证"
      : "请人类在关键门禁（生产发布/最终验收）审批",
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
