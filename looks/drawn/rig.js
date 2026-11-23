// 用代码画的形象：三位大小姐（金卷 / 黑蔷薇 / 紫藤），本项目原创。scripts/draw-look.swift 把它渲染成立绘和精灵图。
// 人物坐标：脚底中点是原点，y 向下，人物高约 900（头顶到脚底），Q 版两头身：大头、短身子、蓬蓬裙。
// 画法：每个部件是一段 SVG，填色 + 同色系的深色线条 + 两色平涂阴影和高光；整个人物外面再套一圈更粗的深色轮廓（SVG 滤镜膨胀出来的），
// 里细外粗，像手绘的线稿。姿态只写「手放哪、脸什么表情、拿什么」，手肘用两节骨骼反解。
// 动画：姿态是 t（0～1）的函数，循环的动画首尾接得上；精灵图每帧 t = i / 帧数。
const RIG = (() => {
  const TAU = Math.PI * 2
  const r1 = n => Math.round(n * 10) / 10
  const wave = (t, n = 1, ph = 0) => Math.sin(TAU * (t * n + ph))
  const bump = (t, a, b) => (t <= a || t >= b) ? 0 : Math.sin(Math.PI * (t - a) / (b - a))
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v))
  const deg = r => r * 180 / Math.PI
  const lerp = (a, b, k) => a + (b - a) * k

  // ---------------- 三位大小姐 ----------------
  // 每种材质：base 底色、shade 阴影、deep 更深的阴影、light 高光、line 线条（同色系的深色）
  const DESIGNS = {
    'ojou-gold': {
      ink: '#5a2a36',
      skin: { base: '#fff3ec', shade: '#fcd5c8', line: '#c27463' }, blush: '#ff7f99',
      hair: { style: 'drills', base: '#ffe18e', shade: '#f6bd57', deep: '#e49b3c', light: '#fffbe6', line: '#b36a22', brow: '#b8742c' },
      eye: { dark: '#16357d', base: '#3577dd', light: '#93d6ff', line: '#3b1f2a' },
      cloth: { base: '#ffb6ca', shade: '#f48aa6', deep: '#dc6286', light: '#ffe3ea', line: '#b94369' },
      lace: { base: '#fffefe', shade: '#f7dde5', line: '#cc8ea2' },
      accent: { base: '#e5364f', shade: '#b51f3d', light: '#ff7d8e', line: '#7c1229' },
      metal: { base: '#ffd45e', shade: '#dd9c24', light: '#fff4c2', line: '#9a6212' },
      legs: { base: '#ffffff', shade: '#f1e2e8', line: '#c99aaa' }, shoe: { base: '#de3a5a', shade: '#aa2041', light: '#ff8fa3', line: '#6e0f25' },
      book: { base: '#cf3a55', shade: '#9e2440', light: '#f07890', line: '#681226' },
      skirt: 'tiered', collar: 'round', prop: 'fan',
    },
    'ojou-noir': {
      ink: '#1c1520',
      skin: { base: '#fff4f0', shade: '#f2d2cb', line: '#b9776f' }, blush: '#ff8597',
      hair: { style: 'hime', base: '#554b7c', shade: '#3e3663', deep: '#2d274a', light: '#aca1e4', line: '#1d1829', brow: '#2c2540' },
      eye: { dark: '#6e0b1f', base: '#d3283f', light: '#ff9aa6', line: '#24141c' },
      cloth: { base: '#38333d', shade: '#26222b', deep: '#1a171e', light: '#615a69', line: '#0f0c12' },
      lace: { base: '#fbf7f8', shade: '#e3d8dd', line: '#9d8f97' },
      accent: { base: '#c8243f', shade: '#8f1630', light: '#f0607a', line: '#4e0a19' },
      metal: { base: '#e9e4ee', shade: '#aaa1b5', light: '#ffffff', line: '#5e566b' },
      legs: { base: '#3a3442', shade: '#28232f', line: '#0f0c12' }, shoe: { base: '#2a2530', shade: '#17141b', light: '#6a6274', line: '#0b090d' },
      book: { base: '#2f2a35', shade: '#1a171e', light: '#5f5868', line: '#0b090d' },
      skirt: 'gothic', collar: 'high', prop: 'parasol', shoeBow: true,
    },
    'ojou-lilac': {
      ink: '#3f3459',
      skin: { base: '#fff3ee', shade: '#f8d4ca', line: '#c27d74' }, blush: '#ff8fb4',
      hair: { style: 'wavy', base: '#f2effb', shade: '#cdc5ea', deep: '#ada2d6', light: '#ffffff', line: '#7f73ad', brow: '#9286bd' },
      eye: { dark: '#0d5e66', base: '#21aaa2', light: '#a8f2e2', line: '#2c2240' },
      cloth: { base: '#cbb8f0', shade: '#a991e0', deep: '#8c72cc', light: '#ebe2ff', line: '#6a52a8' },
      lace: { base: '#ffffff', shade: '#e6e0f3', line: '#9f93c4' },
      accent: { base: '#8c5fd4', shade: '#6942ad', light: '#b996f0', line: '#3f2575' },
      metal: { base: '#e6ecf6', shade: '#a6b1ca', light: '#ffffff', line: '#5d6784' },
      legs: { base: '#ffffff', shade: '#e8e3f3', line: '#a89cc9' }, shoe: { base: '#a184de', shade: '#7458b8', light: '#d3c2fb', line: '#3f2575' },
      book: { base: '#8f72cf', shade: '#6750a6', light: '#bba6f0', line: '#3f2575' },
      skirt: 'apron', collar: 'jabot', prop: 'teacup',
    },
  }
  const FLOWER = { base: '#f6904e', shade: '#d8692f', light: '#ffd9a6', line: '#8a3b14' }   // 小橙花：claudia 的标志，三位都别着一朵

  // ---------------- SVG 小工具 ----------------
  let D, defs, uid
  const LW = 3.6                    // 里面的线；外轮廓另外套
  const at = o => Object.entries(o).filter(([, v]) => v !== undefined && v !== null && v !== false)
    .map(([k, v]) => `${k}="${typeof v === 'number' ? r1(v) : v}"`).join(' ')
  const P = (d, o = {}) => `<path d="${d}" ${at(o)}/>`
  const E = (cx, cy, rx, ry, o = {}) => `<ellipse cx="${r1(cx)}" cy="${r1(cy)}" rx="${r1(rx)}" ry="${r1(ry)}" ${at(o)}/>`
  const C = (cx, cy, r, o = {}) => `<circle cx="${r1(cx)}" cy="${r1(cy)}" r="${r1(r)}" ${at(o)}/>`
  const G = (inner, o = {}) => `<g ${at(o)}>${inner}</g>`
  const ink = (c, w = LW) => ({ fill: 'none', stroke: c, 'stroke-width': w, 'stroke-linejoin': 'round', 'stroke-linecap': 'round' })
  const flat = (c, op) => ({ fill: c, opacity: op })
  const rot = (a, x, y) => `rotate(${r1(a)} ${r1(x)} ${r1(y)})`
  const tr = (x, y) => `translate(${r1(x)} ${r1(y)})`
  const pts = a => a.map(p => `${r1(p[0])} ${r1(p[1])}`).join(' ')
  const onE = (cx, cy, rx, ry, a) => [cx + rx * Math.cos(a), cy + ry * Math.sin(a)]
  const ell = (cx, cy, rx, ry) => `M${r1(cx - rx)} ${r1(cy)} a${r1(rx)} ${r1(ry)} 0 1 0 ${r1(rx * 2)} 0 a${r1(rx)} ${r1(ry)} 0 1 0 ${r1(-rx * 2)} 0Z`
  function clipTo(d, inner) {
    const id = 'c' + (uid++)
    defs.push(`<clipPath id="${id}"><path d="${d}"/></clipPath>`)
    return G(inner, { 'clip-path': `url(#${id})` })
  }
  // 一个部件：底色 + 剪在形状里的阴影高光 + 线条。m 是材质（base / line），也可以直接给颜色
  function part(d, m, inner = '', w = LW) {
    const base = typeof m === 'string' ? m : m.base, line = typeof m === 'string' ? D.ink : m.line
    return P(d, flat(base)) + (inner ? clipTo(d, inner) : '') + P(d, ink(line, w))
  }

  // ---------------- 身体 ----------------
  const SH = 84, SHY = -440            // 肩膀
  const UP = 66, FORE = 72             // 上臂、前臂
  const WAIST = -372                    // 高腰，裙子从这里蓬开
  function ik(S, H, side, prefer) {
    const dx = H[0] - S[0], dy = H[1] - S[1], d0 = Math.hypot(dx, dy) || 1
    const d = clamp(d0, Math.abs(UP - FORE) + 1, UP + FORE - 1), ux = dx / d0, uy = dy / d0
    const A = Math.acos(clamp((UP * UP + d * d - FORE * FORE) / (2 * UP * d), -1, 1)), base = Math.atan2(uy, ux)
    const cands = [base + A, base - A].map(a => [S[0] + UP * Math.cos(a), S[1] + UP * Math.sin(a)])
    const score = e => prefer === 'down' ? e[1] : prefer === 'in' ? -side * e[0] : side * e[0] + e[1] * 0.25
    const e = score(cands[0]) >= score(cands[1]) ? cands[0] : cands[1]
    return { E: e, H: [S[0] + ux * d, S[1] + uy * d] }
  }
  function arm(a, side, U) {
    const S = [side * SH, SHY + U], { E: El, H } = ik(S, [a.hand[0], a.hand[1] + U], side, a.prefer)
    const fx = H[0] - El[0], fy = H[1] - El[1], fl = Math.hypot(fx, fy) || 1, ux = fx / fl, uy = fy / fl
    const W = [H[0] - ux * 18, H[1] - uy * 18]
    const c = D.cloth
    const tube = `M${pts([S, El, W])}`
    const rnd = { 'stroke-linejoin': 'round', 'stroke-linecap': 'round', fill: 'none' }
    let o = P(tube, { ...rnd, stroke: c.line, 'stroke-width': 36 + LW * 2 }) + P(tube, { ...rnd, stroke: c.base, 'stroke-width': 36 })
      + P(`M${pts([[S[0] + side * 7, S[1] + 8], [El[0] + side * 9, El[1] + 2], [W[0] + side * 7, W[1]]])}`, { ...rnd, stroke: c.shade, 'stroke-width': 13 })
    // 袖口花边（手腕）
    o += G(frill(W[0], W[1], 24, 11, D.lace, 5), { transform: rot(deg(Math.atan2(uy, ux)) + 90, W[0], W[1]) })
    o += hand(H, ux, uy, side)
    // 泡泡袖：盖住肩膀和上臂上半截，袖口一圈花边，肩头几道褶
    const pa = deg(Math.atan2(El[1] - S[1], El[0] - S[0]))
    const pc = [S[0] + (El[0] - S[0]) * 0.22, S[1] + (El[1] - S[1]) * 0.22]
    const puff = ell(pc[0], pc[1], 47, 41)
    let p = G(frill(pc[0] + 36, pc[1], 33, 11, D.lace, 6), { transform: `rotate(90 ${r1(pc[0] + 36)} ${r1(pc[1])})` })
    p += part(puff, c, E(pc[0] + 14, pc[1] + 24, 46, 24, flat(c.shade)) + E(pc[0] - 14, pc[1] - 18, 20, 10, flat(c.light))
      + P(`M${pc[0] - 30} ${pc[1] - 26} Q${pc[0] - 12} ${pc[1] - 10} ${pc[0] - 8} ${pc[1] + 12} M${pc[0] - 40} ${pc[1] - 6} Q${pc[0] - 22} ${pc[1] + 4} ${pc[0] - 20} ${pc[1] + 26}`, ink(c.line, 2.6)))
    o += G(p, { transform: rot(pa, pc[0], pc[1]) })
    return { out: o, H, El }
  }
  // 一圈小花边（cx, cy 中心，rx 半宽，ry 半高；n 个小弧），竖着的褶线
  function frill(cx, cy, rx, ry, m, n = 5) {
    const w = rx * 2 / n
    let d = `M${cx - rx} ${cy}`
    for (let i = 0; i < n; i++) d += ` q${w / 2} ${ry * 1.6} ${w} 0`
    d += ` C${cx + rx} ${cy - ry * 1.7} ${cx - rx} ${cy - ry * 1.7} ${cx - rx} ${cy}Z`
    let pleats = ''
    for (let i = 1; i < n; i++) pleats += `M${cx - rx + i * w} ${cy + ry * 0.2} l0 ${-ry * 0.9}`
    return part(d, m, E(cx, cy + ry * 0.8, rx, ry * 0.55, flat(m.shade)) + P(pleats, ink(m.line, 2)), LW * 0.85)
  }
  function hand([x, y], ux, uy, side) {
    // 圆圆的小手：掌心 + 一个大拇指
    const nx = -uy * side, ny = ux * side
    const tx = x - ux * 4 + nx * 14, ty = y - uy * 4 + ny * 14
    return part(ell(tx, ty, 9, 9), D.skin) + part(ell(x, y, 20, 18), D.skin, E(x + 5, y + 9, 17, 9, flat(D.skin.shade)))
  }

  function legs() {
    let o = ''
    const L = D.legs, S = D.shoe
    for (const s of [-1, 1]) {
      const x = s * 36
      o += part(`M${x - 16} -160 L${x - 15} -32 L${x + 15} -32 L${x + 16} -160Z`, L, P(`M${x + s * 4} -160 L${x + s * 6} -30 L${x + s * 18} -30 L${x + s * 18} -160Z`, flat(L.shade)))
      const sx = x + s * 6
      o += part(`M${sx - 33} -1 C${sx - 42} -28 ${sx - 22} -44 ${sx + 1} -44 C${sx + 26} -44 ${sx + 43} -28 ${sx + 35} -1 Q${sx} 4 ${sx - 33} -1Z`, S,
        P(`M${sx - 44} -12 Q${sx} -4 ${sx + 46} -12 L${sx + 46} 8 L${sx - 44} 8Z`, flat(S.shade)) + E(sx - 12, -30, 12, 6, flat(S.light, 0.8)))
      o += P(`M${x - 16} -38 Q${x} -32 ${x + 16} -38`, ink(S.line, 7)) + P(`M${x - 16} -38 Q${x} -32 ${x + 16} -38`, ink(S.base, 3.5))
      if (D.shoeBow) o += bow(sx, -40, 0.3, D.accent)
    }
    return o
  }

  // 裙子：腰在 wy，下摆在 hy，下摆半宽 hw；n 个花边弧。dome：坐着时摊开成半圆
  function bell(wy, hy, ww, hw, n, drop = 22, dome = false) {
    const a = dome ? [-ww - 160, wy + 4, -hw - 16, hy - 120] : [-ww - 60, wy + 24, -hw - 2, hy - 120]
    let d = `M${-ww} ${wy} C${a[0]} ${a[1]} ${a[2]} ${a[3]} ${-hw} ${hy}`
    const w = hw * 2 / n
    for (let i = 0; i < n; i++) d += ` q${w / 2} ${drop} ${w} 0`
    d += ` C${-a[2]} ${a[3]} ${-a[0]} ${a[1]} ${ww} ${wy}Z`
    return d
  }
  // 裙褶：从腰往下散开的几道阴影 + 几道亮面，两边暗
  function folds(wy, hy, hw, m, n = 5) {
    let o = ''
    for (let i = 0; i < n; i++) {
      const k = (i + 0.5) / n * 2 - 1, x = k * hw * 0.84, top = k * 40, sh = i % 2 === 1
      const w = sh ? 22 : 7, y0 = lerp(wy, hy, sh ? 0.3 : 0.45)
      o += P(`M${lerp(top, x, 0.3)} ${y0} Q${lerp(top, x, 0.62) - w * 0.4} ${lerp(y0, hy, 0.5)} ${x - w} ${hy + 30} L${x + w} ${hy + 30} Q${lerp(top, x, 0.62) + w * 0.4} ${lerp(y0, hy, 0.5)} ${lerp(top, x, 0.3) + 2} ${y0}Z`, flat(sh ? m.shade : m.light, sh ? 0.9 : 0.7))
    }
    return o + P(`M${hw * 0.55} ${wy} Q${hw * 0.9} ${hy - 80} ${hw * 0.72} ${hy + 40} L${hw + 60} ${hy + 40} L${hw + 60} ${wy}Z`, flat(m.shade))
      + P(`M${-hw * 0.6} ${wy} Q${-hw * 0.95} ${hy - 80} ${-hw * 0.84} ${hy + 40} L${-hw - 60} ${hy + 40} L${-hw - 60} ${wy}Z`, flat(m.shade, 0.55))
  }
  // 一条花边：上边顺着裙摆，下边一串小弧，带褶线
  function laceBand(y, hw, h, n, m, curve = 10) {
    const w = hw * 2 / n
    let d = `M${-hw} ${y - h} Q0 ${y - h + curve} ${hw} ${y - h} L${hw} ${y}`
    for (let i = 0; i < n; i++) d += ` q${-w / 2} ${h * 0.85} ${-w} 0`
    let pleats = ''
    for (let i = 1; i < n; i++) pleats += `M${-hw + i * w} ${y + 2} L${-hw + i * w} ${y - h * 0.55}`
    return part(d + 'Z', m, P(`M${-hw} ${y - h * 0.3} L${hw} ${y - h * 0.3} L${hw} ${y + h} L${-hw} ${y + h}Z`, flat(m.shade)) + P(pleats, ink(m.line, 2)), LW * 0.85)
  }
  function skirt(U, sit) {
    const c = D.cloth, wy = WAIST + U
    const hy = sit ? -8 : -122, hw = sit ? 272 : 236, n = sit ? 11 : 9
    let o = ''
    const pet = D.skirt === 'gothic' ? D.accent : D.lace
    o += part(bell(wy, hy + (sit ? 4 : 24), 62, hw + 8, n + 4, 16, sit), pet, folds(wy, hy + 24, hw, pet, 7))
    if (!sit) o += laceBand(hy + 34, hw - 2, 16, n + 9, D.lace, 6)
    o += part(bell(wy, hy, 66, hw, n, 24, sit), c, folds(wy, hy, hw, c))
    if (D.skirt === 'tiered') {        // 金卷：上面再罩一层短裙，白花边 + 三个红蝴蝶结
      const h2 = sit ? -120 : -248, w2 = sit ? 214 : 182
      o += part(bell(wy, h2, 66, w2, 7, 26, sit), c, folds(wy, h2, w2, c, 3))
      o += laceBand(h2 + 10, w2 - 10, 18, 16, D.lace, 4)
      for (const k of [-0.6, 0, 0.6]) o += bow(k * w2, h2 - 4, 0.44, D.accent)
      o += laceBand(hy + 6, hw - 18, 18, 18, D.lace, 6)
    } else if (D.skirt === 'gothic') { // 黑蔷薇：两道白蕾丝、一道红边
      o += laceBand(hy - 36, hw - 26, 13, 18, D.lace, 6)
      o += laceBand(hy - 76, hw - 52, 11, 16, D.accent, 6)
      o += laceBand(hy + 6, hw - 14, 15, 20, D.lace, 6)
    } else {                            // 紫藤：白围裙 + 两个紫蝴蝶结
      const ay = sit ? -66 : -186, aw = sit ? 156 : 126
      let a = `M-58 ${wy + 6} L58 ${wy + 6} Q${aw - 10} ${(wy + ay) / 2} ${aw} ${ay}`
      const k = aw * 2 / 8
      for (let i = 0; i < 8; i++) a += ` q${-k / 2} 22 ${-k} 0`
      a += ` Q${-aw + 10} ${(wy + ay) / 2} -58 ${wy + 6}Z`
      let pleats = ''
      for (let i = 1; i < 8; i++) pleats += `M${-aw + i * k} ${ay + 2} L${-aw + i * k} ${ay - 18}`
      o += part(a, D.lace, P(`M${aw} ${ay - 40} L${aw} ${ay + 30} L${-aw} ${ay + 30} L${-aw} ${ay - 40}Z`, flat(D.lace.shade)) + P(`M40 ${wy} Q${aw - 30} ${ay - 60} ${aw + 10} ${ay + 20} L${aw + 40} ${wy}Z`, flat(D.lace.shade)) + P(pleats, ink(D.lace.line, 2)))
      for (const yy of [0.32, 0.68]) o += bow(0, wy + (ay - wy) * yy, 0.38, D.accent)
      o += laceBand(hy + 6, hw - 18, 18, 18, D.lace, 6)
    }
    return o
  }
  function bodice(U) {
    const c = D.cloth, top = -462 + U, wy = WAIST + U + 6
    const body = `M-58 ${top} Q-90 ${top + 2} -92 ${top + 28} L-68 ${wy} L68 ${wy} L92 ${top + 28} Q90 ${top + 2} 58 ${top}Z`
    let inner = P(`M38 ${top} C66 ${top + 20} 70 ${wy - 30} 54 ${wy} L96 ${wy} L96 ${top}Z`, flat(c.shade))
    if (D.collar === 'high') {   // 黑蔷薇：胸前红色束腰，白色交叉系带
      inner += P(`M-30 ${top + 26} L30 ${top + 26} L24 ${wy} L-24 ${wy}Z`, flat(D.accent.base)) + P(`M10 ${top + 26} L30 ${top + 26} L24 ${wy} L8 ${wy}Z`, flat(D.accent.shade))
      for (let i = 0; i < 3; i++) {
        const y = top + 38 + i * ((wy - top - 46) / 3)
        inner += P(`M-17 ${y} L17 ${y + 16} M17 ${y} L-17 ${y + 16}`, ink(D.lace.base, 3.4))
      }
    }
    if (D.collar === 'jabot') inner += P(`M-28 ${top} L28 ${top} L20 ${wy} L-20 ${wy}Z`, flat(c.light))
    let o = part(body, c, inner)
    // 腰带
    const belt = D.collar === 'high' ? D.cloth : D.accent
    o += part(`M-68 ${wy - 14} Q0 ${wy - 8} 68 ${wy - 14} L68 ${wy + 6} Q0 ${wy + 12} -68 ${wy + 6}Z`, belt, P(`M-70 ${wy} L70 ${wy} L70 ${wy + 14} L-70 ${wy + 14}Z`, flat(belt.shade)), LW * 0.9)
    return o
  }
  function collar(U) {
    const y = -462 + U, L = D.lace
    let o = ''
    if (D.collar === 'round') {   // 金卷：圆圆的白蕾丝领子，红蝴蝶结配金扣
      for (const s of [-1, 1]) o += part(`M0 ${y - 4} C${s * 40} ${y - 8} ${s * 90} ${y - 2} ${s * 92} ${y + 22} C${s * 94} ${y + 48} ${s * 50} ${y + 54} ${s * 6} ${y + 38}Z`, L,
        E(s * 58, y + 40, 40, 13, flat(L.shade)) + P(`M${s * 8} ${y + 30} Q${s * 50} ${y + 46} ${s * 84} ${y + 26}`, ink(L.line, 2)))
      o += bow(0, y + 24, 0.72, D.accent) + part(ell(0, y + 24, 11, 11), D.metal, C(3, y + 28, 6, flat(D.metal.shade)) + C(-3, y + 20, 3, flat(D.metal.light)))
    } else if (D.collar === 'high') {   // 黑蔷薇：立起来的白蕾丝高领 + 红丝带颈圈和浮雕扣
      let z = `M-42 ${y - 30}`
      for (let i = 0; i < 7; i++) z += ` q6 -14 12 0`
      z += ` L40 ${y + 4} Q0 ${y + 10} -40 ${y + 4}Z`
      o += part(z, L, P(`M-44 ${y - 10} L44 ${y - 10} L44 ${y + 8} L-44 ${y + 8}Z`, flat(L.shade)))
      o += part(`M-38 ${y - 22} Q0 ${y - 16} 38 ${y - 22} L38 ${y - 8} Q0 ${y - 2} -38 ${y - 8}Z`, D.accent, '', LW * 0.8)
      o += part(ell(0, y - 14, 12, 15), D.metal, E(2, y - 11, 6, 8, flat(D.metal.shade)), LW * 0.8)
      for (const s of [-1, 1]) o += bow(s * 50, y + 58, 0.42, D.accent)
    } else {   // 紫藤：小白领 + 胸前一串褶皱花边 + 紫宝石胸针
      for (const s of [-1, 1]) o += part(`M0 ${y - 4} C${s * 30} ${y - 6} ${s * 70} ${y - 2} ${s * 72} ${y + 16} C${s * 70} ${y + 34} ${s * 34} ${y + 36} ${s * 4} ${y + 24}Z`, L, E(s * 44, y + 26, 30, 9, flat(L.shade)))
      for (let i = 2; i >= 0; i--) o += frill(0, y + 42 + i * 20, 28 - i * 2, 11, L, 5)
      o += gem(0, y + 22, 13, D.accent)
    }
    return o
  }
  function gem(x, y, r, m) {
    return part(ell(x, y, r + 5, r + 5), D.metal, '', LW * 0.8)
      + part(`M${x} ${y - r} L${x + r} ${y} L${x} ${y + r} L${x - r} ${y}Z`, m, P(`M${x} ${y} L${x + r} ${y} L${x} ${y + r} L${x - r} ${y}Z`, flat(m.shade)) + P(`M${x - r * 0.5} ${y - r * 0.15} L${x - r * 0.1} ${y - r * 0.55}`, ink('#ffffff', 2.6)), LW * 0.7)
  }
  function bow(x, y, k, m) {   // 蝴蝶结：两只圆耳朵 + 两条燕尾飘带 + 结
    const s = v => r1(v * k), w = Math.max(2.2, LW * Math.min(1, k + 0.35))
    let o = ''
    for (const side of [-1, 1]) {
      o += part(`M${x + side * s(4)} ${y + s(4)} Q${x + side * s(22)} ${y + s(40)} ${x + side * s(30)} ${y + s(78)} L${x + side * s(16)} ${y + s(66)} L${x + side * s(8)} ${y + s(80)} Q${x + side * s(4)} ${y + s(40)} ${x} ${y + s(8)}Z`, m,
        P(`M${x + side * s(14)} ${y + s(24)} L${x + side * s(40)} ${y + s(80)} L${x} ${y + s(90)}Z`, flat(m.shade)), w)
    }
    for (const side of [-1, 1]) {
      o += part(`M${x} ${y} C${x + side * s(26)} ${y - s(48)} ${x + side * s(84)} ${y - s(40)} ${x + side * s(78)} ${y + s(2)} C${x + side * s(80)} ${y + s(36)} ${x + side * s(30)} ${y + s(40)} ${x} ${y}Z`, m,
        P(`M${x} ${y + s(2)} C${x + side * s(30)} ${y + s(14)} ${x + side * s(66)} ${y + s(16)} ${x + side * s(84)} ${y + s(6)} L${x + side * s(84)} ${y + s(50)} L${x} ${y + s(50)}Z`, flat(m.shade))
        + P(`M${x + side * s(20)} ${y - s(16)} Q${x + side * s(46)} ${y - s(30)} ${x + side * s(62)} ${y - s(14)}`, ink(m.light || m.base, Math.max(2, s(6))))
        + P(`M${x + side * s(18)} ${y + s(4)} Q${x + side * s(40)} ${y} ${x + side * s(56)} ${y + s(14)}`, ink(m.line, Math.max(1.6, s(3)))), w)
    }
    return o + part(ell(x, y + s(1), s(15), s(16)), m, E(x + s(4), y + s(8), s(12), s(8), flat(m.shade)), w)
  }
  function flower(x, y, k) {
    let o = ''
    for (let i = 0; i < 8; i++) {
      const a = i / 8 * TAU + 0.2, px = x + Math.cos(a) * 15 * k, py = y + Math.sin(a) * 15 * k
      o += G(part(ell(px, py, 11 * k, 7 * k), FLOWER, '', 2.4), { transform: rot(deg(a), px, py) })
    }
    return o + part(ell(x, y, 8 * k, 8 * k), { base: FLOWER.light, line: FLOWER.line }, C(x + 2 * k, y + 2 * k, 4 * k, flat(FLOWER.shade)), 2.4)
  }

  // ---------------- 头 ----------------
  const FACE = 'M-172 -700 C-176 -604 -152 -530 -96 -496 C-58 -474 -24 -468 0 -468 C24 -468 58 -474 96 -496 C152 -530 176 -604 172 -700 C168 -800 -168 -800 -172 -700Z'
  function neck(U) {
    return part(`M-20 -500 L-20 ${-452 + U} L20 ${-452 + U} L20 -500Z`, D.skin, P(`M-30 -506 L30 -506 L30 -474 Q0 -460 -30 -474Z`, flat(D.skin.shade)))
  }
  function face(f) {
    const s = D.skin
    let inner = P('M-200 -820 L200 -820 L200 -704 Q130 -680 64 -694 Q0 -676 -64 -694 Q-130 -680 -200 -704Z', flat(s.shade))
      + P('M118 -700 C168 -640 160 -548 96 -500 L210 -500 L210 -700Z', flat(s.shade, 0.55))
    let o = part(FACE, s, inner)
    // 腮红：中间浓、四周淡
    if (f.blush > 0) {
      const id = 'b' + (uid++)
      defs.push(`<radialGradient id="${id}"><stop offset="0" stop-color="${D.blush}" stop-opacity="0.6"/><stop offset="1" stop-color="${D.blush}" stop-opacity="0"/></radialGradient>`)
      for (const x of [-1, 1]) {
        o += E(x * 104, -546, 44, 24, { fill: `url(#${id})`, opacity: clamp(f.blush, 0, 1) })
        if (f.blush > 0.75) for (let i = 0; i < 3; i++) o += P(`M${x * 104 + (i - 1) * 13 - 3} -540 l7 -11`, { ...ink(D.blush, 2.6), opacity: 0.85 })
      }
    }
    for (const x of [-1, 1]) o += eye(x * 72, -590, x, f)
    o += mouth(f) + P('M-2 -552 Q2 -549 5 -553', { ...ink(s.line, 3), opacity: 0.6 })
    if (f.puff) o += P('M146 -566 Q178 -552 164 -514', ink(s.line, LW))   // 鼓起的腮帮子
    if (f.tear) o += part('M-92 -566 q-9 15 0 22 q9 -7 0 -22Z', { base: '#c9ecff', line: '#6aa7d0' }, '', 2.4)
    return o
  }
  function eye(cx, cy, side, f) {
    const k = f.eyes, e = D.eye, L = e.line
    const gx = (f.gaze?.[0] || 0) * 8, gy = (f.gaze?.[1] || 0) * 7
    const thick = (w) => ({ fill: 'none', stroke: L, 'stroke-width': w, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' })
    if (k === 'closed' || k === 'sleep') {
      return P(`M${cx - side * 30} ${cy + 2} Q${cx} ${cy + 20} ${cx + side * 32} ${cy + 2}`, thick(6.5))
        + P(`M${cx + side * 30} ${cy + 3} l${side * 10} -5 M${cx + side * 22} ${cy + 10} l${side * 7} 7`, thick(4))
    }
    if (k === 'happy') return P(`M${cx - 30} ${cy + 14} Q${cx} ${cy - 24} ${cx + 30} ${cy + 14}`, thick(7.5)) + P(`M${cx + side * 28} ${cy + 10} l${side * 9} 4`, thick(4))
    if (k === 'tight') return P(`M${cx - side * 24} ${cy - 18} L${cx + side * 14} ${cy} L${cx - side * 24} ${cy + 18}`, thick(7.5))
    const wide = k === 'wide', rx = 35, ry = 46
    const lid = k === 'half' ? 0.42 : k === 'down' ? 0.34 : 0
    const top = cy - ry + lid * ry * 2
    const eyeD = ell(cx, cy, rx, ry)
    const gid = 'g' + (uid++)
    defs.push(`<linearGradient id="${gid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${e.dark}"/><stop offset="0.5" stop-color="${e.base}"/><stop offset="1" stop-color="${e.light}"/></linearGradient>`)
    const ix = cx + gx, iy = cy + gy + 5, irx = wide ? 20 : 30, iry = wide ? 27 : 40
    let inside = P(`M${cx - rx - 6} ${cy - ry - 6} L${cx + rx + 6} ${cy - ry - 6} L${cx + rx + 6} ${cy + ry + 6} L${cx - rx - 6} ${cy + ry + 6}Z`, flat('#ffffff'))
      + E(cx, cy - ry * 0.7, rx * 1.1, ry * 0.5, flat('#dfe4f4'))
      + E(ix, iy, irx, iry, { fill: `url(#${gid})`, stroke: e.dark, 'stroke-width': 2.5 })
      + E(ix, iy - iry * 0.5, irx * 1.02, iry * 0.48, flat(e.dark, 0.45))
      + E(ix, iy - 2, irx * 0.42, iry * 0.44, flat(e.dark))
      + P(`M${ix - irx * 0.78} ${iy + iry * 0.3} Q${ix} ${iy + iry * 1.08} ${ix + irx * 0.78} ${iy + iry * 0.3} Q${ix} ${iy + iry * 0.7} ${ix - irx * 0.78} ${iy + iry * 0.3}Z`, flat(e.light, 0.85))
      + E(ix - irx * 0.36, iy - iry * 0.36, wide ? 7 : 11, wide ? 9 : 14, flat('#ffffff'))
      + C(ix + irx * 0.4, iy + iry * 0.34, wide ? 3.5 : 5.5, flat('#ffffff'))
      + C(ix - irx * 0.5, iy + iry * 0.3, 2.6, flat('#ffffff', 0.9))
    if (k === 'sad') inside += E(ix, iy + iry * 0.55, irx * 0.8, 6, flat('#ffffff', 0.75))
    if (lid > 0) inside += P(`M${cx - rx - 6} ${cy - ry - 6} L${cx + rx + 6} ${cy - ry - 6} L${cx + rx + 6} ${top} L${cx - rx - 6} ${top}Z`, flat(D.skin.base))
    let o = clipTo(eyeD, inside)
    // 上睫毛：沿上边一道线，越往眼尾越粗，眼尾翘出去
    if (lid > 0) {
      o += P(`M${cx - rx - 2} ${top + 7} Q${cx} ${top - 5} ${cx + rx + 2} ${top + 7}`, thick(8))
      o += P(`M${cx + side * (rx + 1)} ${top + 7} l${side * 9} -7`, thick(5))
    } else {
      const a = [], b = []
      for (let i = 0; i <= 12; i++) {
        const s = i / 12, th = side > 0 ? lerp(Math.PI + 0.32, TAU - 0.04, s) : lerp(TAU - 0.32, Math.PI + 0.04, s)
        const w = 2 + 9 * Math.pow(Math.sin(Math.PI * Math.min(1, s * 1.15) / 2), 0.8) * (s > 0.92 ? (1 - s) / 0.08 * 0.6 + 0.4 : 1)
        a.push(onE(cx, cy, rx + 1 + w, ry + 1 + w * 1.05, th)); b.push(onE(cx, cy, rx - 1, ry - 1, th))
      }
      const end = a[a.length - 1]
      o += P(`M${pts(a)} L${end[0] + side * 14} ${end[1] - 9} L${pts(b.reverse())}Z`, { fill: L, stroke: L, 'stroke-width': 1.6, 'stroke-linejoin': 'round' })
      // 眼皮的褶
      const cr = []
      for (let i = 0; i <= 8; i++) { const s = 0.25 + 0.65 * i / 8, th = side > 0 ? lerp(Math.PI + 0.32, TAU - 0.04, s) : lerp(TAU - 0.32, Math.PI + 0.04, s); cr.push(onE(cx, cy - 6, rx + 12, ry + 12, th)) }
      o += P(`M${pts(cr)}`, { ...ink(D.skin.line, 2.4), opacity: 0.75 })
    }
    // 下睫毛：眼尾一小截
    const l0 = onE(cx, cy, rx, ry, side > 0 ? 0.45 : Math.PI - 0.45), l1 = onE(cx, cy, rx, ry, side > 0 ? 0.08 : Math.PI - 0.08)
    o += P(`M${l0[0]} ${l0[1] + 2} Q${(l0[0] + l1[0]) / 2 + side * 4} ${(l0[1] + l1[1]) / 2 + 6} ${l1[0] + side * 2} ${l1[1]}`, { ...thick(2.6), opacity: 0.8 })
    return o
  }
  function brows(f) {
    let o = ''
    for (const s of [-1, 1]) {
      const x = s * 70, y = -668
      let inY = 0, outY = 0, lift = 0
      if (f.brows === 'up') lift = -10
      if (f.brows === 'worried') { inY = -11; outY = 6 }
      if (f.brows === 'angry') { inY = 12; outY = -6 }
      if (f.brows === 'smug') { inY = s > 0 ? 4 : -2; outY = s > 0 ? -8 : 2 }
      const ix = x - s * 22, ox = x + s * 26, iy = y + inY + lift, oy = y + outY + lift + 3, my = y - 9 + lift + (inY + outY) / 2
      o += P(`M${ix} ${iy - 3} Q${x} ${my - 3} ${ox} ${oy} Q${x} ${my + 2} ${ix} ${iy + 3}Z`, { fill: D.hair.brow, stroke: D.hair.brow, 'stroke-width': 1.5, 'stroke-linejoin': 'round', opacity: 0.9 })
    }
    return o
  }
  function mouth(f) {
    const y = -520, m = f.mouth, line = D.skin.line
    const red = '#c2475a', tongue = '#ff94a0', ml = '#7e2235'
    const fillM = (d, t) => part(d, { base: red, line: ml }, t, 3)
    switch (m) {
      case 'open': return fillM(`M-17 ${y - 6} Q0 ${y - 1} 17 ${y - 6} Q14 ${y + 18} 0 ${y + 20} Q-14 ${y + 18} -17 ${y - 6}Z`, E(0, y + 16, 11, 7, flat(tongue)))
      case 'laugh': return fillM(`M-26 ${y - 10} Q0 ${y - 3} 26 ${y - 10} Q22 ${y + 24} 0 ${y + 28} Q-22 ${y + 24} -26 ${y - 10}Z`, E(0, y + 22, 15, 9, flat(tongue)) + P(`M-24 ${y - 9} Q0 ${y - 2} 24 ${y - 9} L24 ${y - 3} Q0 ${y + 4} -24 ${y - 3}Z`, flat('#ffffff')))
      case 'o': return fillM(ell(0, y + 2, 8, 10), E(0, y + 8, 5, 4, flat(tongue)))
      case 'O': return fillM(ell(0, y + 4, 14, 18), E(0, y + 14, 9, 6, flat(tongue)))
      case 'flat': return P(`M-10 ${y + 1} L10 ${y + 1}`, ink(line, 3.6))
      case 'wavy': return P(`M-20 ${y + 2} q5 -7 10 0 t10 0 t10 0 t10 0`, ink(line, 3.6))
      case 'pout': return P(`M-9 ${y + 5} Q0 ${y - 4} 9 ${y + 5}`, ink(line, 3.6))
      case 'cat': return P(`M-18 ${y - 3} Q-9 ${y + 9} 0 ${y - 1} Q9 ${y + 9} 18 ${y - 3}`, ink(line, 3.6))
      case 'smirk': return P(`M-12 ${y + 1} Q4 ${y + 9} 16 ${y - 5}`, ink(line, 3.6))
      case 'none': return ''
      default: return P(`M-11 ${y - 1} Q0 ${y + 9} 11 ${y - 1}`, ink(line, 3.8))   // smile
    }
  }

  // ---------------- 头发 ----------------
  // 一缕头发：发根中点 (x0, y0)、宽 w，发尖 (x1, y1)；bend 让这缕往一边弯
  function lock(x0, y0, w, x1, y1, bend) {
    const h = D.hair, my = lerp(y0, y1, 0.5)
    const edge = `M${x0 - w / 2} ${y0} C${x0 - w / 2 + bend * 0.5} ${my} ${x1 - w * 0.18 + bend * 0.5} ${lerp(y0, y1, 0.8)} ${x1} ${y1} C${x1 + w * 0.22 + bend * 0.6} ${lerp(y0, y1, 0.72)} ${x0 + w / 2 + bend * 0.5} ${my} ${x0 + w / 2} ${y0}`
    const sh = P(`M${x0 + w * 0.18} ${y0 - 20} Q${lerp(x0, x1, 0.55) + w * 0.2 + bend * 0.4} ${my} ${x1 + 2} ${y1 + 2} L${x0 + w} ${y1 + 10} L${x0 + w} ${y0 - 20}Z`, flat(h.shade))
      + P(`M${x0 - w * 0.12 + bend * 0.2} ${lerp(y0, y1, 0.35)} Q${lerp(x0, x1, 0.55) + bend * 0.3} ${lerp(y0, y1, 0.66)} ${lerp(x0, x1, 0.82)} ${lerp(y0, y1, 0.86)}`, ink(h.line, 1.8))
    // 发根那条边不描线：和头顶连成一片
    return P(edge + 'Z', flat(h.base)) + clipTo(edge + 'Z', sh) + P(edge, ink(h.line))
  }
  // 头顶：圆圆一顶，一圈「天使环」高光，几道发丝
  function cap() {
    const h = D.hair
    const d = 'M-206 -640 C-216 -780 -128 -902 0 -902 C128 -902 216 -780 206 -640 C150 -690 70 -712 0 -712 C-70 -712 -150 -690 -206 -640Z'
    let ring = ''
    {
      const a = [], b = []
      for (let i = 0; i <= 14; i++) {
        const th = lerp(Math.PI + 0.45, TAU - 0.45, i / 14)
        a.push(onE(0, -690, 168, 172, th))
        b.push(onE(0, -690, 160, 148 + (i % 2 ? 6 : -4), th))
      }
      ring = P(`M${pts(a)} L${pts(b.reverse())}Z`, flat(h.light))
    }
    const strands = P('M-60 -888 Q-130 -830 -160 -760 M70 -886 Q140 -830 166 -760', { ...ink(h.line, 1.8), opacity: 0.45 })
    return P(d, flat(h.base)) + clipTo(d, P('M130 -900 Q222 -800 222 -640 L240 -640 L240 -900Z', flat(h.shade, 0.7)) + ring + strands)
      + P('M-206 -640 C-216 -780 -128 -902 0 -902 C128 -902 216 -780 206 -640', ink(h.line))
  }
  function hairBack(sway, sit) {
    const h = D.hair, back = { base: h.back || h.shade, line: h.line }
    const sh = (d) => P(d, flat(h.deep))
    if (h.style === 'drills') {
      let o = part('M-206 -650 C-210 -590 -200 -548 -176 -520 L176 -520 C200 -548 210 -590 206 -650 C206 -800 112 -900 0 -900 C-112 -900 -206 -800 -206 -650Z', { base: h.shade, line: h.line })
      for (const s of [-1, 1]) o += drill(s, sway)
      return o
    }
    if (h.style === 'hime') {
      const b = sit ? -130 : -200
      // 长直发：发尾是几缕尖尖的，略往外散
      let d = `M-198 -700 C-212 -540 -222 -380 -224 ${b - 8}`
      const n = 8, w = 448 / n
      for (let i = 0; i < n; i++) d += ` Q${-224 + w * (i + 0.5)} ${b + 26} ${-224 + w * (i + 1)} ${b - 8 + (i % 2 ? 0 : 6)}`
      d += ` C222 -380 212 -540 198 -700 C204 -872 -204 -872 -198 -700Z`
      const lines = P(`M-196 -560 Q-208 -420 -210 ${b} M-160 -520 Q-170 -400 -168 ${b + 6} M196 -560 Q208 -420 210 ${b} M160 -520 Q170 -400 168 ${b + 6} M-120 -500 Q-126 -380 -112 ${b + 10} M120 -500 Q126 -380 112 ${b + 10}`, { ...ink(h.line, 2.2), opacity: 0.55 })
        + P(`M-206 -520 Q-214 -420 -214 -330 M206 -520 Q214 -420 214 -330`, { ...ink(h.light, 5), opacity: 0.5 })
      return G(part(d, { base: h.shade, line: h.line }, sh(`M-60 -700 Q-90 -400 -90 ${b + 30} L60 ${b + 30} Q90 -400 60 -700Z`) + lines), { transform: rot(sway * 0.5, 0, -640) })
    }
    // 紫藤：长卷发，发尾一个个圆卷
    const b = sit ? -150 : -256
    let d = `M-200 -690 C-224 -560 -236 -420 -232 ${b}`
    const n = 6, w = 464 / n
    for (let i = 0; i < n; i++) d += ` c${w * 0.05} ${36} ${w * 0.95} ${36} ${w} 0`
    d += ` C236 -420 224 -560 200 -690 C204 -880 -204 -880 -200 -690Z`
    let curls = ''
    for (let i = 0; i < n; i++) { const x = -232 + w * (i + 0.5); curls += `M${x - w * 0.3} ${b + 8} Q${x} ${b - 16} ${x + w * 0.28} ${b + 10}` }
    const lines = P(curls + ` M-200 -600 Q-226 -440 -210 ${b - 20} M200 -600 Q226 -440 210 ${b - 20} M-150 -540 Q-170 -400 -150 ${b - 10} M150 -540 Q170 -400 150 ${b - 10}`, { ...ink(h.line, 2.2), opacity: 0.55 })
    return G(part(d, { base: h.shade, line: h.line }, sh(`M-90 -660 Q-130 ${b - 60} -150 ${b + 40} L150 ${b + 40} Q130 ${b - 60} 90 -660Z`) + lines), { transform: rot(sway * 0.5, 0, -640) })
  }
  // 金卷的螺旋卷：从头两侧垂下来，一节一节，越往下越细，下面的节晃得多一点
  function drill(s, sway) {
    const h = D.hair, n = 6
    let o = ''
    const segs = []
    for (let i = 0; i < n; i++) {
      const k = i / (n - 1), w = 96 - 44 * k, hh = 56 - 12 * k
      const x = s * (194 + 24 * k) + sway * (1.5 + i * 2.4) * s * 0.4 + sway * i * 1.8, y = -694 + i * 64
      segs.push([x, y, w, hh])
    }
    o += part(`M${s * 146} -810 C${s * 210} -800 ${s * 242} -744 ${segs[0][0] + s * segs[0][2] * 0.5} ${segs[0][1]} L${segs[0][0] - s * segs[0][2] * 0.5} ${segs[0][1]} C${s * 168} -736 ${s * 150} -764 ${s * 136} -786Z`, h, P(`M${s * 150} -760 L${s * 260} -760 L${s * 260} -680 L${s * 150} -680Z`, flat(h.shade)))
    for (let i = n - 1; i >= 0; i--) {
      const [x, y, w, hh] = segs[i], a = -s * 18
      const sh = `M${x - w / 2} ${y} C${x - w / 2} ${y - hh * 1.1} ${x + w / 2} ${y - hh * 1.1} ${x + w / 2} ${y} C${x + w / 2} ${y + hh * 1.1} ${x - w / 2} ${y + hh * 1.1} ${x - w / 2} ${y}Z`
      o += G(part(sh, h, P(`M${x - w} ${y + 2} Q${x} ${y + hh * 0.5} ${x + w} ${y - 8} L${x + w} ${y + hh * 2} L${x - w} ${y + hh * 2}Z`, flat(h.shade))
        + P(`M${x - w} ${y + hh * 0.55} Q${x} ${y + hh * 0.9} ${x + w} ${y + hh * 0.3} L${x + w} ${y + hh * 2} L${x - w} ${y + hh * 2}Z`, flat(h.deep))
        + P(`M${x - w * 0.32} ${y - hh * 0.5} Q${x + w * 0.02} ${y - hh * 0.78} ${x + w * 0.34} ${y - hh * 0.42}`, ink(h.light, 7))
        + P(`M${x - w * 0.46} ${y + hh * 0.1} Q${x} ${y + hh * 0.42} ${x + w * 0.46} ${y - hh * 0.16}`, ink(h.line, 2))), { transform: rot(a, x, y) })
    }
    const [lx, ly, lw] = segs[n - 1]
    const tip = `M${lx - lw * 0.3} ${ly + 38} Q${lx + s * 4} ${ly + 74} ${lx + s * 26} ${ly + 56}`
    o += P(tip, ink(h.line, 11)) + P(tip, ink(h.base, 5.5))
    return o
  }
  function hairFront(f) {
    const h = D.hair
    let o = ''
    if (h.style === 'drills') {
      // 鬓角：S 形，发尖往里卷
      for (const s of [-1, 1]) o += lock(s * 180, -760, 50, s * 156, -520, s * 26)
      o += cap()
      for (const L of [[-150, -770, 84, -174, -612, -16], [150, -770, 84, 176, -614, 16], [-96, -796, 104, -114, -640, -14], [96, -796, 104, 118, -644, 14],
        [-36, -806, 100, -46, -650, -10], [40, -806, 100, 34, -654, 10], [2, -800, 62, -2, -672, 0]]) o += lock(...L)
      // 呆毛
      o += part('M6 -898 C2 -952 52 -968 62 -932 C46 -946 24 -936 22 -896Z', h)
    } else if (h.style === 'hime') {
      for (const s of [-1, 1]) o += part(`M${s * 206} -740 C${s * 214} -650 ${s * 214} -580 ${s * 208} -494 Q${s * 178} -486 ${s * 150} -498 C${s * 156} -580 ${s * 156} -650 ${s * 148} -720Z`, h,
        P(`M${s * 210} -700 L${s * 186} -700 Q${s * 184} -600 ${s * 186} -490 L${s * 212} -490Z`, flat(h.shade)) + P(`M${s * 176} -700 Q${s * 172} -600 ${s * 174} -500`, ink(h.line, 2)))
      o += cap()
      // 齐刘海：下边齐，几道发缝，两头微微往上收
      let d = 'M-196 -650 C-200 -760 -120 -840 0 -840 C120 -840 200 -760 196 -650 Q190 -676 178 -690'
      const xs = [178, 128, 76, 24, -28, -80, -130, -180]
      for (let i = 1; i < xs.length; i++) d += ` Q${(xs[i - 1] + xs[i]) / 2} ${-678} ${xs[i]} ${-690 + (i === xs.length - 1 ? 2 : (i % 2 ? 4 : 0))}`
      d += ' Q-190 -676 -196 -650Z'
      let cuts = ''
      for (let i = 1; i < xs.length - 1; i++) cuts += `M${xs[i]} -690 Q${xs[i] + 4} -730 ${xs[i] * 0.9} -780 `
      o += part(d, h, P('M-220 -800 Q0 -730 220 -800 L220 -840 L-220 -840Z', flat(h.shade)) + P(cuts, ink(h.line, 2.2)) + P('M-140 -778 Q-80 -800 -20 -804 M30 -804 Q90 -800 140 -778', { ...ink(h.light, 8), opacity: 0.8 }))
    } else {
      for (const s of [-1, 1]) o += lock(s * 182, -760, 50, s * 176, -478, s * 34)
      o += cap()
      // 中分偏左的刘海，往两边撇
      for (const L of [[-130, -782, 84, -172, -610, -24], [130, -778, 84, 176, -612, 20], [-74, -806, 100, -126, -640, -30], [66, -806, 104, 124, -642, 28],
        [12, -812, 104, 58, -652, 28], [-30, -812, 76, -52, -668, -16]]) o += lock(...L)
    }
    return o
  }
  function hairAcc(f, sway) {
    const h = D.hair
    let o = ''
    if (h.style === 'drills') {
      for (const s of [-1, 1]) o += G(bow(s * 168, -796, 1.0, D.accent), { transform: rot(s * 16 + sway * 0.5, s * 168, -796) })
      o += flower(146, -842, 1.0)
    } else if (h.style === 'hime') {
      // 歪戴的小礼帽：黑色、红丝带、一朵小橙花，后面一片黑纱
      const hx = 94, hy = -852, c = D.cloth
      o += G(
        P(`M${hx - 70} ${hy + 6} Q${hx - 40} ${hy + 72} ${hx + 20} ${hy + 66} Q${hx + 90} ${hy + 58} ${hx + 110} ${hy + 2}Z`, { fill: c.deep, opacity: 0.4, stroke: c.line, 'stroke-width': 2.4 })
        + part(`M${hx - 104} ${hy + 4} Q${hx} ${hy + 36} ${hx + 104} ${hy + 4} Q${hx} ${hy - 22} ${hx - 104} ${hy + 4}Z`, c, E(hx, hy + 14, 90, 10, flat(c.shade)))
        + part(`M${hx - 58} ${hy} L${hx - 52} ${hy - 104} Q${hx} ${hy - 118} ${hx + 52} ${hy - 104} L${hx + 58} ${hy} Q${hx} ${hy + 14} ${hx - 58} ${hy}Z`, c,
          P(`M${hx + 20} ${hy - 120} L${hx + 70} ${hy - 120} L${hx + 70} ${hy + 20} L${hx + 26} ${hy + 20}Z`, flat(c.shade)) + E(hx - 32, hy - 70, 8, 26, flat(c.light, 0.9)) + E(hx, hy - 106, 50, 9, flat(c.light, 0.6)))
        + part(`M${hx - 57} ${hy - 30} Q${hx} ${hy - 18} ${hx + 57} ${hy - 30} L${hx + 58} ${hy - 6} Q${hx} ${hy + 6} ${hx - 58} ${hy - 6}Z`, D.accent, P(`M${hx - 60} ${hy - 14} L${hx + 60} ${hy - 14} L${hx + 60} ${hy} L${hx - 60} ${hy}Z`, flat(D.accent.shade)), LW * 0.9)
        + flower(hx + 40, hy - 18, 1.0), { transform: rot(14, hx, hy) })
      o += bow(-150, -806, 0.56, D.accent)
    } else {
      // 编发发箍 + 小银冠 + 耳后小橙花
      const braid = { base: h.base, line: h.line, shade: h.shade }
      for (let i = 0; i <= 14; i++) {
        const a = Math.PI + 0.34 + (Math.PI - 0.68) * i / 14, [x, y] = onE(0, -692, 194, 180, a)
        o += G(part(ell(x, y, 19, 11), braid, E(x + 4, y + 5, 17, 6, flat(h.shade))), { transform: rot(deg(a) + 90 + (i % 2 ? 34 : -34), x, y) })
      }
      o += part('M-54 -844 L-40 -896 L-20 -862 L0 -912 L20 -862 L40 -896 L54 -844 Q0 -854 -54 -844Z', D.metal, P('M0 -912 L54 -844 L0 -854Z', flat(D.metal.shade)))
      o += gem(0, -868, 9, D.accent)
      o += flower(194, -706, 1.0)
    }
    return o
  }

  // ---------------- 道具 ----------------
  // 每个道具画在手的位置，angle 是朝向（度，0 朝右，向下为正）
  function prop(p, Hh) {
    const [x, y] = Hh, M = D.metal, c = D.cloth
    const T = inner => G(inner, { transform: `${tr(x, y)} rotate(${r1(p.angle || 0)})` })
    switch (p.kind) {
      case 'fan': {
        if (!p.open) return T(part('M-6 -10 L116 -16 Q124 0 116 16 L-6 10Z', M, P('M0 2 L120 2 L120 20 L0 20Z', flat(M.shade)) + P('M30 -12 L30 12 M60 -14 L60 14 M90 -15 L90 15', ink(M.line, 2))
          + P('M0 -6 L110 -10', ink(M.light, 3))) + P('M-8 0 Q-20 8 -18 24', ink(M.line, 2.6)) + part(ell(-18, 30, 4, 7), M, '', 2.2))
        const n = 9, R = 116, a0 = -150, a1 = -30, A = i => (a0 + (a1 - a0) * i / n) * Math.PI / 180
        let outer = 'M0 0'
        for (let i = 0; i <= n; i++) outer += ` L${r1(Math.cos(A(i)) * R)} ${r1(Math.sin(A(i)) * R)}`
        outer += 'Z'
        let pleats = '', ribs = '', lace = ''
        for (let i = 0; i < n; i++) {
          if (i % 2) pleats += P(`M0 0 L${Math.cos(A(i)) * R * 1.1} ${Math.sin(A(i)) * R * 1.1} L${Math.cos(A(i + 1)) * R * 1.1} ${Math.sin(A(i + 1)) * R * 1.1}Z`, flat(c.light))
          ribs += `M0 0 L${r1(Math.cos(A(i)) * R)} ${r1(Math.sin(A(i)) * R)} `
          lace += part(ell(Math.cos(A(i + 0.5)) * R, Math.sin(A(i + 0.5)) * R, 11, 11), D.lace, '', 2.2)
        }
        return T(lace + part(outer, c, pleats + P(ribs, ink(c.line, 1.6)) + P(`M0 0 L${Math.cos(A(0)) * 40} ${Math.sin(A(0)) * 40} A40 40 0 0 1 ${Math.cos(A(n)) * 40} ${Math.sin(A(n)) * 40}Z`, flat(D.accent.base)))
          + part(ell(0, 0, 9, 9), M, '', 2.4))
      }
      case 'parasol': {   // 收起的阳伞：上头弯柄在手里，伞尖朝下
        const L = p.len || 330
        return T(P(`M0 0 L0 ${L}`, ink(M.line, 11)) + P(`M0 0 L0 ${L}`, ink(M.shade, 5))
          + part(`M0 ${L * 0.24} C38 ${L * 0.42} 30 ${L * 0.7} 4 ${L * 0.92} L-4 ${L * 0.92} C-30 ${L * 0.7} -38 ${L * 0.42} 0 ${L * 0.24}Z`, c,
            P(`M4 ${L * 0.3} L34 ${L * 0.3} L34 ${L} L6 ${L}Z`, flat(c.shade)) + P(`M-16 ${L * 0.48} Q0 ${L * 0.53} 16 ${L * 0.48} M-12 ${L * 0.64} Q0 ${L * 0.68} 12 ${L * 0.64} M-7 ${L * 0.79} Q0 ${L * 0.82} 7 ${L * 0.79}`, ink(D.lace.base, 3.4))
            + P(`M-10 ${L * 0.34} Q-20 ${L * 0.5} -8 ${L * 0.8}`, ink(c.light, 4)))
          + bow(0, L * 0.28, 0.4, D.accent)
          + P('M0 4 Q0 -34 -26 -34 Q-46 -34 -44 -12', ink(M.line, 13)) + P('M0 4 Q0 -34 -26 -34 Q-46 -34 -44 -12', ink(M.base, 6.5)))
      }
      case 'teacup': {
        const W = { base: '#ffffff', shade: '#e9e4f0', line: D.lace.line }
        return T(part('M-50 6 Q0 26 50 6 Q50 -6 0 -6 Q-50 -6 -50 6Z', W, E(0, 10, 46, 8, flat(W.shade)), 2.8)
          + P('M30 -32 Q50 -32 45 -17 Q40 -6 26 -11', ink(W.line, 10)) + P('M30 -32 Q50 -32 45 -17 Q40 -6 26 -11', ink('#ffffff', 4.5))
          + part('M-31 -40 L31 -40 Q31 -2 0 0 Q-31 -2 -31 -40Z', W, P('M-31 -27 L31 -27 L31 -19 L-31 -19Z', flat(D.accent.base)) + P('M12 -44 L34 -44 L34 4 L10 4Z', flat(W.shade)) + P('M-31 -33 L31 -33', ink(M.base, 2.4)), 2.8)
          + part(ell(0, -40, 31, 8), { base: '#c9895a', line: W.line }, E(-4, -42, 16, 3.5, flat('#e6b07a')), 2.6))
      }
      case 'spoon': return T(P('M0 0 L-40 -70', ink(M.line, 9)) + P('M0 0 L-40 -70', ink(M.base, 4)) + G(part(ell(-44, -78, 7, 11), M, '', 2.6), { transform: rot(-30, -44, -78) }))
      case 'book': {
        const B = D.book, page = { base: '#fffaf2', shade: '#efe5d6', line: '#b9a98f' }
        if (!p.open) return T(part('M-46 -58 L46 -58 L46 58 L-46 58Z', B, P('M30 -60 L50 -60 L50 60 L30 60Z', flat(B.shade)) + P('M-46 40 L46 40', ink(B.line, 2.6))) + flower(-6, -6, 0.9))
        return T(part('M0 -30 L-96 -46 L-96 40 L0 56 L96 40 L96 -46Z', B, '', 3)
          + part('M0 -24 L-88 -40 L-88 32 L0 46Z', page, P('M-76 -22 L-14 -12 M-76 -6 L-14 4 M-76 10 L-14 20', ink('#d6cfc4', 2.4)), 2.6)
          + part('M0 -24 L88 -40 L88 32 L0 46Z', page, P('M14 -12 L76 -22 M14 4 L76 -6 M14 20 L76 10', ink('#d6cfc4', 2.4)) + P('M60 -50 L100 -50 L100 50 L60 50Z', flat(page.shade)), 2.6))
      }
      case 'quill': return T(part('M0 0 Q-20 -60 -6 -130 Q20 -70 6 0Z', D.lace, P('M0 -130 Q6 -60 3 0 L20 0 L20 -130Z', flat(D.lace.shade)), 2.6) + P('M2 0 L-2 -120', ink(D.lace.line, 2)) + P('M2 0 L6 22', ink(D.ink, 4)))
      case 'magnifier': return T(P('M0 0 L-46 -52', ink(D.ink, 15)) + P('M0 0 L-46 -52', ink('#8a5a3a', 8))
        + C(-74, -84, 40, { fill: '#d8f1ff', 'fill-opacity': 0.4, stroke: M.line, 'stroke-width': 15 }) + C(-74, -84, 40, { fill: 'none', stroke: M.base, 'stroke-width': 8 })
        + P('M-98 -100 Q-92 -114 -78 -116', ink('#ffffff', 5)))
      case 'bell': {
        return T(P('M0 0 L0 -40', ink(D.ink, 13)) + P('M0 0 L0 -40', ink('#8a5a3a', 7))
          + part('M-34 -40 Q-34 -96 0 -98 Q34 -96 34 -40 Q44 -36 40 -30 L-40 -30 Q-44 -36 -34 -40Z', M, P('M8 -100 L40 -100 L40 -30 L12 -30Z', flat(M.shade)) + E(-14, -74, 6, 13, flat(M.light, 0.9)))
          + part(ell(0, -24, 8, 8), { base: M.shade, line: M.line }, '', 2.6))
      }
    }
    return ''
  }

  // ---------------- 姿态 ----------------
  // hand：手的位置（站着时的身体坐标；坐下时整个上身一起往下挪）；prefer：手肘往外（默认）/ 往下 / 往里
  const HANDS = {
    down: [[-112, -322], [112, -322]],
    front: [[-20, -352], [20, -352]],
    chest: [[-15, -424], [15, -424]],
    hip: [[-90, -366], [90, -366]],
  }
  const sig = () => D.prop
  function signatureIdle(t) {   // 待机时手里拿着的招牌道具
    const p = sig()
    if (p === 'fan') return { L: { hand: [-16, -360] }, R: { hand: [22, -356] }, props: [{ kind: 'fan', hand: 'R', angle: -66 + wave(t, 1) * 2 }] }
    if (p === 'parasol') return { L: { hand: [-22, -356] }, R: { hand: [146, -340], prefer: 'down' }, props: [{ kind: 'parasol', hand: 'R', angle: 0, len: 340, z: 'mid' }] }
    return { L: { hand: [-30, -398] }, R: { hand: [30, -398] }, props: [{ kind: 'teacup', hand: 'C', dy: 4 }] }
  }
  const POSES = {
    idle(t) {
      const s = signatureIdle(t), blink = t > 0.7 && t < 0.745
      return { breath: -3 * (1 - Math.cos(TAU * t * 2)) / 2, sway: wave(t, 1) * 1.6, head: { rot: wave(t, 1) * 1.2 },
        face: { eyes: blink ? 'closed' : 'open', mouth: 'smile', brows: 'normal', blush: 0.65 }, ...s }
    },
    'idle-blink'(t) { const p = POSES.idle(0); p.face.eyes = 'closed'; return p },
    listening(t) {
      const s = signatureIdle(t)
      return { breath: -2 * bump(t, 0, 0.5), head: { rot: -5 + bump(t, 0.1, 0.5) * 3, dy: bump(t, 0.1, 0.5) * 4 }, sway: -2,
        face: { eyes: 'wide', mouth: 'o', brows: 'up', blush: 0.75, gaze: [-0.3, 0] }, L: { hand: [-146, -524] }, R: s.R, props: s.props.filter(p => p.hand === 'R'), overL: true }
    },
    thinking(t) {
      const p = sig(), tap = bump((t * 2) % 1, 0, 0.3)
      const props = p === 'fan' ? [{ kind: 'fan', hand: 'L', angle: 150, z: 'front' }] : []
      return { breath: -2 * (1 - Math.cos(TAU * t)) / 2, head: { rot: 5 + wave(t, 1) * 2 }, sway: 1.5 + wave(t, 1),
        face: { eyes: 'open', gaze: [0.7, -0.8], mouth: 'flat', brows: 'up', blush: 0.45 },
        L: { hand: [66, -378], prefer: 'down' }, R: { hand: [38, -490 - tap * 4], prefer: 'down' }, props, overR: true }
    },
    reading(t) {
      const gx = -0.8 + 1.6 * ((t * 2) % 1)
      return { breath: -2 * (1 - Math.cos(TAU * t)) / 2, head: { dy: 8, rot: 0 }, sway: wave(t, 1),
        face: { eyes: 'down', gaze: [gx * 0.6, 0.9], mouth: 'smile', brows: 'normal', blush: 0.55 },
        L: { hand: [-60, -396], prefer: 'down' }, R: { hand: [60, -396], prefer: 'down' }, props: [{ kind: 'book', hand: 'C', open: true, dy: -8, z: 'front' }] }
    },
    writing(t) {
      const a = TAU * t * 2, qx = Math.cos(a) * 10, qy = Math.sin(a) * 6
      return { breath: -1.5 * (1 - Math.cos(TAU * t)) / 2, head: { dy: 8, rot: 3 }, sway: 1,
        face: { eyes: 'down', gaze: [0.3, 0.9], mouth: 'smile', brows: 'normal', blush: 0.55 },
        L: { hand: [-58, -378], prefer: 'down' }, R: { hand: [32 + qx, -392 + qy], prefer: 'down' },
        props: [{ kind: 'book', hand: 'L', open: true, dx: 58, dy: -12, angle: -8, z: 'mid' }, { kind: 'quill', hand: 'R', angle: 20 }] }
    },
    running(t) {
      const p = sig(), k = bump((t * 2) % 1, 0, 0.5)
      if (p === 'teacup') {   // 紫藤：搅红茶
        const a = TAU * t * 2
        return { breath: -2 * k, head: { rot: -2, dy: 4 }, face: { eyes: 'down', gaze: [0.2, 0.7], mouth: 'smile', brows: 'normal', blush: 0.55 },
          L: { hand: [-26, -386] }, R: { hand: [40 + Math.cos(a) * 10, -444 + Math.sin(a) * 4] }, props: [{ kind: 'teacup', hand: 'L', dx: 34, dy: 0 }, { kind: 'spoon', hand: 'R', angle: -10 }] }
      }
      return { breath: -3 * k, lift: -4 * k, head: { rot: -4 }, sway: -2 * k,
        face: { eyes: 'half', gaze: [0.6, 0], mouth: 'open', brows: 'smug', blush: 0.55 },
        L: { hand: HANDS.hip[0] }, R: { hand: [200 + 8 * k, -480 - 4 * k] },
        props: p === 'fan' ? [{ kind: 'fan', hand: 'R', angle: -18 }] : [{ kind: 'parasol', hand: 'R', angle: -98, len: 300 }] }
    },
    asking(t) {
      return { breath: -2 * (1 - Math.cos(TAU * t)) / 2, lift: -6 * bump(t, 0, 0.35), head: { rot: 7 + wave(t, 1) * 2 }, sway: wave(t, 1) * 2,
        face: { eyes: 'open', gaze: [0, -0.4], mouth: 'o', brows: 'worried', blush: 0.95 }, L: { hand: HANDS.chest[0] }, R: { hand: HANDS.chest[1] } }
    },
    happy(t) {
      const k = bump(t, 0, 0.28) + bump(t, 0.3, 0.56) * 0.7
      return { lift: -34 * k, breath: -3 * k, head: { rot: wave(t, 2) * 3 * (1 - t) }, sway: k * 2,
        face: { eyes: 'happy', mouth: 'open', brows: 'up', blush: 1 }, L: { hand: [-14, -436 - 10 * k] }, R: { hand: [14, -436 - 10 * k] } }
    },
    proud(t) {   // 「哦～呵呵呵」：一手叉腰、一手（或扇子）挡在嘴边
      const k = Math.abs(wave(t, 3)) * (t < 0.85 ? 1 : 0), fan = sig() === 'fan'
      return { breath: -4 * k, head: { rot: -6 - 2 * k, dy: -4 * k }, sway: -3 - 2 * k,
        face: { eyes: 'closed', mouth: 'laugh', brows: 'smug', blush: 0.85 },
        L: { hand: HANDS.hip[0] }, R: { hand: fan ? [92, -522] : [68, -516] },
        props: fan ? [{ kind: 'fan', hand: 'R', open: true, angle: -28, z: 'over', dx: -4, dy: -8 }] : [], overR: !fan }
    },
    oops(t) {
      const k = t < 0.5 ? wave(t, 4) * (1 - t * 2) : 0
      return { breath: -2, head: { rot: 6 * k, dx: 4 * k }, sway: 3 * k,
        face: { eyes: 'tight', mouth: 'wavy', brows: 'worried', blush: 0.95 }, L: { hand: [-42, -498] }, R: { hand: [42, -498] }, overL: true, overR: true }
    },
    sorry(t) {
      return { breath: -1.5 * (1 - Math.cos(TAU * t)) / 2, head: { dy: 14 + 3 * bump(t, 0.2, 0.7), rot: -3 }, sway: 0,
        face: { eyes: 'sad', gaze: [-0.2, 0.8], mouth: 'wavy', brows: 'worried', blush: 0.65, tear: true }, L: { hand: HANDS.front[0] }, R: { hand: HANDS.front[1] } }
    },
    surprised(t) {
      const k = bump(t, 0, 0.45)
      return { lift: -50 * k, breath: -3, head: { rot: 0, dy: -4 * k }, sway: -3 * k,
        face: { eyes: 'wide', mouth: 'O', brows: 'up', blush: 0.6 }, L: { hand: [-160, -504 - 20 * k] }, R: { hand: [160, -504 - 20 * k] } }
    },
    pat(t) {
      return { breath: -2, head: { rot: wave(t, 2) * 5 }, sway: wave(t, 2) * 3,
        face: { eyes: 'happy', mouth: 'cat', brows: 'up', blush: 1 }, L: { hand: [-146, -550] }, R: { hand: [146, -550] }, overL: true, overR: true }
    },
    searching(t) {
      const a = TAU * t
      return { breath: -2 * (1 - Math.cos(a)) / 2, head: { rot: 3 + Math.sin(a) * 2 }, sway: Math.sin(a),
        face: { eyes: 'open', gaze: [0.4 + Math.sin(a) * 0.4, Math.cos(a) * 0.4], mouth: 'o', brows: 'up', blush: 0.55 },
        L: { hand: HANDS.hip[0] }, R: { hand: [142 + Math.sin(a) * 10, -502 + Math.cos(a) * 8] }, props: [{ kind: 'magnifier', hand: 'R', angle: 0, z: 'over' }] }
    },
    delegating(t) {
      const ring = wave(t, 4) * 16
      return { breath: -2 * Math.abs(wave(t, 2)), head: { rot: -4 }, sway: -2,
        face: { eyes: 'closed', mouth: 'open', brows: 'smug', blush: 0.65 }, L: { hand: HANDS.hip[0] }, R: { hand: [150, -558] },
        props: [{ kind: 'bell', hand: 'R', angle: ring, z: 'over' }], overR: true }
    },
    sleeping(t) {
      return { sit: true, breath: -3 * (1 - Math.cos(TAU * t)) / 2, head: { rot: 12 + wave(t, 1) * 1.5, dy: 6 }, sway: 3,
        face: { eyes: 'sleep', mouth: 'o', brows: 'normal', blush: 0.75 }, L: { hand: [-32, -304], prefer: 'down' }, R: { hand: [32, -304], prefer: 'down' } }
    },
    tired(t) {
      return { sit: true, breath: -2 * (1 - Math.cos(TAU * t)) / 2, head: { rot: -6, dy: 8 + bump(t, 0.3, 0.8) * 4 }, sway: -2,
        face: { eyes: 'half', gaze: [0, 0.6], mouth: 'wavy', brows: 'worried', blush: 0.45 }, L: { hand: [-38, -304], prefer: 'down' }, R: { hand: [38, -304], prefer: 'down' } }
    },
    bye(t) {
      const w = wave(t, 2.5) * 22
      return { breath: -2, head: { rot: -4 }, sway: -2, face: { eyes: 'happy', mouth: 'open', brows: 'up', blush: 0.85 },
        L: { hand: HANDS.front[0] }, R: { hand: [140 + w * 0.4, -566 + Math.abs(w) * 0.2] }, overR: true }
    },
    busy_left(t) { const p = POSES.idle(t); p.face.gaze = [-1, 0]; p.head = { rot: -4, dx: -6 }; p.face.mouth = 'flat'; return p },
    busy_right(t) { const p = POSES.idle(t); p.face.gaze = [1, 0]; p.head = { rot: 4, dx: 6 }; p.face.mouth = 'flat'; return p },
    pout(t) {   // 「哼」：抱着胳膊，头扭向一边
      const k = bump(t, 0, 0.3)
      return { breath: -2, head: { rot: 8 + 4 * k, dx: 6 }, sway: 3,
        face: { eyes: 'closed', mouth: 'pout', brows: 'angry', blush: 1, puff: true }, L: { hand: [62, -410], prefer: 'down' }, R: { hand: [-58, -404], prefer: 'down' } }
    },
    hum(t) {
      const p = sig(), k = wave(t, 3)
      if (p === 'fan') return { breath: -2, head: { rot: -3 + k }, sway: k * 2, face: { eyes: 'closed', mouth: 'smile', brows: 'normal', blush: 0.75 },
        L: { hand: HANDS.front[0] }, R: { hand: [124, -508] }, props: [{ kind: 'fan', hand: 'R', open: true, angle: -64 + k * 14, z: 'over' }], overR: true }
      return { breath: -2, head: { rot: 2, dy: 4 }, sway: 0, face: { eyes: 'closed', mouth: 'none', brows: 'normal', blush: 0.75 },
        L: { hand: [-30, -444] }, R: { hand: [30, -482 - 6 * bump(t, 0.2, 0.8)] }, props: [{ kind: 'teacup', hand: 'R', dx: -26, dy: -2, z: 'over' }], overR: true, overL: true }
    },
  }

  // ---------------- 拼起来 ----------------
  function svg(id, poseName, t, view) {
    D = DESIGNS[id]; defs = []; uid = 0
    const pose = POSES[poseName](t)
    const U = (pose.breath || 0) + (pose.sit ? 103 : 0), sit = !!pose.sit
    const hd = pose.head || {}, sway = pose.sway || 0
    const headT = `${tr(hd.dx || 0, (hd.dy || 0) + U)} ${rot(hd.rot || 0, 0, -480)}`
    const arms = {}
    for (const [k, side] of [['L', -1], ['R', 1]]) arms[k] = arm(pose[k] || { hand: HANDS.down[side < 0 ? 0 : 1] }, side, U)
    const props = (pose.props || []).map(p => {
      const H = p.hand === 'C' ? [(arms.L.H[0] + arms.R.H[0]) / 2, (arms.L.H[1] + arms.R.H[1]) / 2] : arms[p.hand].H
      return { z: p.z || 'front', s: prop(p, [H[0] + (p.dx || 0), H[1] + (p.dy || 0)]) }
    })
    const z = k => props.filter(p => p.z === k).map(p => p.s).join('')
    const hang = D.hair.style === 'drills' ? 0.7 : 0.3   // 长发往下垂：头歪的时候它少歪一点
    let body = G(hairBack(sway, sit), { transform: `${tr(hd.dx || 0, (hd.dy || 0) + U)} ${rot((hd.rot || 0) * hang, 0, -480)}` })
    body += z('back')
    if (!sit) body += legs()
    body += skirt(U, sit) + bodice(U) + collar(U) + neck(U)
    body += z('mid')
    if (!pose.overL) body += arms.L.out
    if (!pose.overR) body += arms.R.out
    body += z('front')
    body += G(face(pose.face) + hairFront(pose.face) + brows(pose.face) + hairAcc(pose.face, sway), { transform: headT })
    if (pose.overL) body += arms.L.out
    if (pose.overR) body += arms.R.out
    body += z('over')
    // 外轮廓：把整个人物的剪影往外膨胀一圈，涂成深色垫在下面
    defs.push(`<filter id="ol" x="-20%" y="-20%" width="140%" height="140%" color-interpolation-filters="sRGB"><feMorphology in="SourceAlpha" operator="dilate" radius="4.5" result="d"/><feFlood flood-color="${D.ink}"/><feComposite in2="d" operator="in" result="o"/><feMerge><feMergeNode in="o"/><feMergeNode in="SourceGraphic"/></feMerge></filter>`)
    const all = G(G(body, { filter: 'url(#ol)' }), { transform: `translate(${r1(view.tx)} ${r1(view.ty + (pose.lift || 0) * view.s)}) scale(${view.s})` })
    return `<svg xmlns="http://www.w3.org/2000/svg" width="${view.w}" height="${view.h}" viewBox="0 0 ${view.w} ${view.h}"><defs>${defs.join('')}</defs>${all}</svg>`
  }

  // 每位大小姐要出的图：所有姿态的立绘 + 这些姿态的动画（帧数 = 秒数 × 12）
  const STILLS = ['idle', 'idle-blink', 'listening', 'thinking', 'reading', 'writing', 'running', 'asking', 'happy', 'proud', 'oops', 'sorry',
    'surprised', 'pat', 'searching', 'delegating', 'sleeping', 'tired', 'bye', 'busy_left', 'busy_right', 'pout', 'hum']
  const SHEETS = { idle: 48, listening: 24, thinking: 48, reading: 48, writing: 24, running: 24, asking: 24, happy: 30, proud: 36, oops: 24,
    sorry: 36, surprised: 18, pat: 30, searching: 36, delegating: 24, sleeping: 48, tired: 36, bye: 30, pout: 24, hum: 36 }
  function jobs(id) {
    return [...STILLS.map(p => ({ kind: 'still', name: p, pose: p })),
      ...Object.entries(SHEETS).map(([p, n]) => ({ kind: 'sheet', name: p, pose: p, frames: n }))]
  }
  return { svg, jobs, designs: Object.keys(DESIGNS), sheets: SHEETS }
})()
