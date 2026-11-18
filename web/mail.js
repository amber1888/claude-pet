// 邮件提醒（macOS 外壳的 Mail.swift 调用；本文件是 macOS 移植新加的，不是上游的）
//   setMail(s)       信封角标：{count, important, latest: [{from, subject}]}；count 为 0 时收起
//   mailArrived(m)   新邮件：{from, subject, account, important}。重要的她会念出来（短暂换成「听」的样子），其他的只让信封晃一下
// 点信封、或点正在念邮件的气泡：发 {mail: 'open'} 给外壳，打开 Foxmail / 网页邮箱
;(() => {
  const css = document.createElement('style')
  css.textContent = `
#mail { position: absolute; left: 16px; bottom: 30px; z-index: 6; width: 34px; height: 26px; cursor: pointer;
  transition: opacity .3s, transform .3s; filter: drop-shadow(0 1px 2px rgba(0,0,0,.18)); }
#mail.hidden { opacity: 0; transform: scale(.6); pointer-events: none; }
#mail svg { width: 34px; height: 26px; display: block; }
#mail b { position: absolute; right: -7px; top: -7px; min-width: 16px; height: 16px; padding: 0 4px; box-sizing: border-box;
  border-radius: 8px; background: #c9874f; color: #fff; font: 600 10px/16px -apple-system, sans-serif; text-align: center; }
#mail.vip b { background: #e0453a; }
#mail.ring { animation: mail-ring .9s ease-in-out 2; }
@keyframes mail-ring { 0%,100% { transform: rotate(0); } 15% { transform: rotate(-14deg) scale(1.12); } 30% { transform: rotate(12deg) scale(1.12); }
  45% { transform: rotate(-9deg); } 60% { transform: rotate(6deg); } 75% { transform: rotate(-3deg); } }
html.moving #mail { animation: none; }`
  document.head.append(css)

  const el = document.createElement('div')
  el.id = 'mail'
  el.className = 'hidden'
  el.innerHTML = `<svg viewBox="0 0 34 26"><rect x="1.5" y="2.5" width="31" height="21" rx="3" fill="#fffaf3" stroke="#8a4b2a" stroke-width="1.6"/>
    <path d="M2.5 4.5 L17 15 L31.5 4.5" fill="none" stroke="#8a4b2a" stroke-width="1.6" stroke-linejoin="round"/>
    <circle cx="17" cy="15" r="2.6" fill="#d9773f"/></svg><b></b>`
  $('stage').append(el)
  // 能点到：加进外壳的点击区域（index.html 的 hitRects 会跳过带 hidden 的）
  hitElements.push(el)
  hitResize.observe(el)
  hitClasses.observe(el, { attributes: true, attributeFilter: ['class'] })

  let state = { count: 0 }
  window.setMail = s => {
    state = s || { count: 0 }
    const n = Number(state.count) || 0
    el.querySelector('b').textContent = n > 99 ? '99+' : String(n)
    el.classList.toggle('vip', (Number(state.important) || 0) > 0)
    el.classList.toggle('hidden', n === 0)
    el.title = (state.latest || []).map(m => `${m.from}：${m.subject}`).join('\n')
    scheduleHitRects()
  }

  // 几封同时到（比如开机后第一次检查）合成一句
  let batch = [], batchTimer = 0, mailLine = null, lineTimer = 0, poseTimer = 0
  const clip = (s, n) => (s.length > n ? s.slice(0, n - 1) + '…' : s)
  window.mailArrived = m => {
    el.classList.remove('ring'); void el.offsetWidth; el.classList.add('ring')
    if (!m?.important) return
    batch.push(m)
    clearTimeout(batchTimer)
    batchTimer = setTimeout(announce, 300)
  }
  function announce() {
    const list = batch; batch = []
    if (!list.length || farewellLine !== null) return
    const first = list[list.length - 1]
    mailLine = list.length === 1
      ? `📮 ${clip(first.from, 12)}：${clip(first.subject, 28)}`
      : `📮 收到 ${list.length} 封新邮件，最新：${clip(first.from, 10)}「${clip(first.subject, 18)}」`
    lastActive = Date.now()
    // 闲着时转过来「嗯？」一下；AI 在干活、几个会话一起忙、被扔着、在拖时只说话不换动作
    const calm = !aiActivity() && !multi && !tumble && !document.documentElement.classList.contains('moving') && RESTING.has(pose)
    if (calm && canShow('listening')) {
      show('listening', true)
      clearTimeout(poseTimer)
      poseTimer = setTimeout(() => { if (pose === 'listening' && !aiActivity()) show('idle', true) }, 4500)
    }
    say(mailLine)
    clearTimeout(lineTimer)
    lineTimer = setTimeout(() => { if ($('bubble').textContent === mailLine) say(''); mailLine = null }, 12000)
  }

  const inside = (node, x, y) => {
    const r = node.getBoundingClientRect()
    return r.width > 0 && x >= r.left - 4 && x <= r.right + 4 && y >= r.top - 4 && y <= r.bottom + 4
  }
  const baseClick = handleClick
  handleClick = function (kind, x, y) {
    if (kind === 'pat' && x != null) {
      const onEnvelope = !el.classList.contains('hidden') && inside(el, x, y)
      const onMailLine = mailLine && $('bubble').textContent === mailLine && !$('bubble').classList.contains('hide') && inside($('bubble'), x, y)
      if (onEnvelope || onMailLine) {
        window.chrome?.webview?.postMessage({ mail: 'open' })
        if (onMailLine) { say(''); mailLine = null }
        return
      }
    }
    return baseClick(kind, x, y)
  }
})()
