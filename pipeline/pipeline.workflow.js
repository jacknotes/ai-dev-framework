// ============================================================
// AI 多智能体协同开发 —— 最小闭环编排脚本（DSH Workflow）v2
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
//          scope: "frontend" | "backend" | "both",  // 可选，仅 quickfix 生效
//          tasks: [ { id: "T1", title: "...", acceptance: "...", paths: ["backend/"] } ]
//                                                 // 可选：预拆任务（feature/full 档跳过架构师拆解）
//          lightModel:  { provider: "...", model: "..." }, // 可选：执行器/汇总类低档模型
//          strongModel: { provider: "...", model: "..." }  // 可选：编码/评审类强档模型
//
// 【重要】必须在【新项目目录】打开的 agent 会话中运行本 workflow（projectRoot="."）。
//   原因：DSH 会给每个子智能体注入"会话所在目录"的 AGENTS.md 指令链。
//   在框架仓库里运行 → 所有子智能体背框架级指令，既贵又与项目无关。
//
// 团队预设（docs/03 §1.4 裁剪规则的工程落地——不每次全量上智能体）：
//   路由规则（选档参考）：
//     触碰鉴权/密码/支付/数据存储、对外接口、发版前 → full
//     涉及 docs/api-spec.yaml 的常规功能           → feature（默认）
//     纯 bug 修复/文案/无契约变更的小改动          → quickfix
//
// 三条铁律不因降档而裁剪（v2 同样不裁剪）：
//   1. 门禁必须真实退出码——聚合执行器只是把 5 次调用收成 1 次，退出码判定一个不少；
//   2. 写代码的智能体不得验收自己的代码——quickfix 也保留轻量独立评审；
//   3. 失败退回重试——改的是"退回粒度"（整条→局部），不是取消退回。
//
// v2 相对 v1 的成本优化（详见 docs/04 §4 与 docs/03 §8 度量）：
//   - 聚合门禁执行器：5 道门禁 1 个智能体会话跑完（v1 是 5 个会话）；
//   - 编码门禁一轮收集全部失败（v1 逐道重试，修 lint 可能 build 还红着）；
//   - 评审驳回走局部修复循环（v1 直接 return，用户只能整条重跑）；
//   - 删除"任务拆解""交付汇总"两个纯文档会话（docs/03 §1.4 本来就说不必单开）；
//   - 模型分档：执行器/汇总类用低档模型，编码/评审用强档（opts.model 覆盖）；
//   - feature/full 档按任务迭代执行：单会话上下文有界，复杂功能不再"越写越糊"；
//   - 关键产出 schema 化：评审结论不再靠 /驳回/ 正则猜；
//   - 注入瘦身：开发智能体只拿契约+任务，不拿全文需求/架构/改动摘要串珠。
// ============================================================

// ---------- 可调参数 ----------
const MAX_RETRY = 2;                 // 每轮门禁最多重试次数（docs/04 §3；v2 从 3 降到 2，
                                     // 因为聚合失败清单让每轮修复信息更全，轮次本身可以少）
const MAX_REVIEW_LOOP = 2;           // 评审驳回的局部修复循环上限
const ROOT = (args && args.projectRoot) || ".";

// ---------- 模型分档 ----------
// DSH workflow 的 agent(prompt, opts) 原生支持 provider/model 覆盖。
// 原则：只执行命令、搬运文本的会话用低档；写代码、评审、定契约的会话用强档。
// MODEL.light 不设置时 = 不传 model，跟随父会话默认（部署没有低档模型时自然退化）。
const MODEL = {
  light: (args && args.lightModel) || null,   // 例：{ provider: "xxx", model: "xxx-lite" }
  strong: (args && args.strongModel) || null, // 例：{ provider: "xxx", model: "xxx-strong" }
};
// 把分档并入 agent 的 opts；null 时不覆盖，保持向后兼容。
function optsFor(extra) {
  const o = Object.assign({}, extra || {});
  if (MODEL.light) Object.assign(o, MODEL.light);
  return o;
}
function optsForStrong(extra) {
  const o = Object.assign({}, extra || {});
  if (MODEL.strong) Object.assign(o, MODEL.strong);
  return o;
}

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
    desc: "常规功能档：PM+架构+按任务编码+评审+QA+部署；跳过安全红队",
    pm: true,
    architect: true,
    tasks: true,           // v2：拆解并入架构师产出，不再单开会话
    coding: "taskwise",    // taskwise：每个任务一个独立开发会话（上下文有界）
    review: "full",        // full：六维评审（按任务分批评审）
    qa: true,
    security: false,
    deploy: true,
  },
  full: {
    desc: "全量档：全部角色 + 安全红队；鉴权/支付/数据模型变更、发版前必用",
    pm: true,
    architect: true,
    tasks: true,
    coding: "taskwise",
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

// ---------- 预拆任务（可选）----------
// args.tasks 提供时，feature/full 档跳过架构师兼拆解，任务清单直接从这里来。
// 用于"需求已拆好"的场景（人工拆解或上游系统拆解），再省一次拆解开销。
let preTasks = null;
if (args && Array.isArray(args.tasks) && args.tasks.length > 0) {
  preTasks = args.tasks.filter((t) => t && t.id && t.title);
  if (preTasks.length > 0) {
    log(`[任务] 使用外部预拆任务清单：${preTasks.map((t) => t.id).join(", ")}`);
  }
}

// ---------- 角色提示词（精简内联版；prompts/ 原文用于人工会话，见 docs/04 §4）----------
// v2 瘦身：开发智能体的注入材料 = 契约/架构 + 本任务清单，不注入全文需求与架构长文。
const ROLE = {
  pm: `你是产品经理智能体。阅读原始需求，产出含"可测验收标准"的需求文档，写入 docs/requirements.md。只产出文档，不写代码。`,
  architect: `你是架构师智能体。基于 docs/requirements.md 完成技术选型、系统架构图(Mermaid)、接口契约(OpenAPI)，写入 docs/architecture.md 和 docs/api-spec.yaml。只产出设计，不写实现代码。`,
  frontend: `你是前端开发智能体。严格遵循 docs/api-spec.yaml，只修改 frontend/ 目录，编写代码与单元测试。不碰后端与测试用例。`,
  backend: `你是后端开发智能体。严格遵循 docs/api-spec.yaml，只修改 backend/ 目录，编写代码与单元测试。不碰前端与测试用例。`,
  developer: `你是开发智能体。严格遵循 docs/api-spec.yaml 的接口契约，编写代码与单元测试，不碰 tests/ 与 scripts/ 与 docs/。`,
  reviewer: `你是独立代码评审智能体。只读代码，按正确性/契约/安全/质量/测试/性能六维审查，产出评审结论与问题清单。verdict 为 reject 时必须列出问题。`,
  reviewerLight: `你是独立代码评审智能体（轻量档）。只读本次改动相关代码，聚焦【正确性】与【安全】两维（边界条件、注入/泄漏/越权），产出简短评审结论与问题清单。verdict 为 reject 时必须列出问题。`,
  qa: `你是独立测试智能体。只读代码+可执行测试，在隔离 staging 环境做功能/集成/UI/性能测试，产出报告。绝不修改业务代码，绝不让用例"变绿"。`,
  security: `你是安全红队智能体。以黑盒方式对 staging 做 OWASP Top 10 扫描、依赖审计、渗透，产出安全报告。你拿不到源码，只能从外部探测。绝不接触生产。`,
  devops: `你是运维智能体。用声明式方式把已验证产物部署到 staging，做健康检查，产出可复用 runbook。不修改业务逻辑，生产需人类审批。`,
  fixer: `你是开发修复智能体。只修复失败清单里列出的问题，不改无关代码，不绕过门禁、不放宽阈值、不删除测试用例。`,
};

// ---------- 结构化 schema ----------
// 门禁执行器：一次跑完多个脚本，逐个回报真实退出码（结构见 docs/04 §4）
const GATES_SCHEMA = {
  type: "object",
  properties: {
    ran: {
      type: "array",
      items: {
        type: "object",
        properties: {
          script: { type: "string" },
          exitCode: { type: "number" },
          summary: { type: "string" },
          failures: { type: "array", items: { type: "string" } },
        },
        required: ["script", "exitCode", "summary", "failures"],
        additionalProperties: false,
      },
    },
  },
  required: ["ran"],
  additionalProperties: false,
};

// 评审结论：verdict 字段取代 v1 的 /驳回/ 正则（v1 靠匹配中文自由文本，脆弱）
const REVIEW_SCHEMA = {
  type: "object",
  properties: {
    verdict: { type: "string", enum: ["approve", "reject"] },
    issues: {
      type: "array",
      items: {
        type: "object",
        properties: {
          severity: { type: "string", enum: ["Critical", "High", "Medium", "Low"] },
          file: { type: "string" },
          problem: { type: "string" },
          suggestion: { type: "string" },
        },
        required: ["severity", "problem"],
        additionalProperties: false,
      },
    },
    summary: { type: "string" },
  },
  required: ["verdict", "issues", "summary"],
  additionalProperties: false,
};

// ---------- 聚合门禁执行器 ----------
// 关键：workflow 脚本本身无进程权限，所以让一个子智能体去跑。
// v2：一次调用跑完全部脚本（不短路），passed 由每个脚本的真实 exitCode === 0 推出。
// 一个会话顶 v1 的五个，重试同理收敛；且修复方一轮拿到全部失败清单。
async function runGates(scripts, stageLabel) {
  const scriptList = scripts.map((s) => `bash ${s}`).join("\n");
  const r = await agent(
    `你是一个门禁执行器，只做一件事：在目录 ${ROOT} 下依次执行下面的命令，并如实回报每个命令的结果。

命令清单（按顺序执行；某条失败也继续执行后面的，不得短路）：
${scriptList}

严格要求：
1. 必须真实执行，绝不臆测结果、绝不跳过、绝不用 "看起来应该通过" 代替执行。
2. 每个命令的 exitCode 必须是该命令的真实退出码；passed 判定由编排器完成，你只如实回报。
3. 每个命令 summary 一句话结论；若失败，failures 里逐条列出失败的检查项或关键报错行（可先 tail 末 40 行再回报）。
4. 如果命令不存在或脚本缺失，exitCode 记为 127 或 1，并在 failures 说明。
5. ran 数组必须与命令清单一一对应，顺序一致。`,
    Object.assign({ label: `门禁聚合:${scripts.length}项`, schema: GATES_SCHEMA, phase: stageLabel }, optsFor())
  );
  const ran = (r && Array.isArray(r.ran)) ? r.ran : null;
  if (!ran) {
    // 执行器无输出/格式错 = 门禁未执行 = 失败（绝不静默放行）
    return scripts.map((s) => ({
      ok: false, script: s, stageLabel, passed: false, exitCode: -1,
      summary: "门禁执行器无结构化输出", failures: ["agent 未返回结构化结果"],
    }));
  }
  // 按清单顺序对齐；缺项 = 未执行 = 失败
  return scripts.map((s, i) => {
    const item = ran.find((x) => x.script === s) || ran[i];
    if (!item) {
      return { ok: false, script: s, stageLabel, passed: false, exitCode: -1,
        summary: "执行器未回报该命令", failures: [`缺少 ${s} 的执行结果`] };
    }
    const ok = item.exitCode === 0;
    return { ok, script: s, stageLabel, passed: ok, exitCode: item.exitCode,
      summary: item.summary || "", failures: Array.isArray(item.failures) ? item.failures : [] };
  });
}

// 编码门禁轮：执行 + 一次聚合修复。返回 { results, attempts }。
// v2 变化：一轮收集 lint/build/test 全部失败，一次修复会话拿到完整清单（v1 是逐道独立重试）。
async function codingGateRound(stageLabel, repairContext) {
  const scripts = ["scripts/lint.sh", "scripts/build.sh", "scripts/test.sh"];
  let results = await runGates(scripts, stageLabel);
  let attempts = 1;
  while (attempts < MAX_RETRY) {
    const bad = results.filter((g) => !g.ok);
    if (bad.length === 0) break;
    const failLines = bad.map((g) => `- [${g.script}] exit=${g.exitCode} ${g.summary}\n  ${g.failures.join("\n  ")}`).join("\n");
    log(`[门禁] ${stageLabel} 第 ${attempts} 轮失败 ${bad.length} 项，聚合修复后重跑`);
    await agent(
      `${repairContext}\n\n上一轮门禁失败，必须修复根因，不得绕过门禁、不得放宽阈值、不得删除测试用例。

失败清单（全部失败项，修完每一项）：
${failLines}

修复后返回改动摘要。`,
      Object.assign({ label: `聚合修复:${stageLabel}`, phase: stageLabel }, optsForStrong())
    );
    attempts++;
    results = await runGates(scripts, stageLabel);
  }
  return { results, attempts };
}

// 任一失败即中断整条流水线（携带可归因的失败清单）
function abortOn(at, gates) {
  const bad = gates.filter((g) => !g.ok);
  if (bad.length === 0) return null;
  return {
    ok: false,
    at,
    reason: bad.map((g) => `${g.script}：${g.summary}（exit=${g.exitCode}）`).join("；"),
    failures: bad.flatMap((g) => g.failures),
    nextAction: "携带上述 failures 退回开发修复后重跑；或人工查看 scripts 输出定位",
  };
}

// ---------- 评审 + 局部修复循环 ----------
// v2：驳回不再让整条流水线终止重跑，而是带问题清单调修复会话后重审，最多 MAX_REVIEW_LOOP 轮。
// 独立性不破坏：评审会话每次都是全新上下文，修复会话拿不到评审的推理过程。
async function reviewWithLoop(reviewPrompt, label, phaseName, repairContext) {
  for (let round = 1; round <= MAX_REVIEW_LOOP + 1; round++) {
    let r = await agent(reviewPrompt, Object.assign({ label, schema: REVIEW_SCHEMA, phase: phaseName }, optsForStrong()));
    if (!r) {
      // 评审器瞬时故障：先重试一次评审本身（不轮修复），仍无输出才判不通过
      log(`[评审] ${label} 无结构化输出，重试一次`);
      r = await agent(reviewPrompt, Object.assign({ label: `${label}:重试`, schema: REVIEW_SCHEMA, phase: phaseName }, optsForStrong()));
    }
    if (!r) {
      // 评审器无结构化输出：不可判定，视为不通过（不能静默放行）
      return { verdict: "reject", issues: [], summary: "评审智能体无结构化输出", rounds: round, review: null };
    }
    if (r.verdict === "approve") return { verdict: "approve", issues: r.issues || [], summary: r.summary || "", rounds: round, review: r };
    if (round > MAX_REVIEW_LOOP) {
      return { verdict: "reject", issues: r.issues || [], summary: r.summary || "", rounds: round, review: r };
    }
    const blocking = (r.issues || []).filter((i) => i.severity === "Critical" || i.severity === "High");
    if (blocking.length === 0) {
      // 无 Critical/High（docs/01 §4 放行标准）→ 视为通过，Medium/Low 记录在案
      return { verdict: "approve", issues: r.issues || [], summary: r.summary || "", rounds: round, review: r };
    }
    const issueLines = blocking.map((i) => `- [${i.severity}] ${i.file || ""} ${i.problem}（建议：${i.suggestion || "评审未给出"}）`).join("\n");
    log(`[评审] 第 ${round} 轮驳回 ${blocking.length} 个 Critical/High，局部修复后重审`);
    await agent(
      `${repairContext}\n\n独立评审驳回以下问题，必须修复根因：\n${issueLines}\n\n修复后返回改动摘要。`,
      Object.assign({ label: `评审修复:第${round}轮`, phase: phaseName }, optsForStrong())
    );
  }
  // 理论上不可达（循环内有 return），防御性返回
  return { verdict: "reject", issues: [], summary: "评审循环异常退出", rounds: MAX_REVIEW_LOOP + 1, review: null };
}

// ---------- 阶段 0：需求澄清 ----------
phase("需求澄清");
let requirements = "";
if (TEAM.pm) {
  requirements = await agent(
    `${ROLE.pm}\n\n原始需求：${args.requirement}\n\n完成后返回需求文档摘要（含验收标准清单）。`,
    Object.assign({ label: "需求澄清" }, optsForStrong())
  );
  log(`需求文档产出：${requirements?.slice(0, 200) || "（无输出，需检查）"}`);
  if (!requirements) return { ok: false, at: "需求澄清", reason: "PM 未产出需求文档" };
} else {
  // quickfix：人类已直接给出明确需求，PM 不参与（省一次智能体调用）
  requirements = String(args.requirement || "");
  skipped.push("需求澄清(PM)");
  log(`[quickfix] 跳过 PM：需求直接取自 args.requirement`);
}

// ---------- 阶段 1：架构设计 + 任务拆解（合并为一个会话）----------
let architecture = "";
let tasks = [];
if (preTasks) {
  // 外部预拆任务：架构师会话仍要跑（feature/full 档有契约产出），但不再要求它拆解
  if (TEAM.architect) {
    phase("架构设计");
    architecture = await agent(
      `${ROLE.architect}\n\n需求文档：${requirements}\n\n已有任务清单（写入 docs/pipeline-status.md，勿重新拆解）：${JSON.stringify(preTasks)}\n\n完成后返回架构设计与接口契约摘要。`,
      Object.assign({ label: "架构设计" }, optsForStrong())
    );
    log(`架构产出：${architecture?.slice(0, 200) || "（无输出）"}`);
    if (!architecture) return { ok: false, at: "架构设计", reason: "架构师未产出设计" };
  } else {
    architecture = "（无契约变更）";
  }
  tasks = preTasks;
} else if (TEAM.architect) {
  phase("架构设计");
  const taskwise = TEAM.coding === "taskwise";
  architecture = await agent(
    `${ROLE.architect}\n\n需求文档：${requirements}\n\n完成后返回架构设计与接口契约摘要。` +
    (taskwise
      ? `\n\n同时完成【任务拆解】（这是编排器职能，docs/03 §1.4 规定不必单开会话）：把需求拆成可独立验收的任务清单，JSON 数组返回，每项含 id（如 T1）、title、acceptance（可测验收标准）、paths（涉及目录，如 frontend/ 或 backend/）。任务数以需求规模为准，通常 2-6 个。任务清单请同时写入 docs/pipeline-status.md。`
      : ""),
    Object.assign({ label: "架构+拆解" }, optsForStrong())
  );
  log(`架构产出：${architecture?.slice(0, 200) || "（无输出）"}`);
  if (!architecture) return { ok: false, at: "架构设计", reason: "架构师未产出设计" };

  // 解析架构师返回的任务清单（容错：JSON 解析失败则退化为单任务，不中断流水线）
  if (taskwise) {
    const m = String(architecture).match(/\[\s*\{[\s\S]*\}\s*\]/);
    if (m) {
      try { tasks = JSON.parse(m[0]); } catch (e) { tasks = []; }
    }
    tasks = (Array.isArray(tasks) && tasks.length > 0)
      ? tasks
      : [{ id: "T1", title: "按需求完成实现", acceptance: String(args.requirement || ""), paths: ["frontend/", "backend/"] }];
    log(`任务拆解：${tasks.length} 个任务（${tasks.map((t) => t.id).join(", ")}）`);
  }
} else {
  // quickfix：前提是本次改动不涉及 docs/api-spec.yaml（路由规则），故无架构师
  architecture = "（quickfix 档：无契约变更，跳过架构设计；改动不得触碰 docs/api-spec.yaml）";
  skipped.push("架构设计");
  log("[quickfix] 跳过架构设计");
}

// ---------- 阶段 3：编码（v2 三种模式）----------
phase("编码");
const changes = [];   // 每个任务一段简短改动摘要（评审/门禁退回用，不注全文）
let frontendResult = null;
let backendResult = null;

if (TEAM.coding === "taskwise") {
  // ---- feature/full：按任务迭代执行，每个任务一个独立开发会话（上下文有界）----
  // 这是"功能复杂不爆上下文"的关键：v1 把全部任务塞进两个并行会话，功能越大单会话越长。
  for (const t of tasks) {
    const paths = Array.isArray(t.paths) && t.paths.length > 0 ? t.paths.join(" 与 ") : "涉及目录";
    const prompt = `${ROLE.developer}

任务 ${t.id}：${t.title}
只允许修改：${paths}
本任务验收标准：${t.acceptance}
接口契约与架构摘要（只与本任务相关的部分会由你自行 read，勿通读全文）：
${architecture}

完成后：跑 bash scripts/test.sh 自测通过，返回【不超过 150 字】的改动摘要（改了什么文件、实现了什么）。`;
    const r = await agent(prompt, Object.assign({ label: `开发:${t.id}`, phase: "编码" }, optsForStrong()));
    log(`${t.id}：${r?.slice(0, 150) || "（无输出）"}`);
    if (!r) {
      return { ok: false, at: "编码", reason: `任务 ${t.id} 开发智能体无输出`, failures: [`${t.id} 无改动摘要`],
        nextAction: "检查该任务的验收标准与目录范围是否可执行" };
    }
    changes.push(`[${t.id}] ${t.title}：${String(r).slice(0, 150)}`);
  }
  frontendResult = changes.join("\n");
  backendResult = frontendResult;
} else if (TEAM.coding === "parallel") {
  // ---- v1 兼容路径（当前 TEAMS 表已不使用，保留以备自定义预设）----
  [frontendResult, backendResult] = await parallel([
    () => agent(`${ROLE.frontend}\n\n接口契约与架构：${architecture}\n\n任务：${tasks}\n\n完成后返回改动摘要与自测结果。`, Object.assign({ label: "前端开发", phase: "编码" }, optsForStrong())),
    () => agent(`${ROLE.backend}\n\n接口契约与架构：${architecture}\n\n任务：${tasks}\n\n完成后返回改动摘要与自测结果。`, Object.assign({ label: "后端开发", phase: "编码" }, optsForStrong())),
  ]);
  log(`前端：${frontendResult?.slice(0, 150) || "（无输出）"}`);
  log(`后端：${backendResult?.slice(0, 150) || "（无输出）"}`);
} else {
  // ---- quickfix：单开发智能体，scope 限定可触碰的目录（最小权限）----
  const scope = (args && args.scope) || "both";
  const scopeRule =
    scope === "frontend" ? "只允许修改 frontend/ 目录" :
    scope === "backend" ? "只允许修改 backend/ 目录" :
    "允许修改 frontend/ 与 backend/ 目录";
  frontendResult = await agent(
    `你是开发智能体（quickfix 档）。${scopeRule}，不碰 tests/ 与 scripts/ 与 docs/。
需求/缺陷描述：${requirements}

完成后：跑通 bash scripts/test.sh 自测通过（lint/build 由门禁统一执行，不要重复跑），返回【不超过 150 字】的改动摘要。`,
    Object.assign({ label: "开发(quickfix)", phase: "编码" }, optsForStrong())
  );
  backendResult = frontendResult;
  log(`开发：${frontendResult?.slice(0, 150) || "（无输出）"}`);
}

// —— 编码门禁：三道真实脚本，聚合执行 + 聚合修复（一轮拿到全部失败清单）——
phase("编码门禁");
const coding = await codingGateRound("编码门禁", `${ROLE.fixer}\n\n本次改动摘要：\n${changes.join("\n") || String(frontendResult || "")}`);
const [gLint, gBuild, gTest] = coding.results;
const codingAbort = abortOn("编码门禁", coding.results);
if (codingAbort) return codingAbort;
log(`[门禁] 编码门禁 ${coding.attempts} 轮通过（lint=${gLint.exitCode} build=${gBuild.exitCode} test=${gTest.exitCode}）`);

// ---------- 阶段 4：代码评审（所有档位保留独立验收方——铁律 2）----------
phase("代码评审");
let reviewOutcome = null;
let review = "";
if (TEAM.review === "full") {
  // 按任务分批评审：每个评审会话只看一个任务的改动（上下文有界 + 可归因）
  if (TEAM.coding === "taskwise" && tasks.length > 1) {
    reviewOutcome = { verdict: "approve", issues: [], summary: "", rounds: 0, review: null };
    for (const t of tasks) {
      const per = await reviewWithLoop(
        `${ROLE.reviewer}

评审任务 ${t.id}（只评审该任务的改动，勿通读全仓库）：
- 任务标题：${t.title}
- 涉及目录：${Array.isArray(t.paths) ? t.paths.join(", ") : ""}
- 该任务验收标准：${t.acceptance}
- 改动摘要：${changes.find((c) => c.startsWith(`[${t.id}]`)) || "（见 git log 最新提交）"}

完成后按 schema 返回结论。`,
        `评审:${t.id}`, "代码评审",
        `${ROLE.fixer}\n\n正在修复任务 ${t.id}（${t.title}）的评审问题。`
      );
      // 合并结论：任一任务 reject 即整体 reject（保留最高轮次与问题清单）
      if (per.verdict === "reject") {
        reviewOutcome = {
          verdict: "reject",
          issues: reviewOutcome.issues.concat((per.issues || []).map((i) => Object.assign({ file: t.id }, i))),
          summary: (reviewOutcome.summary ? reviewOutcome.summary + "；" : "") + `${t.id}: ${per.summary}`,
          rounds: Math.max(reviewOutcome.rounds, per.rounds),
          review: per.review,
        };
        break; // 有 Critical/High 未清，后面任务等修复后重跑（局部循环已在任务内跑满）
      }
      reviewOutcome.issues = reviewOutcome.issues.concat(per.issues || []);
      reviewOutcome.summary += `${t.id}: ${per.summary}；`;
      reviewOutcome.rounds = Math.max(reviewOutcome.rounds, per.rounds);
    }
  } else {
    reviewOutcome = await reviewWithLoop(
      `${ROLE.reviewer}\n\n前端改动：${frontendResult}\n后端改动：${backendResult}\n\n完成后按 schema 返回结论。`,
      "代码评审", "代码评审", `${ROLE.fixer}\n\n本次改动摘要：\n` + String(frontendResult || "")
    );
  }
} else if (TEAM.review === "light") {
  reviewOutcome = await reviewWithLoop(
    `${ROLE.reviewerLight}\n\n本次改动摘要：${frontendResult}\n\n完成后按 schema 返回结论。`,
    "轻量评审", "代码评审", `${ROLE.fixer}\n\n本次改动摘要：\n` + String(frontendResult || "")
  );
} else {
  skipped.push("代码评审");
  log("[配置] 跳过代码评审（不建议：写代码方不得自我验收）");
}

if (reviewOutcome && reviewOutcome.verdict === "reject") {
  return {
    ok: false,
    at: "代码评审",
    reason: `评审驳回（${reviewOutcome.rounds} 轮局部修复后仍有 Critical/High）：${reviewOutcome.summary}`,
    failures: reviewOutcome.issues.map((i) => `[${i.severity}] ${i.file || ""} ${i.problem}`),
    nextAction: "按问题清单人工处理后重跑；或降档为 quickfix 先行热修",
  };
}
review = reviewOutcome ? `通过（${reviewOutcome.rounds} 轮）：${reviewOutcome.summary}` : "（已跳过）";
log(`评审结论：${review.slice(0, 200)}`);

// ---------- 阶段 5：集成测试 ----------
let testReport = "";
if (TEAM.qa) {
  phase("集成测试");
  testReport = await agent(
    `${ROLE.qa}\n\n在隔离 staging 环境执行功能/集成/UI 测试。评审摘要：${review}\n\n完成后返回测试报告结论。`,
    Object.assign({ label: "集成测试" }, optsFor())
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
const e2e = await runGates(["scripts/e2e.sh"], "验收门禁");
const gE2E = e2e[0];
if (!gE2E.ok) {
  // e2e 失败退回：先让测试智能体按失败清单修一轮（绝不改断言变绿），再执行一次
  const failLines = gE2E.failures.join("\n");
  await agent(
    `${ROLE.qa}\n\n上一轮 e2e 失败，必须修复根因：修复用例脚本的环境/选择器/等待问题，或让用例真实暴露缺陷（绝不修改断言让其变绿）。\n\n失败清单：\n${failLines}\n\n失败摘要：${gE2E.summary}（exit=${gE2E.exitCode}）`,
    Object.assign({ label: "e2e修复" }, optsFor())
  );
  const retry = await runGates(["scripts/e2e.sh"], "验收门禁重跑");
  if (!retry[0].ok) {
    return {
      ok: false,
      at: "验收门禁",
      reason: `${retry[0].summary}（exit=${retry[0].exitCode}）`,
      failures: retry[0].failures,
      nextAction: "退回开发/测试修复；交付前 e2e 必须真实通过，不能是『未配置即跳过』",
    };
  }
  log("[门禁] e2e 重跑通过");
}
const gE2EPassed = true;

// ---------- 阶段 6：安全测试（仅 full 档）----------
let securityReport = "";
if (TEAM.security) {
  phase("安全测试");
  securityReport = await agent(
    `${ROLE.security}\n\n对 staging 环境黑盒扫描（你拿不到源码）。完成后返回安全报告结论。`,
    Object.assign({ label: "安全测试" }, optsFor())
  );
  log(`安全结论：${securityReport?.slice(0, 200) || "（无输出）"}`);
} else {
  securityReport = "（本次未执行安全红队扫描）";
  skipped.push("安全测试");
  log(`[${teamKey}] 跳过安全红队——若本次触碰鉴权/密码/支付/数据存储，请改用 full 档重跑`);
}

// ---------- 阶段 8：部署 + 部署门禁 ----------
let deploy = "";
let healthPassed = null;
if (TEAM.deploy) {
  phase("部署");
  deploy = await agent(
    `${ROLE.devops}\n\n部署已验证产物到 staging，健康检查，产出 runbook。完成后返回部署状态与 runbook 摘要。`,
    Object.assign({ label: "部署 staging" }, optsFor())
  );
  log(`部署：${deploy?.slice(0, 200) || "（无输出）"}`);

  // —— 部署门禁：真实健康检查（聚合执行器跑单脚本；失败携清单退回运维修复一轮）——
  phase("部署门禁");
  let h = (await runGates(["scripts/health.sh"], "部署门禁"))[0];
  if (!h.ok) {
    await agent(
      `${ROLE.devops}\n\n上一轮健康检查失败。修复启动/健康检查问题，不得放宽探针、不得跳过迁移校验。\n\n失败清单：\n${h.failures.join("\n")}\n\n失败摘要：${h.summary}（exit=${h.exitCode}）\n\n修复后返回部署状态。`,
      Object.assign({ label: "部署修复" }, optsFor())
    );
    h = (await runGates(["scripts/health.sh"], "部署门禁重跑"))[0];
  }
  if (!h.ok) {
    return {
      ok: false,
      at: "部署门禁",
      reason: h.summary,
      failures: h.failures,
      nextAction: "自动回滚上一稳定版本，保留现场日志，并通知人类",
    };
  }
  healthPassed = true;
} else {
  deploy = "（quickfix 档：跳过 staging 部署）";
  skipped.push("部署+health门禁");
  log("[quickfix] 跳过部署与健康检查门禁");
}

// ---------- 阶段 10：交付（编排器直接汇总，不再花一次智能体调用——docs/03 §1.4）----------
phase("交付");
const gateSummary = [
  `lint=${gLint.exitCode}`,
  `build=${gBuild.exitCode}`,
  `test=${gTest.exitCode}`,
  `e2e=${gE2EPassed ? 0 : "?"}`,
  ...(healthPassed !== null ? [`health=0`] : []),
].join(" ");
const delivery = `交付摘要（${teamKey} 档）——改动：${changes.join(" ") || String(frontendResult || "")}；评审：${review}；测试：${testReport}；安全：${securityReport}；部署：${deploy}；门禁：${gateSummary} 全部真实 exit 0。未执行：${skipped.join("、") || "无"}。`;

return {
  ok: true,
  team: teamKey,
  pipeline: "闭环已跑通（按团队预设裁剪，v2 聚合门禁 + 局部退回）",
  gates: {
    lint: gLint.passed,
    build: gBuild.passed,
    test: gTest.passed,
    e2e: gE2EPassed,
    ...(healthPassed !== null ? { health: healthPassed } : {}),
  },
  skippedPhases: skipped,
  reviewRounds: reviewOutcome ? reviewOutcome.rounds : 0,
  codingGateRounds: coding.attempts,
  delivery: delivery,
  nextAction:
    teamKey === "quickfix"
      ? "quickfix 交付：未执行 PM/架构/QA/安全/部署。若本次改动影响面超出预期（触碰契约/鉴权/存储），请用 feature 或 full 档重跑完整验证"
      : "请人类在关键门禁（生产发布/最终验收）审批",
  artifacts: [
    "docs/requirements.md",
    "docs/architecture.md",
    "docs/api-spec.yaml",
    "docs/pipeline-status.md",
    "docs/review/",
    "docs/test/",
    "docs/runbook.md",
    "CHANGELOG.md",
  ],
};
