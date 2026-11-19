// macOS 移植：站在 Claude Code 输入框上。窗口怎么跳、跳到哪由外壳（mac/Sources/Perch.swift）管，
// 这里只管起跳 / 落地时人物压扁拉长、说句话，和把脚底位置告诉外壳。
;(function () {
  const LINES = {
    arrive: ['我来输入框这儿陪你～', '写吧，我看着呢', '你说，我听着～'],
    learned: ['记住啦，以后就站这儿～'],
  }
  const reduced = () => matchMedia('(prefers-reduced-motion: reduce)').matches
  let sayTimer = null

  // 脚底中心（人物 #body 的底边中点）在页面里的位置，CSS 像素；用 offset 算，不受正在播的动画影响
  window.perchFeet = function () {
    const b = document.getElementById('body')
    let x = b.offsetWidth / 2, y = b.offsetHeight, el = b
    while (el) { x += el.offsetLeft; y += el.offsetTop; el = el.offsetParent }
    return JSON.stringify([x, y])
  }

  window.perchHop = function (phase, dur) {
    if (reduced()) return
    const el = document.getElementById('impact')
    try { impactAnimation?.cancel() } catch (e) {}
    const a = phase === 'up'
      ? el.animate([   // 蹲一下 → 蹬出去拉长 → 空中恢复
          { transform: 'scale(1)' }, { transform: 'scale(1.07,.9)', offset: .1 },
          { transform: 'scale(.95,1.07)', offset: .28 }, { transform: 'scale(1)', offset: .6 }, { transform: 'scale(1)' }
        ], { duration: Math.max(240, dur * 1000) })
      : el.animate([   // 落地压扁再弹回
          { transform: 'scale(1)' }, { transform: 'scale(1.09,.88)', offset: .3 },
          { transform: 'scale(.98,1.03)', offset: .7 }, { transform: 'scale(1)' }
        ], { duration: 230, easing: 'ease-out' })
    try { impactAnimation = a } catch (e) {}
    try { scheduleHitRects() } catch (e) {}
  }

  window.perchSay = function (kind) {
    let lines = null
    try { lines = typeof linesOf === 'function' ? linesOf('perch_' + kind) : null } catch (e) {}
    lines = lines && lines.length ? lines : LINES[kind]
    if (!lines) return
    const line = lines[Math.floor(Math.random() * lines.length)]
    say(line)
    clearTimeout(sayTimer)
    sayTimer = setTimeout(() => { if (document.getElementById('bubble').textContent === line) say('') }, 4000)
  }
})()
