// usage-sampler.mjs —— 从 DSH 会话记录（逐帧追加的 zstd）采样 token 用量
// 用法：node usage-sampler.mjs <session.jsonl.zstd 路径> [...更多文件] [--dump <路径>]
// 输出：JSON { sessions:[{id,cwd,createdAt,requests,firstInput,input,output,total}], total:{...} }
// 字段事实（实测 DSH v4 会话记录）：
//   - 文件由多个 zstd 帧顺序追加而成，zstdDecompressSync 只解一帧，需按帧魔数切分逐帧解码；
//   - type=assistant/message 的 data.usage = { inputTokens, outputTokens, totalTokens }，
//     inputTokens 是该请求的完整输入（含系统提示+工具定义+AGENTS 指令链+累积上下文），
//     因此【每个会话第一条 assistant/message 的 inputTokens】≈ 该会话的固定注入基线。
import zlib from 'node:zlib';
import fs from 'node:fs';
import path from 'node:path';

const files = process.argv.slice(2).filter((a) => !a.startsWith('--'));
if (files.length === 0) {
  console.error('用法: node usage-sampler.mjs <session.v4.jsonl.zstd> [...更多] [--dump <路径>]');
  process.exit(1);
}

// 按 zstd 帧魔数 28 B5 2F FD 切分，逐帧解码拼接
function decodeZstdAppendFile(buf, tag) {
  const magics = [];
  for (let i = 0; i < buf.length - 3; i++) {
    if (buf[i] === 0x28 && buf[i + 1] === 0xB5 && buf[i + 2] === 0x2F && buf[i + 3] === 0xFD) magics.push(i);
  }
  const chunks = [];
  let pos = 0, frames = 0;
  for (const m of magics) {
    if (m <= pos) continue;
    try { chunks.push(zlib.zstdDecompressSync(buf.subarray(pos, m))); pos = m; frames++; } catch { /* 魔数误报，跳过 */ }
  }
  if (pos < buf.length) {
    try { chunks.push(zlib.zstdDecompressSync(buf.subarray(pos))); frames++; } catch (e) { console.error(`[${tag}] 尾帧解码失败: ${e.message}`); }
  }
  console.error(`[${tag}] 解码 ${frames} 帧 / ${magics.length} 个魔数位置`);
  return Buffer.concat(chunks).toString('utf8');
}

const sessions = [];
let dumpIdx = process.argv.indexOf('--dump');

for (const file of files) {
  const tag = path.basename(path.dirname(file));
  const text = decodeZstdAppendFile(fs.readFileSync(file), tag);
  if (dumpIdx > 0 && process.argv[dumpIdx + 1]) {
    fs.writeFileSync(process.argv[dumpIdx + 1] + '.' + tag, text, 'utf8');
  }
  const lines = text.split('\n').filter((l) => l.trim());

  // 会话元信息
  let meta = { id: '(unknown)', cwd: '', createdAt: null };
  let requests = 0, input = 0, output = 0, firstInput = null;
  let parsed = 0;
  for (const line of lines) {
    let obj;
    try { obj = JSON.parse(line); parsed++; } catch { continue; }
    if (obj.type === 'session') {
      meta = { id: obj.id || meta.id, cwd: obj.cwd || '', createdAt: obj.createdAt || null };
    }
    if (obj.type === 'assistant/message' && obj.data && obj.data.usage) {
      const u = obj.data.usage;
      const inTok = u.inputTokens || 0, outTok = u.outputTokens || 0;
      if (firstInput === null) firstInput = inTok;
      input += inTok; output += outTok; requests++;
    }
  }
  console.error(`[${tag}] 可解析 ${parsed}/${lines.length} 行，assistant 请求 ${requests} 条`);
  if (requests === 0) continue;
  sessions.push({
    id: meta.id, cwd: meta.cwd, createdAt: meta.createdAt,
    requests, firstInput, input, output, total: input + output,
  });
}

const total = sessions.reduce(
  (acc, s) => ({ requests: acc.requests + s.requests, input: acc.input + s.input, output: acc.output + s.output, total: acc.total + s.total }),
  { requests: 0, input: 0, output: 0, total: 0 }
);
// 固定注入估算：每个会话首请求输入之和（≈ 指令链 + 工具定义 + 系统提示 + 首条用户消息）
const fixedInject = sessions.reduce((a, s) => a + (s.firstInput || 0), 0);

const result = {
  files: files.length,
  sessions,
  total,
  fixedInjectEstimate: fixedInject,
  fixedInjectRatio: total.input > 0 ? +(fixedInject / total.input).toFixed(4) : 0,
};
console.log(JSON.stringify(result, null, 2));
