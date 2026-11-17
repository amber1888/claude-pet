import type { EngineInterface, Register } from 'claude-code'

// claudia-pet（macOS）× Claude Code
// 把会话里发生的事写成几个小文件，桌宠每 0.3 秒读一次：
//   ~/.claudia/state/claude-state.json     现在在干什么（听你说、思考、读文件、跑命令、完成、出错、等你回答……）
//   ~/.claudia/state/claude-sessions.json  好几个会话同时干活时，各自在干什么
//   ~/.claudia/state/claude-quota.json     5 小时 / 每周额度（session.measure 推来的）
//   ~/.claudia/state/claude-notify-*.json  完成 / 出错 / 等你回答的通知事件
// 会话开始、你发消息时顺便叫她出来（open -g -b local.claudia-pet.mac --args --ensure；你从菜单退出过就不出来）。
// 只写本机的状态文件，不改 Claude 的行为，出错也不影响会话。
// 移植自 claudia-pet（kirito1207）的 Windows 版插件（MIT，改自 CrossPet 的 Claude Code mod），只改了路径和拉起方式。

const BUNDLE_ID = 'local.claudia-pet.mac'

let dir: string | undefined
async function stateDir($: EngineInterface): Promise<string | undefined> {
  if (dir) return dir
  const custom = await $.env.get('CLAUDIA_STATE_DIR')
  const home = await $.env.get('HOME')
  dir = custom || (home ? `${home}/.claudia/state` : undefined)
  return dir
}
async function write($: EngineInterface, file: string, data: unknown): Promise<void> {
  const d = await stateDir($)
  if (!d) return
  await $.fs.write(`${d}/${file}`, typeof data === 'string' ? data : JSON.stringify(data))
}

type State = { pose: string; event: string; tool: string; ts: number }
async function setState($: EngineInterface, state: State): Promise<void> {
  try {
    await write($, 'seen-plugin', String(Math.floor(Date.now() / 1000)))   // 心跳：菜单里显示「上次收到消息」
    let sid = ''
    try { sid = await $.session.id() } catch {}
    await write($, 'claude-state.json', { ...state, sid, noticeV: 1 })
    const d = await stateDir($)
    if (!d) return
    const file = `${d}/claude-sessions.json`
    let known: Record<string, { pose: string; event: string; ts: number }> = {}
    try { known = JSON.parse(await $.fs.read(file)) } catch {}
    known[sid] = { pose: state.pose, event: state.event, ts: state.ts }
    const now = Date.now() / 1000
    for (const k of Object.keys(known)) if (now - known[k].ts > 600) delete known[k]
    await $.fs.write(file, JSON.stringify(known))
  } catch {}   // 写不了就算了：不能影响 Claude
}

// 每个会话一份通知事件文件，避免两次轮询之间的短暂状态丢掉
let noticeSequence = 0
async function notify($: EngineInterface, kind: 'complete' | 'error' | 'waiting'): Promise<void> {
  try {
    const d = await stateDir($); if (!d) return
    let sid = 'default'; try { sid = await $.session.id() } catch {}
    const file = `${d}/claude-notify-${encodeURIComponent(sid).slice(0, 100)}.json`
    let events: { id: string; kind: string; ts: number }[] = []
    try { events = JSON.parse(await $.fs.read(file)).events || [] } catch {}
    const ts = Date.now() / 1000
    events = events.filter(e => ts - e.ts < 120).slice(-31)
    events.push({ id: `${sid}:${Date.now()}:${++noticeSequence}`, kind, ts })
    await $.fs.write(file, JSON.stringify({ events }))
  } catch {} // 通知失败不能影响 Claude 会话
}

// 叫她出来：一分钟内最多一次；没装 / 出错都不影响 Claude
let lastEnsure = 0
async function ensurePet($: EngineInterface): Promise<void> {
  if (Date.now() - lastEnsure < 60_000) return
  lastEnsure = Date.now()
  await $.process.run(['/usr/bin/open', '-g', '-b', BUNDLE_ID, '--args', '--ensure'], { timeoutMs: 10_000 })
}

function poseForTool(tool: string): string {
  const t = tool.toLowerCase()
  if (t === 'askuserquestion') return 'asking'  // 停下来问你问题、让你选
  if (/read|grep|glob|list|view|cat/.test(t)) return 'reading'
  if (/write|edit|patch|replace|create/.test(t)) return 'writing'
  if (/web|fetch|browse|search|http/.test(t)) return 'searching'
  if (/agent|task|subagent|delegate/.test(t)) return 'delegating'
  return 'running'
}

// 额度：各窗口显示「已用」百分比，只给用得最多的那个标重置时间；bars 给「额度条」样式用，里面存剩余比例 left
type Limit = { kind: string; percentUsed: number; resetsAt?: string }
const LABEL: Record<string, string> = { five_hour: '5小时', seven_day: '本周', spend_limit: '花费' }
export function quotaOf(limits: Limit[]) {
  const shown = limits.filter(l => l.kind in LABEL)
  if (shown.length === 0) return null
  const top = shown.reduce((a, b) => (b.percentUsed > a.percentUsed ? b : a))
  const pad = (n: number) => String(n).padStart(2, '0')
  const parts = shown.map(l => {
    let piece = `${LABEL[l.kind]} 已用 ${Math.min(100, Math.max(0, Math.round(l.percentUsed)))}%`
    if (l === top && l.resetsAt) {
      const d = new Date(l.resetsAt)
      const soon = d.getTime() - Date.now() < 86_400_000
      piece += ` · ${soon ? `${pad(d.getHours())}:${pad(d.getMinutes())}` : `${d.getMonth() + 1}/${d.getDate()}`} 重置`
    }
    return piece
  })
  const bars = shown.map(l => ({
    label: LABEL[l.kind],
    left: Math.max(0, 100 - Math.round(l.percentUsed)) / 100,
    ...(l.resetsAt ? { reset: Math.round(new Date(l.resetsAt).getTime() / 1000) } : {}),
  }))
  return { text: parts.join(' ｜ '), low: top.percentUsed >= 90, bars }
}

// 空额度：网页按它不显示额度、不算紧张、不换钱袋档位
export const NO_QUOTA = { text: '', low: false, bars: [] as never[] }

const BIG_JOB_TOOLS = 8   // 一轮里用了这么多次工具，完成时「得意」一下

export const register: Register = on => {
  let tools = 0
  const now = () => Date.now() / 1000

  on('session.start', async ($, e, next) => {
    void ensurePet($).catch(() => {})
    await setState($, { pose: 'idle', event: 'SessionStart', tool: '', ts: now() })
    // 这次会话一个认得的额度都没报（换成别的模型 / 别家接口时）：写一份空额度把旧数字清掉
    try {
      const q = quotaOf((await $.session.usage()).rateLimits ?? [])
      await write($, 'claude-quota.json', q ?? NO_QUOTA)
    } catch {}
    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    void ensurePet($).catch(() => {})
    tools = 0
    await setState($, { pose: 'listening', event: 'UserPromptSubmit', tool: '', ts: now() })
    return next(e)
  })

  on('tool.call', async ($, e, next) => {
    tools += 1
    if (e.tool.toLowerCase() === 'askuserquestion') await notify($, 'waiting')
    await setState($, { pose: poseForTool(e.tool), event: 'PreToolUse', tool: e.tool, ts: now() })
    const r = await next(e)
    const failed = 'deny' in r && r.deny !== undefined ? true : r.isError === true
    await setState($, { pose: failed ? 'oops' : 'thinking', event: 'PostToolUse', tool: e.tool, ts: now() })
    return r
  })

  on('turn.complete', async ($, e, next) => {
    const r = await next(e)
    const pose = e.reason === 'answer' ? (tools >= BIG_JOB_TOOLS ? 'proud' : 'happy') : e.reason === 'aborted' ? 'surprised' : 'oops'
    tools = 0
    await setState($, { pose, event: 'Stop', tool: '', ts: now() })
    if (e.reason === 'answer') await notify($, 'complete')
    else if (e.reason !== 'aborted') await notify($, 'error')
    return r
  })

  // 要你授权 / MCP 要你填表：只认真的弹到你面前的那一刻
  on('classic.Notification', async ($, e, next) => {
    const kind = String(e.notification_type ?? '').toLowerCase()
    if (kind === 'permission_prompt' || kind === 'elicitation_dialog') {
      await setState($, { pose: 'asking', event: 'Notification', tool: '', ts: now() })
      await notify($, 'waiting')
    }
    return next(e)
  })

  // 压缩上下文：只管主对话；手动 /compact 压完这一轮就结束了，得自己收尾
  on('session.compact', async ($, e, next) => {
    const shown = (e.trigger === 'manual' || e.trigger === 'auto') && !e.agentId
    if (shown) await setState($, { pose: 'compact', event: 'PreCompact', tool: '', ts: now() })
    const r = await next(e)
    if (shown) await setState($, e.trigger === 'manual'
      ? { pose: 'happy', event: 'Stop', tool: '', ts: now() }
      : { pose: 'thinking', event: 'PostCompact', tool: '', ts: now() })
    return r
  })

  on('session.measure', async ($, e, next) => {
    try {
      const q = quotaOf(e.rateLimits.map(l => ({ kind: l.kind, percentUsed: l.percentUsed, resetsAt: l.resetsAt })))
      if (q) await write($, 'claude-quota.json', q)
    } catch {}
    return next(e)
  })
}
