// 邮件提醒（macOS 外壳的 Mail.swift 调用；本文件是 macOS 移植新加的，不是上游的）
//   setMail(s)       名牌右边的小胶囊「✉ 4 · 王总」：{count, important, vipFrom}；没有未读时收起
//   mailArrived(m)   新邮件：{from, subject, account, important}。重要的用一个「信纸」样式的气泡念出来（发件人一行、主题一行），
//                    她短暂换成「听」的样子；不重要的只让胶囊跳一下
// 点胶囊、或点正在念邮件的气泡：发 {mail: 'open'} 给外壳，打开 Foxmail / 网页邮箱
;(() => {
  const ENVELOPE = `<svg viewBox="0 0 16 12" aria-hidden="true"><rect x=".8" y=".8" width="14.4" height="10.4" rx="1.8" fill="#fffaf3" stroke="currentColor" stroke-width="1.3"/>
    <path d="M1.6 2 L8 6.8 L14.4 2" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/></svg>`
  const css = document.createElement('style')
  css.textContent = `
/* 名牌那一行：名字 + 邮件胶囊并排，不增加底栏高度（底栏高了人物会被顶上去） */
#namerow { display: flex; align-items: center; justify-content: center; gap: calc(2px * var(--k)); max-width: calc(236px * var(--k)); }
#namerow #caption { flex: 0 1 auto; min-width: 0; }
#mailchip { flex: 0 0 auto; display: inline-flex; align-items: center; gap: calc(3px * var(--k)); max-width: calc(130px * var(--k));
  height: calc(16px * var(--k)); padding: 0 calc(6px * var(--k)); box-sizing: border-box; margin-top: calc(-2px * var(--k));
  border-radius: calc(8px * var(--k)); background: rgba(255,255,255,.95); border: calc(1.2px * var(--k)) solid var(--accent, #e0b48a);
  color: #8a4b2a; font-size: calc(10px * var(--k)); font-weight: 600; line-height: 1; white-space: nowrap; cursor: pointer;
  box-shadow: 0 1px 3px rgba(0,0,0,.15); transition: transform .25s, opacity .25s; }
#mailchip.hidden { display: none; }
#mailchip svg { width: calc(12px * var(--k)); height: calc(9px * var(--k)); flex: 0 0 auto; }
#mailchip .who { overflow: hidden; text-overflow: ellipsis; font-weight: 500; color: #6b4a3a; }
#mailchip.vip { border-color: #e0453a; color: #c8372d; }
#mailchip.bump { animation: mail-bump .7s ease-out; }
@keyframes mail-bump { 0% { transform: scale(1); } 25% { transform: scale(1.25) rotate(-6deg); } 50% { transform: scale(.95) rotate(4deg); } 75% { transform: scale(1.06); } 100% { transform: none; } }
html.moving #mailchip { animation: none; }

/* 念邮件的气泡：信纸底色、左对齐，两行——发件人（右边小字「点开」）、主题（太长省略）。窗口上方空间有限，不能再高 */
#bubble.mail { text-align: left; width: calc(228px * var(--k)); box-sizing: border-box; background: #fffaf3; border-color: #d9773f; padding: calc(6px * var(--k)) calc(10px * var(--k)); }
#bubble.mail .mh { display: flex; align-items: center; gap: calc(4px * var(--k)); color: #8a4b2a; font-size: calc(11px * var(--k)); }
#bubble.mail .mh svg { width: calc(14px * var(--k)); height: calc(10.5px * var(--k)); flex: 0 0 auto; color: #d9773f; }
#bubble.mail .mh b { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
#bubble.mail .mh span { white-space: nowrap; }
#bubble.mail .mt { margin-left: auto; padding-left: calc(8px * var(--k)); color: #b09a8c; font-size: calc(9px * var(--k)); white-space: nowrap; }
#bubble.mail .ms { margin-top: calc(1px * var(--k)); color: #4a2418; font-size: calc(12.5px * var(--k)); font-weight: 600; line-height: 1.3;
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }`
  document.head.append(css)

  // 名牌外面套一行，把胶囊放在名字右边
  const caption = $('caption')
  const row = document.createElement('div')
  row.id = 'namerow'
  caption.before(row)
  const chip = document.createElement('div')
  chip.id = 'mailchip'
  chip.className = 'hidden'
  row.append(caption, chip)
  hitElements.push(chip)
  hitResize.observe(chip)
  hitClasses.observe(chip, { attributes: true, attributeFilter: ['class'] })

  const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))
  const clip = (s, n) => (s.length > n ? s.slice(0, n - 1) + '…' : s)

  window.setMail = s => {
    const st = s || {}
    const n = Number(st.count) || 0, vip = Number(st.important) || 0
    const who = vip > 0 && st.vipFrom ? `<span class="who">· ${esc(clip(st.vipFrom, 8))}</span>` : ''
    chip.innerHTML = `${ENVELOPE}<span>${n > 99 ? '99+' : n}</span>${who}`
    chip.classList.toggle('vip', vip > 0)
    chip.classList.toggle('hidden', n === 0)
    scheduleHitRects()
  }

  // ---- 念邮件 ----
  // 她平常的台词也走 say()：念邮件的气泡至少留 MAIL_HOLD，这期间别的台词不盖掉它（道别除外）
  const MAIL_HOLD = 8000, MAIL_SHOW = 15000
  let mailShowing = false, holdUntil = 0, lineTimer = 0, poseTimer = 0, batch = [], batchTimer = 0
  const baseSay = say
  say = function (line) {
    if (mailShowing) {
      if (farewellLine === null && Date.now() < holdUntil) return
      mailShowing = false
      $('bubble').classList.remove('mail')
    }
    return baseSay(line)
  }

  window.mailArrived = m => {
    chip.classList.remove('bump'); void chip.offsetWidth; chip.classList.add('bump')
    if (!m?.important) return
    batch.push(m)
    clearTimeout(batchTimer)
    batchTimer = setTimeout(announce, 300)   // 几封一起到（比如刚开机）合成一个气泡
  }

  function announce() {
    const list = batch; batch = []
    if (!list.length || farewellLine !== null) return
    const last = list[list.length - 1]
    const head = list.length === 1 ? `<b>${esc(clip(last.from, 16))}</b>` : `<b>${list.length} 封新邮件</b><span>· 最新 ${esc(clip(last.from, 8))}</span>`
    lastActive = Date.now()
    // 闲着时转过来「嗯？」一下；AI 在干活、几个会话一起忙、被扔着、在拖时只弹气泡不换动作
    const calm = !aiActivity() && !multi && !tumble && !document.documentElement.classList.contains('moving') && RESTING.has(pose)
    if (calm && canShow('listening')) {
      show('listening', true)
      clearTimeout(poseTimer)
      poseTimer = setTimeout(() => { if (pose === 'listening' && !aiActivity()) show('idle', true) }, 4500)
    }
    holdUntil = 0; say('')   // 先清掉正在说的（也会结束上一封的气泡）
    baseSay('·')
    const b = $('bubble')
    b.innerHTML = `<div class="mh">${ENVELOPE}${head}<span class="mt">点开</span></div><div class="ms">${esc(last.subject)}</div>`
    b.classList.add('mail')
    mailShowing = true
    holdUntil = Date.now() + MAIL_HOLD
    scheduleHitRects()
    clearTimeout(lineTimer)
    lineTimer = setTimeout(() => { if (mailShowing) { holdUntil = 0; say('') } }, MAIL_SHOW)
  }

  const inside = (node, x, y) => {
    const r = node.getBoundingClientRect()
    return r.width > 0 && x >= r.left - 4 && x <= r.right + 4 && y >= r.top - 4 && y <= r.bottom + 4
  }
  const baseClick = handleClick
  handleClick = function (kind, x, y) {
    if (kind === 'pat' && x != null) {
      const onChip = !chip.classList.contains('hidden') && inside(chip, x, y)
      const onBubble = mailShowing && !$('bubble').classList.contains('hide') && inside($('bubble'), x, y)
      if (onChip || onBubble) {
        window.chrome?.webview?.postMessage({ mail: 'open' })
        if (onBubble) { holdUntil = 0; say('') }
        return
      }
    }
    return baseClick(kind, x, y)
  }
})()
