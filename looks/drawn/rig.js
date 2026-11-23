// 用代码画的形象：三位大小姐（金卷 / 黑蔷薇 / 紫藤），本项目原创。scripts/draw-look.swift 把它渲染成立绘和精灵图。
// 人物坐标：脚底中点是原点，y 向下，人物高约 1000（头顶到脚底），Q 版两头身半：大头、短身子、蓬蓬裙。
// 画法：每个部件是一段 SVG（填色 + 深色描边，两色平涂阴影），姿态只写「手放哪、脸什么表情、拿什么」，手肘用两节骨骼反解。
// 动画：姿态是 t（0～1）的函数，循环的动画首尾接得上；精灵图每帧 t = i / 帧数。
const RIG = (() => {
  const TAU = Math.PI * 2
  const r1 = n => Math.round(n * 10) / 10
  const wave = (t, n = 1, ph = 0) => Math.sin(TAU * (t * n + ph))
  const bump = (t, a, b) => (t <= a || t >= b) ? 0 : Math.sin(Math.PI * (t - a) / (b - a))
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v))
  const deg = r => r * 180 / Math.PI

  // ---------------- 三位大小姐 ----------------
  const DESIGNS = {
    'ojou-gold': {
      line: '#6a3a40', skin: ['#ffeadf', '#f7c9b8'], blush: '#ff8fa3',
      hair: { style: 'drills', base: '#ffd977', shade: '#e9ad45', light: '#fff4c4', back: '#f0bb52', brow: '#b07a2c' },
      eye: ['#1f4fa8', '#3f86e8', '#9fd2ff'],
      dress: { base: '#f7a7bf', shade: '#e47b9c', light: '#ffd0dd', lace: '#fffafb', laceShade: '#f2d3dc', accent: '#d8304f', accentShade: '#a81d3a', metal: '#f4c44f', metalShade: '#c98d1e' },
      skirt: 'tiered', collar: 'round', legs: { sock: '#ffffff', sockShade: '#eadde2', shoe: '#cf3654', shoeShade: '#9c1f3a' },
      book: ['#c8344f', '#8f1d33'], prop: 'fan', bell: ['#f4c44f', '#c98d1e'],
    },
    'ojou-noir': {
      line: '#211a26', skin: ['#fff0ea', '#f0cfc6'], blush: '#ff8f9f',
      hair: { style: 'hime', base: '#3e3658', shade: '#28223c', light: '#9488c4', back: '#2f2945', brow: '#2b2540' },
      eye: ['#7a0f22', '#d42a45', '#ff9aa5'],
      dress: { base: '#302c33', shade: '#1d1a20', light: '#605a66', lace: '#fbf6f8', laceShade: '#dcd2d8', accent: '#c02442', accentShade: '#87142c', metal: '#e8e2ea', metalShade: '#a79eb0' },
      skirt: 'gothic', collar: 'high', legs: { sock: '#2e2836', sockShade: '#1f1a25', shoe: '#1d1822', shoeShade: '#0f0c12', bow: '#c02442' },
      book: ['#2a2430', '#16121a'], prop: 'parasol', bell: ['#e8e2ea', '#a79eb0'],
    },
    'ojou-lilac': {
      line: '#4e4266', skin: ['#ffeee6', '#f5cfc2'], blush: '#ff9ab8',
      hair: { style: 'wavy', base: '#eeeaf8', shade: '#c4bbe0', light: '#ffffff', back: '#d3cbec', brow: '#9c90c0' },
      eye: ['#0f6f73', '#2bb3a8', '#a6f0e0'],
      dress: { base: '#c9b5ee', shade: '#a28bd8', light: '#e6dbff', lace: '#ffffff', laceShade: '#e4def2', accent: '#8a5fd0', accentShade: '#6440a8', metal: '#dfe6f2', metalShade: '#9ea9c2' },
      skirt: 'apron', collar: 'jabot', legs: { sock: '#ffffff', sockShade: '#e5e0f0', shoe: '#9a7fd6', shoeShade: '#6f55ae' },
      book: ['#8a6cc8', '#5f479a'], prop: 'teacup', bell: ['#dfe6f2', '#9ea9c2'],
    },
  }
  const FLOWER = ['#f08a4b', '#c9612a', '#ffd9a0']   // 小橙花：claudia 的标志，三位都别着一朵

  // ---------------- SVG 小工具 ----------------
  let D, defs, uid, LW
  const at = o => Object.entries(o).filter(([, v]) => v !== undefined && v !== null && v !== false)
    .map(([k, v]) => `${k}="${typeof v === 'number' ? r1(v) : v}"`).join(' ')
  const P = (d, o = {}) => `<path d="${d}" ${at(o)}/>`
  const E = (cx, cy, rx, ry, o = {}) => `<ellipse cx="${r1(cx)}" cy="${r1(cy)}" rx="${r1(rx)}" ry="${r1(ry)}" ${at(o)}/>`
  const C = (cx, cy, r, o = {}) => `<circle cx="${r1(cx)}" cy="${r1(cy)}" r="${r1(r)}" ${at(o)}/>`
  const G = (inner, o = {}) => `<g ${at(o)}>${inner}</g>`
  const fill = (c, w = LW) => ({ fill: c, stroke: D.line, 'stroke-width': w, 'stroke-linejoin': 'round', 'stroke-linecap': 'round' })
  const ink = (w = LW, c = D.line) => ({ fill: 'none', stroke: c, 'stroke-width': w, 'stroke-linejoin': 'round', 'stroke-linecap': 'round' })
  const flat = c => ({ fill: c })
  const rot = (a, x, y) => `rotate(${r1(a)} ${r1(x)} ${r1(y)})`
  const tr = (x, y) => `translate(${r1(x)} ${r1(y)})`
  // 填色 + 里面的阴影（剪在形状里）+ 描边
  function part(d, base, inner = '', w = LW) {
    const id = 'c' + (uid++)
    defs.push(`<clipPath id="${id}"><path d="${d}"/></clipPath>`)
    return P(d, flat(base)) + (inner ? G(inner, { 'clip-path': `url(#${id})` }) : '') + P(d, ink(w))
  }
  const pts = a => a.map(p => `${r1(p[0])} ${r1(p[1])}`).join(' ')
  // 椭圆上的点（角度：0 在右，向下为正）
  const onE = (cx, cy, rx, ry, a) => [cx + rx * Math.cos(a), cy + ry * Math.sin(a)]

  // ---------------- 身体 ----------------
  const SH = 88, SHY = -440           // 肩膀
  const UP = 70, FORE = 76            // 上臂、前臂
  function ik(S, H, side, prefer) {
    const dx = H[0] - S[0], dy = H[1] - S[1], d0 = Math.hypot(dx, dy) || 1
    const d = clamp(d0, Math.abs(UP - FORE) + 1, UP + FORE - 1), ux = dx / d0, uy = dy / d0
    const A = Math.acos(clamp((UP * UP + d * d - FORE * FORE) / (2 * UP * d), -1, 1)), base = Math.atan2(uy, ux)
    const cands = [base + A, base - A].map(a => [S[0] + UP * Math.cos(a), S[1] + UP * Math.sin(a)])
    const score = e => prefer === 'down' ? e[1] : prefer === 'in' ? -side * e[0] : side * e[0] + e[1] * 0.25
    const e = score(cands[0]) >= score(cands[1]) ? cands[0] : cands[1]
    return { E: e, H: [S[0] + ux * d, S[1] + uy * d] }
  }
  function armParts(a, side, U) {
    const S = [side * SH, SHY + U], { E: El, H } = ik(S, [a.hand[0], a.hand[1] + U], side, a.prefer)
    const fx = H[0] - El[0], fy = H[1] - El[1], fl = Math.hypot(fx, fy) || 1
    const W = [H[0] - fx / fl * 20, H[1] - fy / fl * 20]
    const s = D.sleeve || D.dress
    const tube = `M${pts([S, El, W])}`
    let out = P(tube, { fill: 'none', stroke: D.line, 'stroke-width': 44 + LW * 2, 'stroke-linejoin': 'round', 'stroke-linecap': 'round' })
      + P(tube, { fill: 'none', stroke: s.base, 'stroke-width': 44, 'stroke-linejoin': 'round', 'stroke-linecap': 'round' })
      + P(`M${pts([[S[0] + side * 6, S[1] + 6], [El[0] + side * 8, El[1]], [W[0] + side * 6, W[1]]])}`,
        { fill: 'none', stroke: s.shade, 'stroke-width': 14, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', opacity: 0.7 })
    // 泡泡袖
    const pa = deg(Math.atan2(El[1] - S[1], El[0] - S[0]))
    const pc = [S[0] + (El[0] - S[0]) * 0.28, S[1] + (El[1] - S[1]) * 0.28]
    out += G(part(`M${pc[0] - 44} ${pc[1]} a44 38 0 1 0 88 0 a44 38 0 1 0 -88 0Z`, s.base,
      E(pc[0] + 10, pc[1] + 22, 44, 22, flat(s.shade)) + E(pc[0] - 14, pc[1] - 16, 16, 9, flat(s.light || D.dress.light))), { transform: rot(pa, pc[0], pc[1]) })
    const ta = deg(Math.atan2(El[1] - S[1], El[0] - S[0])) + 90, tp = [S[0] + (El[0] - S[0]) * 0.62, S[1] + (El[1] - S[1]) * 0.62]
    out += G(frill(tp[0], tp[1], 30, 10, D.dress.lace, D.dress.laceShade), { transform: rot(ta, tp[0], tp[1]) })
    // 袖口花边
    const ca = deg(Math.atan2(fy, fx)) + 90
    out += G(frill(W[0], W[1], 27, 13, D.dress.lace, D.dress.laceShade), { transform: rot(ca, W[0], W[1]) })
    out += hand(H[0], H[1])
    return { out, H, El }
  }
  function frill(cx, cy, rx, ry, c, sh) {
    let d = `M${cx - rx} ${cy}`
    const n = 5, w = rx * 2 / n
    for (let i = 0; i < n; i++) d += ` q${w / 2} ${ry * 1.5} ${w} 0`
    d += ` C${cx + rx} ${cy - ry * 1.6} ${cx - rx} ${cy - ry * 1.6} ${cx - rx} ${cy}Z`
    return part(d, c, E(cx, cy + ry * 0.6, rx, ry * 0.5, flat(sh)))
  }
  function hand(x, y) {
    return part(`M${x - 23} ${y} a23 22 0 1 0 46 0 a23 22 0 1 0 -46 0Z`, D.skin[0], E(x + 6, y + 9, 20, 12, flat(D.skin[1])))
  }

  function legs(lift) {
    const L = D.legs
    let o = ''
    for (const s of [-1, 1]) {
      const x = s * 40
      o += part(`M${x - 18} -150 L${x - 17} -34 L${x + 17} -34 L${x + 18} -150Z`, L.sock, P(`M${x + s * 4} -150 L${x + s * 6} -34 L${x + s * 18} -34 L${x + s * 18} -150Z`, flat(L.sockShade)))
      const sx = x + s * 5
      o += part(`M${sx - 36} -1 C${sx - 44} -30 ${sx - 22} -46 ${sx + 2} -46 C${sx + 28} -46 ${sx + 46} -30 ${sx + 38} -1Z`, L.shoe,
        P(`M${sx - 40} -10 L${sx + 44} -10 L${sx + 44} 4 L${sx - 40} 4Z`, flat(L.shoeShade)) + E(sx - 12, -32, 12, 6, { fill: '#ffffff', opacity: 0.45 }))
      o += P(`M${x - 17} -40 L${x + 17} -40`, ink(8, L.shoeShade)) + P(`M${x - 17} -40 L${x + 17} -40`, ink(4, L.shoe))
      if (L.bow) o += bow(sx, -40, 0.32, L.bow, D.dress.accentShade)
    }
    return o
  }

  // 裙子：腰在 wy，下摆在 hy，下摆半宽 hw；n 个花边弧
  function bell(wy, hy, ww, hw, n, drop = 22, dome = false) {
    const a = dome ? [-ww - 150, wy + 6, -hw - 14, hy - 120] : [-ww - 20, wy + 50, -hw + 6, hy - 90]
    let d = `M${-ww} ${wy} C${a[0]} ${a[1]} ${a[2]} ${a[3]} ${-hw} ${hy}`
    const w = hw * 2 / n
    for (let i = 0; i < n; i++) d += ` q${w / 2} ${drop} ${w} 0`
    d += ` C${-a[2]} ${a[3]} ${-a[0]} ${a[1]} ${ww} ${wy}Z`
    return d
  }
  function folds(wy, hy, hw, c, n = 4) {
    let o = ''
    for (let i = 0; i < n; i++) {
      const k = (i + 0.5) / n * 2 - 1, x = k * hw * 0.78
      o += P(`M${k * 30} ${wy + 30} Q${x * 0.8} ${(wy + hy) / 2} ${x - 16} ${hy + 30} L${x + 14} ${hy + 30} Q${x * 0.8 + 10} ${(wy + hy) / 2} ${k * 30 + 4} ${wy + 30}Z`, flat(c))
    }
    return o + P(`M${-hw - 40} ${hy + 40} L${-hw - 40} ${wy} L${-hw * 0.62} ${wy} Q${-hw * 0.8} ${hy - 60} ${-hw * 0.78} ${hy + 40}Z`, flat(c))
      + P(`M${hw + 40} ${hy + 40} L${hw + 40} ${wy} L${hw * 0.62} ${wy} Q${hw * 0.8} ${hy - 60} ${hw * 0.78} ${hy + 40}Z`, flat(c))
  }
  function laceBand(y, hw, h, n, c, sh) {   // 一条花边：上边直、下边一串小弧
    let d = `M${-hw} ${y - h}`
    d += ` L${hw} ${y - h} L${hw} ${y}`
    const w = hw * 2 / n
    for (let i = 0; i < n; i++) d += ` q${-w / 2} ${h * 0.9} ${-w} 0`
    return part(d + 'Z', c, P(`M${-hw} ${y - h * 0.35} L${hw} ${y - h * 0.35} L${hw} ${y + h} L${-hw} ${y + h}Z`, flat(sh)), LW * 0.8)
  }
  function skirt(U, sit) {
    const d = D.dress, wy = -335 + U
    const hy = sit ? -8 : -122, hw = sit ? 268 : 232, n = sit ? 10 : 8
    let o = ''
    // 衬裙花边
    o += part(bell(wy, hy + (sit ? 4 : 22), 60, hw + 10, n + 3, 18, sit), D.skirt === 'gothic' ? d.accent : d.lace,
      folds(wy, hy + 22, hw, D.skirt === 'gothic' ? d.accentShade : d.laceShade, 6))
    if (D.skirt === 'gothic') o += laceBand(hy + (sit ? 6 : 28), hw - 4, 14, n + 6, d.lace, d.laceShade)
    o += part(bell(wy, hy, 62, hw, n, 22, sit), d.base, folds(wy, hy, hw, d.shade))
    if (D.skirt === 'tiered') {
      const h2 = sit ? -130 : -238, w2 = sit ? 205 : 172
      o += part(bell(wy, h2, 62, w2, 6, 26, sit), d.base, folds(wy, h2, w2, d.shade, 3) + P(`M${-w2} ${h2 - 16} L${w2} ${h2 - 16} L${w2} ${h2 + 40} L${-w2} ${h2 + 40}Z`, flat(d.lace)))
      for (const k of [-0.62, 0, 0.62]) o += bow(k * w2, h2 + 4, 0.42, d.accent, d.accentShade)
      o += laceBand(hy + 4, hw - 18, 16, 14, d.lace, d.laceShade)
    } else if (D.skirt === 'gothic') {
      o += laceBand(hy - 34, hw - 30, 12, 16, d.lace, d.laceShade)
      o += laceBand(hy - 70, hw - 52, 10, 14, d.accent, d.accentShade)
    } else if (D.skirt === 'apron') {
      const ay = sit ? -60 : -178, aw = sit ? 150 : 122
      let a = `M-52 ${wy + 8} L52 ${wy + 8} L${aw} ${ay}`
      const k = aw * 2 / 7
      for (let i = 0; i < 7; i++) a += ` q${-k / 2} 20 ${-k} 0`
      o += part(a + 'Z', d.lace, P(`M${aw} ${ay - 40} L${aw} ${ay + 30} L${-aw} ${ay + 30} L${-aw} ${ay - 40}Z`, flat(d.laceShade)) + P(`M${aw - 30} ${wy} L${aw + 20} ${ay + 20} L${aw + 40} ${wy}Z`, flat(d.laceShade)))
      for (const yy of [0.35, 0.7]) o += bow(0, wy + (ay - wy) * yy, 0.36, d.accent, d.accentShade)
      o += laceBand(hy + 4, hw - 18, 16, 14, d.lace, d.laceShade)
    }
    return o
  }
  function bodice(U, sit) {
    const d = D.dress, top = -452 + U, wy = -335 + U + 4
    const body = `M-66 ${top} Q-96 ${top + 4} -96 ${top + 34} L-64 ${wy} L64 ${wy} L96 ${top + 34} Q96 ${top + 4} 66 ${top}Z`
    let inner = P(`M30 ${top} L96 ${top} L96 ${wy} L48 ${wy}Z`, flat(d.shade))
    if (D.collar === 'high') {   // 黑蔷薇：胸前红色束腰，白色交叉系带
      inner += P(`M-34 ${top + 30} L34 ${top + 30} L28 ${wy} L-28 ${wy}Z`, flat(d.accent))
      for (let i = 0; i < 4; i++) {
        const y = top + 44 + i * ((wy - top - 54) / 4)
        inner += P(`M-20 ${y} L20 ${y + 18} M20 ${y} L-20 ${y + 18}`, ink(4, d.lace))
      }
    }
    if (D.collar === 'jabot') inner += P(`M-30 ${top} L30 ${top} L22 ${wy} L-22 ${wy}Z`, flat(d.light))
    let o = part(body, d.base, inner)
    // 腰带
    o += part(`M-66 ${wy - 16} L66 ${wy - 16} L64 ${wy + 6} L-64 ${wy + 6}Z`, D.collar === 'high' ? d.shade : d.accent,
      P(`M-66 ${wy - 2} L66 ${wy - 2} L66 ${wy + 8} L-66 ${wy + 8}Z`, flat(D.collar === 'high' ? '#000' : d.accentShade)), LW * 0.9)
    return o
  }
  function collar(U) {
    const d = D.dress, y = -452 + U
    let o = ''
    if (D.collar === 'round') {   // 金卷：圆圆的白蕾丝领子，红蝴蝶结配金扣
      for (const s of [-1, 1]) o += part(`M0 ${y - 4} C${s * 40} ${y - 8} ${s * 92} ${y - 2} ${s * 96} ${y + 22} C${s * 98} ${y + 50} ${s * 50} ${y + 58} ${s * 6} ${y + 40}Z`, d.lace,
        E(s * 60, y + 40, 40, 14, flat(d.laceShade)))
      o += bow(0, y + 24, 0.7, d.accent, d.accentShade) + part(`M-11 ${y + 24} a11 11 0 1 0 22 0 a11 11 0 1 0 -22 0Z`, d.metal, C(3, y + 28, 6, flat(d.metalShade)))
    } else if (D.collar === 'high') {   // 黑蔷薇：立起来的白蕾丝高领 + 红丝带颈圈和浮雕扣
      o += part(`M-36 ${y - 40} L36 ${y - 40} L40 ${y + 4} L-40 ${y + 4}Z`, d.lace, P(`M-40 ${y - 14} L40 ${y - 14} L40 ${y + 6} L-40 ${y + 6}Z`, flat(d.laceShade)))
      let z = `M-44 ${y - 40}`
      for (let i = 0; i < 8; i++) z += ` l5.5 -10 l5.5 10`
      o += P(z, ink(LW * 0.7)) + part(`M-40 ${y - 26} L40 ${y - 26} L40 ${y - 12} L-40 ${y - 12}Z`, d.accent, '', LW * 0.7)
      o += part(`M-13 ${y - 19} a13 16 0 1 0 26 0 a13 16 0 1 0 -26 0Z`, d.metal, E(0, y - 16, 7, 8, flat(d.metalShade)), LW * 0.8)
      for (const s of [-1, 1]) o += bow(s * 52, y + 60, 0.42, d.accent, d.accentShade)
    } else if (D.collar === 'jabot') {   // 紫藤：小白领 + 胸前一串褶皱花边 + 紫宝石胸针
      for (const s of [-1, 1]) o += part(`M0 ${y - 4} C${s * 30} ${y - 6} ${s * 70} ${y - 2} ${s * 72} ${y + 16} C${s * 70} ${y + 34} ${s * 34} ${y + 36} ${s * 4} ${y + 24}Z`, d.lace, E(s * 44, y + 26, 30, 9, flat(d.laceShade)))
      for (let i = 3; i >= 0; i--) o += frill(0, y + 40 + i * 20, 30 - i * 2, 11, d.lace, d.laceShade)
      o += gem(0, y + 22, 14, d.accent, d.accentShade, d.metal)
    }
    return o
  }
  function gem(x, y, r, c, sh, rim) {
    return part(`M${x - r - 4} ${y} a${r + 4} ${r + 4} 0 1 0 ${2 * r + 8} 0 a${r + 4} ${r + 4} 0 1 0 ${-2 * r - 8} 0Z`, rim, '', LW * 0.8)
      + part(`M${x} ${y - r} L${x + r} ${y} L${x} ${y + r} L${x - r} ${y}Z`, c, P(`M${x} ${y} L${x + r} ${y} L${x} ${y + r} L${x - r} ${y}Z`, flat(sh)) + P(`M${x - r * 0.5} ${y - r * 0.2} L${x - r * 0.1} ${y - r * 0.6}`, ink(3, '#ffffff')), LW * 0.7)
  }
  function bow(x, y, k, c, sh) {   // 蝴蝶结：两只耳朵 + 两条飘带 + 结
    const s = v => r1(v * k)
    let o = ''
    for (const side of [-1, 1]) {
      o += part(`M${x} ${y} L${x + side * s(30)} ${y + s(66)} L${x + side * s(8)} ${y + s(58)} L${x + side * s(2)} ${y + s(74)}Z`, c, P(`M${x + side * s(14)} ${y + s(30)} L${x + side * s(40)} ${y + s(70)} L${x} ${y + s(80)}Z`, flat(sh)), LW * Math.min(1, k + 0.3))
    }
    for (const side of [-1, 1]) {
      o += part(`M${x} ${y} C${x + side * s(30)} ${y - s(44)} ${x + side * s(78)} ${y - s(34)} ${x + side * s(74)} ${y} C${x + side * s(78)} ${y + s(34)} ${x + side * s(30)} ${y + s(44)} ${x} ${y}Z`, c,
        P(`M${x} ${y} C${x + side * s(30)} ${y + s(10)} ${x + side * s(70)} ${y + s(10)} ${x + side * s(80)} ${y + s(4)} L${x + side * s(80)} ${y + s(50)} L${x} ${y + s(50)}Z`, flat(sh)), LW * Math.min(1, k + 0.3))
    }
    return o + part(`M${x - s(14)} ${y} a${s(14)} ${s(15)} 0 1 0 ${s(28)} 0 a${s(14)} ${s(15)} 0 1 0 ${-s(28)} 0Z`, c, E(x + s(4), y + s(7), s(12), s(8), flat(sh)), LW * Math.min(1, k + 0.3))
  }
  function flower(x, y, k) {
    let o = ''
    for (let i = 0; i < 8; i++) {
      const a = i / 8 * TAU, px = x + Math.cos(a) * 15 * k, py = y + Math.sin(a) * 15 * k
      o += E(px, py, 11 * k, 7 * k, { ...fill(FLOWER[0], LW * 0.6), transform: rot(deg(a), px, py) })
    }
    return o + C(x, y, 8 * k, fill(FLOWER[2], LW * 0.6)) + C(x + 2 * k, y + 2 * k, 4 * k, flat(FLOWER[1]))
  }

  // ---------------- 头 ----------------
  const FACE = 'M-178 -690 C-180 -575 -112 -485 0 -478 C112 -485 180 -575 178 -690 C176 -790 -176 -790 -178 -690Z'
  function neck(U) {
    return part(`M-24 -506 L-24 ${-438 + U} L24 ${-438 + U} L24 -506Z`, D.skin[0], P(`M-30 -510 L30 -510 L30 -470 Q0 -452 -30 -470Z`, flat(D.skin[1])))
  }
  function face(f) {
    let shade = P('M-200 -800 L200 -800 L200 -712 Q100 -690 0 -694 Q-100 -690 -200 -712Z', flat(D.skin[1]))
    let o = part(FACE, D.skin[0], shade)
    // 腮红
    if (f.blush > 0) for (const s of [-1, 1]) {
      o += E(s * 112, -548, 34, 15, { fill: D.blush, opacity: 0.35 * f.blush })
      if (f.blush > 0.7) for (let i = 0; i < 3; i++) o += P(`M${s * 112 + (i - 1) * 13 - 4} -542 l8 -12`, { ...ink(3, D.blush), opacity: 0.9 })
    }
    for (const s of [-1, 1]) o += eye(s * 76, -598, s, f)
    o += brows(f) + mouth(f) + P('M-3 -556 Q2 -552 5 -557', { ...ink(3.5), opacity: 0.45 })
    if (f.puff) o += P('M150 -560 Q180 -548 168 -514', ink(LW))   // 鼓起的腮帮子
    if (f.tear) o += P('M-108 -570 q-8 14 0 20 q8 -6 0 -20Z', { ...fill('#bfe6ff', 3) })
    return o
  }
  function eye(cx, cy, side, f) {
    const k = f.eyes, [dark, base, light] = D.eye, L = D.line
    const gx = (f.gaze?.[0] || 0) * 9, gy = (f.gaze?.[1] || 0) * 8
    if (k === 'closed' || k === 'sleep') {
      return P(`M${cx - 30} ${cy + 4} Q${cx} ${cy + 22} ${cx + 30} ${cy + 4}`, ink(7)) + P(`M${cx + side * 30} ${cy + 4} l${side * 10} -6`, ink(5))
    }
    if (k === 'happy') return P(`M${cx - 30} ${cy + 12} Q${cx} ${cy - 22} ${cx + 30} ${cy + 12}`, ink(8))
    if (k === 'tight') return P(`M${cx - side * 24} ${cy - 18} L${cx + side * 14} ${cy} L${cx - side * 24} ${cy + 18}`, ink(8))
    const wide = k === 'wide', rx = wide ? 31 : 30, ry = wide ? 42 : 40
    const lid = k === 'half' ? 0.45 : k === 'down' ? 0.3 : k === 'sad' ? 0.15 : 0
    const id = 'e' + (uid++)
    const top = cy - ry + lid * ry * 2
    defs.push(`<clipPath id="${id}"><path d="M${cx - rx} ${cy} a${rx} ${ry} 0 1 0 ${rx * 2} 0 a${rx} ${ry} 0 1 0 ${-rx * 2} 0Z"/></clipPath>`)
    const gid = 'g' + (uid++)
    defs.push(`<linearGradient id="${gid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${dark}"/><stop offset="0.55" stop-color="${base}"/><stop offset="1" stop-color="${light}"/></linearGradient>`)
    const ix = cx + gx, iy = cy + gy + 4, irx = wide ? 19 : 27, iry = wide ? 25 : 35
    let inside = P(`M${cx - rx - 5} ${top} L${cx + rx + 5} ${top} L${cx + rx + 5} ${cy + ry + 5} L${cx - rx - 5} ${cy + ry + 5}Z`, flat('#ffffff'))
      + E(ix, iy, irx, iry, { fill: `url(#${gid})` })
      + E(ix, iy - 4, irx * 0.45, iry * 0.45, flat(dark))
      + P(`M${ix - irx * 0.75} ${iy + iry * 0.35} Q${ix} ${iy + iry * 1.05} ${ix + irx * 0.75} ${iy + iry * 0.35} Q${ix} ${iy + iry * 0.75} ${ix - irx * 0.75} ${iy + iry * 0.35}Z`, { fill: light, opacity: 0.8 })
      + E(ix - irx * 0.36, iy - iry * 0.4, wide ? 7 : 10, wide ? 9 : 12, flat('#ffffff'))
      + C(ix + irx * 0.42, iy + iry * 0.36, wide ? 4 : 5, flat('#ffffff'))
    if (k === 'sad') inside += E(ix, iy + iry * 0.55, irx * 0.8, 6, { fill: '#ffffff', opacity: 0.75 })
    inside += P(`M${cx - rx - 5} ${cy - ry - 5} L${cx + rx + 5} ${cy - ry - 5} L${cx + rx + 5} ${top} L${cx - rx - 5} ${top}Z`, flat(D.skin[0]))
    let o = G(inside, { 'clip-path': `url(#${id})` })
    // 上睫毛：沿上边一道粗线，眼尾翘一下
    const t0 = lid > 0 ? top : cy - ry
    if (lid > 0) {
      o += P(`M${cx - rx - 3} ${t0 + 6} Q${cx} ${t0 - 6} ${cx + rx + 3} ${t0 + 6}`, ink(9, L))
    } else {
      const a = [], b = []
      for (let i = 0; i <= 10; i++) {
        const th = Math.PI + 0.12 + (Math.PI - 0.24) * i / 10, w = 3 + 5 * Math.sin(Math.PI * i / 10)
        a.push(onE(cx, cy, rx + 2 + w * 0.5, ry + 2 + w * 0.6, th)); b.push(onE(cx, cy, rx - 1, ry - 1, th))
      }
      o += P(`M${pts(a)} L${pts(b.reverse())}Z`, { fill: L, stroke: L, 'stroke-width': 2, 'stroke-linejoin': 'round' })
    }
    const ox = cx + side * (rx + 1), oy = (lid > 0 ? t0 + 6 : cy - ry * 0.45)
    o += P(`M${ox - side * 6} ${oy} L${ox + side * 11} ${oy - 12} L${ox + side * 4} ${oy + 6}Z`, { fill: L, stroke: L, 'stroke-width': 2, 'stroke-linejoin': 'round' })
    o += P(`M${cx - rx * 0.45} ${cy + ry + 3} Q${cx} ${cy + ry + 7} ${cx + rx * 0.45} ${cy + ry + 3}`, { ...ink(3.5), opacity: 0.55 })
    return o
  }
  function brows(f) {
    let o = ''
    const c = D.hair.brow
    for (const s of [-1, 1]) {
      const x = s * 76, y = -668
      let inY = 0, outY = 0, lift = 0
      if (f.brows === 'up') lift = -10
      if (f.brows === 'worried') { inY = -10; outY = 6 }
      if (f.brows === 'angry') { inY = 12; outY = -6 }
      if (f.brows === 'smug') { inY = s > 0 ? 4 : -2; outY = s > 0 ? -8 : 2 }
      const ix = x - s * 26, ox = x + s * 28
      o += P(`M${ix} ${y + inY + lift} Q${x} ${y - 10 + lift + (inY + outY) / 2} ${ox} ${y + outY + lift + 2}`, ink(6, c))
    }
    return o
  }
  function mouth(f) {
    const y = -524, m = f.mouth
    const red = '#c4475a', tongue = '#ff8f9c'
    switch (m) {
      case 'open': return part(`M-22 ${y - 6} Q0 ${y - 2} 22 ${y - 6} Q20 ${y + 24} 0 ${y + 26} Q-20 ${y + 24} -22 ${y - 6}Z`, red, E(0, y + 22, 14, 9, flat(tongue)), 4.5)
      case 'laugh': return part(`M-30 ${y - 10} Q0 ${y - 4} 30 ${y - 10} Q28 ${y + 30} 0 ${y + 34} Q-28 ${y + 30} -30 ${y - 10}Z`, red, E(0, y + 28, 18, 11, flat(tongue)), 4.5)
      case 'o': return part(`M-11 ${y + 4} a11 13 0 1 0 22 0 a11 13 0 1 0 -22 0Z`, red, E(0, y + 12, 7, 5, flat(tongue)), 4.5)
      case 'O': return part(`M-17 ${y + 6} a17 21 0 1 0 34 0 a17 21 0 1 0 -34 0Z`, red, E(0, y + 18, 11, 7, flat(tongue)), 4.5)
      case 'flat': return P(`M-12 ${y + 2} L12 ${y + 2}`, ink(5))
      case 'wavy': return P(`M-24 ${y + 4} q6 -8 12 0 t12 0 t12 0 t12 0`, ink(5))
      case 'pout': return P(`M-12 ${y + 6} Q0 ${y - 4} 12 ${y + 6}`, ink(5))
      case 'cat': return P(`M-24 ${y - 2} Q-12 ${y + 14} 0 ${y} Q12 ${y + 14} 24 ${y - 2}`, ink(5))
      case 'smirk': return P(`M-16 ${y + 2} Q4 ${y + 12} 20 ${y - 6}`, ink(5))
      case 'none': return ''
      default: return P(`M-16 ${y} Q0 ${y + 12} 16 ${y}`, ink(5))   // smile
    }
  }

  // ---------------- 头发 ----------------
  function hairBack(sway, sit) {
    const h = D.hair
    if (h.style === 'drills') {
      let o = part('M-205 -650 C-210 -540 -190 -470 -150 -440 L150 -440 C190 -470 210 -540 205 -650 C205 -800 110 -884 0 -884 C-110 -884 -205 -800 -205 -650Z', h.back)
      for (const s of [-1, 1]) o += drill(s, sway)
      return o
    }
    if (h.style === 'hime') {
      const b = sit ? -120 : -190
      let d = `M-200 -700 C-212 -520 -224 -360 -226 ${b}`
      const n = 9, w = 452 / n
      for (let i = 0; i < n; i++) d += ` l${w / 2} ${i % 2 ? 10 : -6} l${w / 2} ${i % 2 ? -10 : 6}`
      d += ` C224 -360 212 -520 200 -700 C205 -870 -205 -870 -200 -700Z`
      return G(part(d, h.back, P(`M-60 -700 L-90 ${b + 20} L-40 ${b + 20}Z M70 -700 L100 ${b + 20} L50 ${b + 20}Z`, flat(h.shade))
        + P(`M-196 -560 Q-206 -420 -208 ${b + 40} M-170 -520 Q-178 -400 -180 ${b + 30} M196 -560 Q206 -420 208 ${b + 40} M170 -520 Q178 -400 180 ${b + 30}`, { ...ink(5, h.light), opacity: 0.45 })), { transform: rot(sway * 0.6, 0, -640) })
    }
    // 紫藤：长卷发，发尾一圈圈的
    const b = sit ? -150 : -250
    let d = `M-202 -690 C-222 -560 -232 -420 -228 ${b}`
    const n = 7, w = 456 / n
    for (let i = 0; i < n; i++) d += ` c${w * 0.1} ${30} ${w * 0.9} ${30} ${w} 0`
    d += ` C232 -420 222 -560 202 -690 C206 -872 -206 -872 -202 -690Z`
    return G(part(d, h.back, P(`M-120 -640 Q-140 ${b - 40} -180 ${b + 30} L-120 ${b + 30} Z M120 -640 Q140 ${b - 40} 180 ${b + 30} L120 ${b + 30}Z`, flat(h.shade))), { transform: rot(sway * 0.6, 0, -640) })
  }
  // 金卷的螺旋卷：从头两侧垂下来，一节一节，越往下越细，下面的节晃得多一点
  function drill(s, sway) {
    const h = D.hair, n = 6
    let o = ''
    const segs = []
    for (let i = 0; i < n; i++) {
      const k = i / (n - 1), w = 98 - 46 * k, hh = 58 - 14 * k
      const x = s * (196 + 22 * k) + sway * (2 + i * 3.2) * s * 0.5 + sway * i * 2.2, y = -690 + i * 66
      segs.push([x, y, w, hh])
    }
    // 发根：头侧连到第一节
    o += part(`M${s * 150} -800 C${s * 210} -790 ${s * 240} -740 ${segs[0][0] + s * segs[0][2] * 0.5} ${segs[0][1]} L${segs[0][0] - s * segs[0][2] * 0.5} ${segs[0][1]} C${s * 170} -730 ${s * 150} -760 ${s * 140} -780Z`, h.base, '', LW)
    for (let i = n - 1; i >= 0; i--) {
      const [x, y, w, hh] = segs[i], a = -s * 18
      const sh = `M${x - w / 2} ${y} C${x - w / 2} ${y - hh * 1.1} ${x + w / 2} ${y - hh * 1.1} ${x + w / 2} ${y} C${x + w / 2} ${y + hh * 1.1} ${x - w / 2} ${y + hh * 1.1} ${x - w / 2} ${y}Z`
      o += G(part(sh, h.base, P(`M${x - w} ${y + 4} Q${x} ${y + hh * 0.45} ${x + w} ${y - 6} L${x + w} ${y + hh * 2} L${x - w} ${y + hh * 2}Z`, flat(h.shade))
        + P(`M${x - w * 0.3} ${y - hh * 0.55} Q${x + w * 0.05} ${y - hh * 0.75} ${x + w * 0.32} ${y - hh * 0.45}`, ink(7, h.light))), { transform: rot(a, x, y) })
    }
    const [lx, ly, lw] = segs[n - 1]
    o += P(`M${lx - lw * 0.3} ${ly + 40} Q${lx + s * 4} ${ly + 74} ${lx + s * 26} ${ly + 56}`, ink(LW + 4)) + P(`M${lx - lw * 0.3} ${ly + 40} Q${lx + s * 4} ${ly + 74} ${lx + s * 26} ${ly + 56}`, ink(8, h.base))
    return o
  }
  function hairFront(f) {
    const h = D.hair
    let o = ''
    if (h.style === 'drills') {
      // 两边鬓角
      for (const s of [-1, 1]) o += part(`M${s * 204} -730 C${s * 222} -640 ${s * 210} -580 ${s * 172} -530 C${s * 188} -560 ${s * 176} -620 ${s * 150} -700Z`, h.base, P(`M${s * 210} -700 L${s * 170} -540 L${s * 230} -540Z`, flat(h.shade)))
      o += cap(['M196 -640', [152, -660], [124, -720], [96, -680], [62, -726], [30, -688], [-2, -730], [-36, -690], [-66, -726], [-98, -680], [-126, -718], [-152, -658], '-196 -640'], -14)
    } else if (h.style === 'hime') {
      for (const s of [-1, 1]) o += part(`M${s * 206} -740 C${s * 214} -650 ${s * 214} -580 ${s * 206} -496 L${s * 148} -500 C${s * 156} -580 ${s * 156} -650 ${s * 148} -720Z`, h.base,
        P(`M${s * 206} -700 L${s * 180} -700 L${s * 182} -496 L${s * 206} -496Z`, flat(h.shade)))
      o += cap(['M198 -650', [176, -694], [150, -722], [120, -700], [88, -716], [54, -700], [20, -716], [-16, -700], [-52, -716], [-88, -700], [-120, -718], [-152, -700], [-176, -716], '-198 -650'], 0, true)
    } else {
      for (const s of [-1, 1]) o += part(`M${s * 204} -730 C${s * 230} -620 ${s * 214} -540 ${s * 182} -470 C${s * 206} -480 ${s * 214} -500 ${s * 212} -470 C${s * 236} -520 ${s * 222} -580 ${s * 216} -640 C${s * 200} -690 ${s * 176} -700 ${s * 150} -710Z`, h.base, P(`M${s * 216} -690 L${s * 186} -480 L${s * 240} -480Z`, flat(h.shade)))
      o += cap(['M198 -640', [160, -656], [138, -714], [108, -676], [72, -724], [40, -690], [-10, -748], [-40, -694], [-76, -720], [-112, -674], [-142, -712], [-160, -656], '-198 -640'], 10)
    }
    return o
  }
  // 头顶 + 刘海：points 是刘海下边（从右往左）：发尖、发缝交替；bend 让每缕往一边撇
  function cap(p, bend, blunt) {
    const h = D.hair
    let d = `${p[0]} C200 -770 120 -880 0 -880 C-120 -880 -200 -770 -196 -640`
    const lower = p.slice(1, -1)
    // 从左往右沿刘海下边走回去
    const back = lower.slice().reverse()
    d += ` L${back[0][0] - 20} ${back[0][1] + 10}`
    for (let i = 0; i < back.length; i++) {
      const [x, y] = back[i], prev = i ? back[i - 1] : [back[0][0] - 20, back[0][1] + 10]
      if (blunt) d += ` L${x} ${y}`
      else d += ` Q${(prev[0] + x) / 2 + bend} ${(prev[1] + y) / 2 + (y > prev[1] ? -8 : 8)} ${x} ${y}`
    }
    d += ` L${lower[0][0] + 24} ${lower[0][1] + 10}Z`
    const shine = P('M-150 -790 Q-120 -830 -80 -838 L-74 -814 Q-110 -806 -132 -776Z M-40 -846 Q0 -852 40 -846 L36 -822 Q0 -828 -36 -822Z M80 -838 Q120 -830 150 -790 L132 -776 Q110 -806 74 -814Z', flat(h.light))
    const under = P('M-220 -760 Q0 -700 220 -760 L220 -600 L-220 -600Z', flat(h.shade))
    return part(d, h.base, under + shine)
  }
  function hairAcc(f, sway) {
    const h = D.hair, d = D.dress
    let o = ''
    if (h.style === 'drills') {
      for (const s of [-1, 1]) o += G(bow(s * 172, -790, 1.0, d.accent, d.accentShade), { transform: rot(s * 18 + sway * 0.5, s * 172, -790) })
      o += flower(150, -830, 1.0)
    } else if (h.style === 'hime') {
      // 歪戴的小礼帽：黑色、红丝带、一朵小橙花，后面一片黑纱
      const hx = 96, hy = -848
      o += G(
        P(`M${hx - 70} ${hy + 6} Q${hx - 40} ${hy + 70} ${hx + 20} ${hy + 64} Q${hx + 90} ${hy + 56} ${hx + 110} ${hy + 2}Z`, { fill: '#1b1720', opacity: 0.35, stroke: D.line, 'stroke-width': 3 })
        + part(`M${hx - 104} ${hy + 4} Q${hx} ${hy + 34} ${hx + 104} ${hy + 4} Q${hx} ${hy - 22} ${hx - 104} ${hy + 4}Z`, d.base, E(hx, hy + 14, 90, 10, flat(d.shade)))
        + part(`M${hx - 58} ${hy} L${hx - 52} ${hy - 104} Q${hx} ${hy - 118} ${hx + 52} ${hy - 104} L${hx + 58} ${hy}Q${hx} ${hy + 14} ${hx - 58} ${hy}Z`, d.base, P(`M${hx + 20} ${hy - 120} L${hx + 70} ${hy - 120} L${hx + 70} ${hy + 20} L${hx + 26} ${hy + 20}Z`, flat(d.shade)) + E(hx - 30, hy - 80, 8, 18, { fill: d.light, opacity: 0.8 }))
        + part(`M${hx - 57} ${hy - 30} Q${hx} ${hy - 18} ${hx + 57} ${hy - 30} L${hx + 58} ${hy - 6} Q${hx} ${hy + 6} ${hx - 58} ${hy - 6}Z`, d.accent, '', LW * 0.9)
        + flower(hx + 40, hy - 18, 1.0), { transform: rot(14, hx, hy) })
      o += bow(-150, -800, 0.55, d.accent, d.accentShade)
    } else {
      // 编发发箍 + 小银冠 + 耳后小橙花
      for (let i = 0; i <= 10; i++) {
        const a = Math.PI + 0.35 + (Math.PI - 0.7) * i / 10, [x, y] = onE(0, -690, 192, 176, a)
        o += E(x, y, 22, 14, { ...fill(h.shade, LW * 0.8), transform: rot(deg(a) + 90 + (i % 2 ? 30 : -30), x, y) })
      }
      o += part('M-54 -838 L-40 -890 L-20 -856 L0 -906 L20 -856 L40 -890 L54 -838 Q0 -848 -54 -838Z', d.metal, P('M0 -906 L54 -838 L0 -848Z', flat(d.metalShade)))
      o += gem(0, -864, 9, d.accent, d.accentShade, d.metal)
      o += flower(196, -700, 1.0)
    }
    return o
  }

  // ---------------- 道具 ----------------
  // 每个道具画在手的位置，a 是朝向（度，0 朝右，向下为正）
  function prop(p, Hh) {
    const [x, y] = Hh, d = D.dress
    const T = inner => G(inner, { transform: `${tr(x, y)} rotate(${r1(p.angle || 0)})` })
    switch (p.kind) {
      case 'fan': {
        if (!p.open) return T(part('M-6 -10 L118 -16 Q126 0 118 16 L-6 10Z', d.metal, P('M0 0 L120 0 L120 20 L0 20Z', flat(d.metalShade)) + P('M30 -12 L30 12 M60 -14 L60 14 M90 -15 L90 15', ink(3, d.metalShade)))
          + P('M-8 0 Q-20 8 -18 24', ink(3, d.metalShade)) + E(-18, 30, 4, 7, fill(d.metal, 2.5)))
        let o = '', n = 9, R = 118, a0 = -150, a1 = -30
        let outer = `M0 0`
        for (let i = 0; i <= n; i++) { const a = (a0 + (a1 - a0) * i / n) * Math.PI / 180; outer += ` L${r1(Math.cos(a) * R)} ${r1(Math.sin(a) * R)}` }
        outer += 'Z'
        let pleats = ''
        for (let i = 0; i < n; i++) if (i % 2) {
          const b0 = (a0 + (a1 - a0) * i / n) * Math.PI / 180, b1 = (a0 + (a1 - a0) * (i + 1) / n) * Math.PI / 180
          pleats += P(`M0 0 L${Math.cos(b0) * R * 1.1} ${Math.sin(b0) * R * 1.1} L${Math.cos(b1) * R * 1.1} ${Math.sin(b1) * R * 1.1}Z`, flat(d.light))
        }
        let lace = ''
        for (let i = 0; i < n; i++) { const a = (a0 + (a1 - a0) * (i + 0.5) / n) * Math.PI / 180; lace += C(Math.cos(a) * R, Math.sin(a) * R, 12, fill(d.lace, 3)) }
        o += lace + part(outer, d.base, pleats + P('M-200 -40 L200 -40 L200 40 L-200 40Z', flat(d.accent)))
        o += C(0, 0, 9, fill(d.metal, 3))
        return T(o)
      }
      case 'parasol': {   // 收起的阳伞：上头弯柄在手里，伞尖朝下
        const L = p.len || 330
        return T(P(`M0 0 L0 ${L}`, ink(12)) + P(`M0 0 L0 ${L}`, ink(6, d.metalShade))
          + part(`M0 ${L * 0.26} C36 ${L * 0.42} 30 ${L * 0.7} 4 ${L * 0.92} L-4 ${L * 0.92} C-30 ${L * 0.7} -36 ${L * 0.42} 0 ${L * 0.26}Z`, d.base, P(`M4 ${L * 0.3} L30 ${L * 0.3} L30 ${L} L6 ${L}Z`, flat(d.shade)) + P(`M-14 ${L * 0.5} Q0 ${L * 0.55} 14 ${L * 0.5} M-10 ${L * 0.66} Q0 ${L * 0.7} 10 ${L * 0.66}`, ink(4, d.lace)))
          + bow(0, L * 0.3, 0.4, d.accent, d.accentShade)
          + P(`M0 4 Q0 -34 -26 -34 Q-46 -34 -44 -12`, ink(14)) + P(`M0 4 Q0 -34 -26 -34 Q-46 -34 -44 -12`, ink(7, d.metal)))
      }
      case 'teacup': {
        return T(part('M-50 6 Q0 26 50 6 Q50 -6 0 -6 Q-50 -6 -50 6Z', '#ffffff', E(0, 10, 46, 8, flat(d.laceShade)), LW * 0.8)
          + part('M-30 -40 L30 -40 Q30 -2 0 0 Q-30 -2 -30 -40Z', '#ffffff', P('M-30 -26 L30 -26 L30 -18 L-30 -18Z', flat(d.accent)) + P('M10 -44 L34 -44 L34 4 L8 4Z', flat(d.laceShade)), LW * 0.8)
          + E(0, -40, 30, 8, fill('#c98a5a', LW * 0.8)) + E(-4, -42, 16, 3.5, { fill: '#e6b07a' })
          + P('M30 -32 Q48 -32 44 -18 Q40 -8 26 -12', ink(LW + 4)) + P('M30 -32 Q48 -32 44 -18 Q40 -8 26 -12', ink(5, '#ffffff')))
      }
      case 'spoon': return T(P('M0 0 L-40 -70', ink(9)) + P('M0 0 L-40 -70', ink(4, d.metal)) + E(-44, -78, 7, 11, { ...fill(d.metal, 4), transform: rot(-30, -44, -78) }))
      case 'book': {
        const [c, sh] = D.book
        if (!p.open) return T(part('M-46 -58 L46 -58 L46 58 L-46 58Z', c, P('M30 -60 L50 -60 L50 60 L30 60Z', flat(sh)) + P('M-46 40 L46 40', ink(4, sh))) + flower(-6, -6, 0.9))
        return T(part('M0 -30 L-96 -46 L-96 40 L0 56 L96 40 L96 -46Z', c)
          + part('M0 -24 L-88 -40 L-88 32 L0 46Z', '#fffaf2', P('M-76 -22 L-14 -12 M-76 -6 L-14 4 M-76 10 L-14 20', ink(3, '#d6cfc4')), LW * 0.8)
          + part('M0 -24 L88 -40 L88 32 L0 46Z', '#fffaf2', P('M14 -12 L76 -22 M14 4 L76 -6 M14 20 L76 10', ink(3, '#d6cfc4')) + P('M60 -50 L100 -50 L100 50 L60 50Z', flat('#efe5d6')), LW * 0.8))
      }
      case 'quill': return T(part('M0 0 Q-20 -60 -6 -130 Q20 -70 6 0Z', '#ffffff', P('M0 -130 Q6 -60 3 0 L20 0 L20 -130Z', flat(D.dress.laceShade)), LW * 0.8) + P('M2 0 L-2 -120', ink(3)) + P('M2 0 L6 22', ink(5)))
      case 'magnifier': return T(P('M0 0 L-46 -52', ink(16)) + P('M0 0 L-46 -52', ink(9, '#8a5a3a'))
        + C(-74, -84, 40, { fill: '#cfeeff', 'fill-opacity': 0.35, stroke: D.line, 'stroke-width': LW + 9 }) + C(-74, -84, 40, { fill: 'none', stroke: d.metal || '#f4c44f', 'stroke-width': 9 })
        + P('M-96 -100 Q-90 -112 -78 -114', ink(5, '#ffffff')))
      case 'bell': {
        const [c, sh] = D.bell
        return T(P('M0 0 L0 -40', ink(14)) + P('M0 0 L0 -40', ink(8, '#8a5a3a'))
          + part('M-34 -40 Q-34 -96 0 -98 Q34 -96 34 -40 Q44 -36 40 -30 L-40 -30 Q-44 -36 -34 -40Z', c, P('M8 -100 L40 -100 L40 -30 L12 -30Z', flat(sh)) + E(-14, -76, 6, 12, { fill: '#ffffff', opacity: 0.6 }))
          + C(0, -24, 8, fill(sh, 4)))
      }
    }
    return ''
  }

  // ---------------- 姿态 ----------------
  // hand：手的位置（站着时的身体坐标；坐下时整个上身一起往下挪）；prefer：手肘往外（默认）/ 往下 / 往里
  const HANDS = {
    down: [[-118, -318], [118, -318]],
    front: [[-22, -340], [22, -340]],
    chest: [[-16, -418], [16, -418]],
    hip: [[-96, -350], [96, -350]],
  }
  const sig = () => D.prop
  function signatureIdle(t) {   // 待机时手里拿着的招牌道具
    const p = sig()
    if (p === 'fan') return { L: { hand: [-20, -350] }, R: { hand: [24, -344] }, props: [{ kind: 'fan', hand: 'R', angle: -62 + wave(t, 1) * 2 }] }
    if (p === 'parasol') return { L: { hand: [-26, -344] }, R: { hand: [150, -336], prefer: 'down' }, props: [{ kind: 'parasol', hand: 'R', angle: 0, len: 336, z: 'mid' }] }
    return { L: { hand: [-30, -392] }, R: { hand: [30, -392] }, props: [{ kind: 'teacup', hand: 'C', dy: 4 }] }
  }
  const POSES = {
    idle(t) {
      const s = signatureIdle(t), blink = t > 0.7 && t < 0.745
      return { breath: -3 * (1 - Math.cos(TAU * t * 2)) / 2, sway: wave(t, 1) * 1.6, head: { rot: wave(t, 1) * 1.2 },
        face: { eyes: blink ? 'closed' : 'open', mouth: 'smile', brows: 'normal', blush: 0.6 }, ...s }
    },
    'idle-blink'(t) { const p = POSES.idle(0); p.face.eyes = 'closed'; return p },
    listening(t) {
      const s = signatureIdle(t)
      return { breath: -2 * bump(t, 0, 0.5), head: { rot: -5 + bump(t, 0.1, 0.5) * 3, dy: bump(t, 0.1, 0.5) * 4 }, sway: -2,
        face: { eyes: 'wide', mouth: 'o', brows: 'up', blush: 0.7, gaze: [-0.3, 0] }, L: { hand: [-150, -520] }, R: s.R, props: s.props.filter(p => p.hand === 'R'), overL: true }
    },
    thinking(t) {
      const p = sig(), tap = bump((t * 2) % 1, 0, 0.3)
      const props = p === 'fan' ? [{ kind: 'fan', hand: 'R', angle: -120 + tap * 8, z: 'over' }] : []
      return { breath: -2 * (1 - Math.cos(TAU * t)) / 2, head: { rot: 5 + wave(t, 1) * 2 }, sway: 1.5 + wave(t, 1),
        face: { eyes: 'open', gaze: [0.7, -0.8], mouth: 'flat', brows: 'up', blush: 0.4 },
        L: { hand: [70, -370], prefer: 'down' }, R: { hand: [40, -488 - tap * 4], prefer: 'down' }, props, overR: true }
    },
    reading(t) {
      const gx = -0.8 + 1.6 * ((t * 2) % 1)
      return { breath: -2 * (1 - Math.cos(TAU * t)) / 2, head: { dy: 8, rot: 0 }, sway: wave(t, 1),
        face: { eyes: 'down', gaze: [gx * 0.6, 0.9], mouth: 'smile', brows: 'normal', blush: 0.5 },
        L: { hand: [-62, -392], prefer: 'down' }, R: { hand: [62, -392], prefer: 'down' }, props: [{ kind: 'book', hand: 'C', open: true, dy: -8, z: 'front' }] }
    },
    writing(t) {
      const a = TAU * t * 2, qx = Math.cos(a) * 10, qy = Math.sin(a) * 6
      return { breath: -1.5 * (1 - Math.cos(TAU * t)) / 2, head: { dy: 8, rot: 3 }, sway: 1,
        face: { eyes: 'down', gaze: [0.3, 0.9], mouth: 'smile', brows: 'normal', blush: 0.5 },
        L: { hand: [-60, -372], prefer: 'down' }, R: { hand: [34 + qx, -386 + qy], prefer: 'down' },
        props: [{ kind: 'book', hand: 'L', open: true, dx: 60, dy: -12, angle: -8, z: 'mid' }, { kind: 'quill', hand: 'R', angle: 20 }] }
    },
    running(t) {
      const p = sig(), k = bump((t * 2) % 1, 0, 0.5)
      if (p === 'teacup') {   // 紫藤：搅红茶
        const a = TAU * t * 2
        return { breath: -2 * k, head: { rot: -2, dy: 4 }, face: { eyes: 'down', gaze: [0.2, 0.7], mouth: 'smile', brows: 'normal', blush: 0.5 },
          L: { hand: [-26, -380] }, R: { hand: [40 + Math.cos(a) * 10, -438 + Math.sin(a) * 4] }, props: [{ kind: 'teacup', hand: 'L', dx: 34, dy: 0 }, { kind: 'spoon', hand: 'R', angle: -10 }] }
      }
      return { breath: -3 * k, lift: -4 * k, head: { rot: -4 }, sway: -2 * k,
        face: { eyes: 'half', gaze: [0.6, 0], mouth: 'open', brows: 'smug', blush: 0.5 },
        L: { hand: HANDS.hip[0] }, R: { hand: [210 + 8 * k, -478 - 4 * k] },
        props: p === 'fan' ? [{ kind: 'fan', hand: 'R', angle: -18 }] : [{ kind: 'parasol', hand: 'R', angle: -98, len: 300 }] }
    },
    asking(t) {
      return { breath: -2 * (1 - Math.cos(TAU * t)) / 2, lift: -6 * bump(t, 0, 0.35), head: { rot: 7 + wave(t, 1) * 2 }, sway: wave(t, 1) * 2,
        face: { eyes: 'open', gaze: [0, -0.4], mouth: 'o', brows: 'worried', blush: 0.9 }, L: { hand: HANDS.chest[0] }, R: { hand: HANDS.chest[1] } }
    },
    happy(t) {
      const k = bump(t, 0, 0.28) + bump(t, 0.3, 0.56) * 0.7
      return { lift: -34 * k, breath: -3 * k, head: { rot: wave(t, 2) * 3 * (1 - t) }, sway: k * 4,
        face: { eyes: 'happy', mouth: 'open', brows: 'up', blush: 1 }, L: { hand: [-14, -430 - 10 * k] }, R: { hand: [14, -430 - 10 * k] } }
    },
    proud(t) {   // 「哦～呵呵呵」：一手叉腰、一手（或扇子）挡在嘴边
      const k = Math.abs(wave(t, 3)) * (t < 0.85 ? 1 : 0), p = sig()
      const fan = p === 'fan'
      return { breath: -4 * k, head: { rot: -6 - 2 * k, dy: -4 * k }, sway: -3 - 2 * k,
        face: { eyes: 'closed', mouth: fan ? 'laugh' : 'laugh', brows: 'smug', blush: 0.8 },
        L: { hand: HANDS.hip[0] }, R: { hand: fan ? [92, -520] : [70, -514] },
        props: fan ? [{ kind: 'fan', hand: 'R', open: true, angle: -28, z: 'over', dx: -4, dy: -8 }] : [], overR: !fan }
    },
    oops(t) {
      const k = t < 0.5 ? wave(t, 4) * (1 - t * 2) : 0
      return { breath: -2, head: { rot: 6 * k, dx: 4 * k }, sway: 3 * k,
        face: { eyes: 'tight', mouth: 'wavy', brows: 'worried', blush: 0.9 }, L: { hand: [-44, -498] }, R: { hand: [44, -498] }, overL: true, overR: true }
    },
    sorry(t) {
      return { breath: -1.5 * (1 - Math.cos(TAU * t)) / 2, head: { dy: 14 + 3 * bump(t, 0.2, 0.7), rot: -3 }, sway: 0,
        face: { eyes: 'sad', gaze: [-0.2, 0.8], mouth: 'wavy', brows: 'worried', blush: 0.6, tear: true }, L: { hand: HANDS.front[0] }, R: { hand: HANDS.front[1] } }
    },
    surprised(t) {
      const k = bump(t, 0, 0.45)
      return { lift: -50 * k, breath: -3, head: { rot: 0, dy: -4 * k }, sway: -4 * k,
        face: { eyes: 'wide', mouth: 'O', brows: 'up', blush: 0.6 }, L: { hand: [-168, -500 - 20 * k] }, R: { hand: [168, -500 - 20 * k] } }
    },
    pat(t) {
      return { breath: -2, head: { rot: wave(t, 2) * 5 }, sway: wave(t, 2) * 3,
        face: { eyes: 'happy', mouth: 'cat', brows: 'up', blush: 1 }, L: { hand: [-150, -548] }, R: { hand: [150, -548] }, overL: true, overR: true }
    },
    searching(t) {
      const a = TAU * t
      return { breath: -2 * (1 - Math.cos(a)) / 2, head: { rot: 3 + Math.sin(a) * 2 }, sway: Math.sin(a),
        face: { eyes: 'open', gaze: [0.4 + Math.sin(a) * 0.4, Math.cos(a) * 0.4], mouth: 'o', brows: 'up', blush: 0.5 },
        L: { hand: HANDS.hip[0] }, R: { hand: [146 + Math.sin(a) * 10, -500 + Math.cos(a) * 8] }, props: [{ kind: 'magnifier', hand: 'R', angle: 0, z: 'over' }] }
    },
    delegating(t) {
      const ring = wave(t, 4) * 16
      return { breath: -2 * Math.abs(wave(t, 2)), head: { rot: -4 }, sway: -2,
        face: { eyes: 'closed', mouth: 'open', brows: 'smug', blush: 0.6 }, L: { hand: HANDS.hip[0] }, R: { hand: [156, -556] },
        props: [{ kind: 'bell', hand: 'R', angle: ring, z: 'over' }], overR: true }
    },
    sleeping(t) {
      return { sit: true, breath: -3 * (1 - Math.cos(TAU * t)) / 2, head: { rot: 12 + wave(t, 1) * 1.5, dy: 6 }, sway: 3,
        face: { eyes: 'sleep', mouth: 'o', brows: 'normal', blush: 0.7 }, L: { hand: [-34, -300], prefer: 'down' }, R: { hand: [34, -300], prefer: 'down' } }
    },
    tired(t) {
      return { sit: true, breath: -2 * (1 - Math.cos(TAU * t)) / 2, head: { rot: -6, dy: 8 + bump(t, 0.3, 0.8) * 4 }, sway: -2,
        face: { eyes: 'half', gaze: [0, 0.6], mouth: 'wavy', brows: 'worried', blush: 0.4 }, L: { hand: [-40, -300], prefer: 'down' }, R: { hand: [40, -300], prefer: 'down' } }
    },
    bye(t) {
      const w = wave(t, 2.5) * 22
      return { breath: -2, head: { rot: -4 }, sway: -2, face: { eyes: 'happy', mouth: 'open', brows: 'up', blush: 0.8 },
        L: { hand: HANDS.front[0] }, R: { hand: [146 + w * 0.4, -566 + Math.abs(w) * 0.2] }, overR: true }
    },
    busy_left(t) { const p = POSES.idle(t); p.face.gaze = [-1, 0]; p.head = { rot: -4, dx: -6 }; p.face.mouth = 'flat'; return p },
    busy_right(t) { const p = POSES.idle(t); p.face.gaze = [1, 0]; p.head = { rot: 4, dx: 6 }; p.face.mouth = 'flat'; return p },
    pout(t) {   // 「哼」：抱着胳膊，头扭向一边
      const k = bump(t, 0, 0.3)
      return { breath: -2, head: { rot: 8 + 4 * k, dx: 6 }, sway: 3,
        face: { eyes: 'closed', mouth: 'pout', brows: 'angry', blush: 1, puff: true }, L: { hand: [64, -404], prefer: 'down' }, R: { hand: [-60, -398], prefer: 'down' } }
    },
    hum(t) {
      const p = sig(), k = wave(t, 3)
      if (p === 'fan') return { breath: -2, head: { rot: -3 + k }, sway: k * 2, face: { eyes: 'closed', mouth: 'smile', brows: 'normal', blush: 0.7 },
        L: { hand: HANDS.front[0] }, R: { hand: [128, -506] }, props: [{ kind: 'fan', hand: 'R', open: true, angle: -64 + k * 14, z: 'over' }], overR: true }
      return { breath: -2, head: { rot: 2, dy: 4 }, sway: 0, face: { eyes: 'closed', mouth: 'none', brows: 'normal', blush: 0.7 },
        L: { hand: [-30, -440] }, R: { hand: [30, -478 - 6 * bump(t, 0.2, 0.8)] }, props: [{ kind: 'teacup', hand: 'R', dx: -26, dy: -2, z: 'over' }], overR: true, overL: true }
    },
  }

  // ---------------- 拼起来 ----------------
  function svg(id, poseName, t, view) {
    D = DESIGNS[id]; defs = []; uid = 0; LW = 6
    const pose = POSES[poseName](t)
    const U = (pose.breath || 0) + (pose.sit ? 103 : 0), sit = !!pose.sit
    const hd = pose.head || {}, sway = pose.sway || 0
    const headT = `${tr(hd.dx || 0, (hd.dy || 0) + U)} ${rot(hd.rot || 0, 0, -480)}`
    const arms = {}
    for (const [k, side] of [['L', -1], ['R', 1]]) arms[k] = armParts(pose[k] || { hand: HANDS.down[side < 0 ? 0 : 1] }, side, U)
    const props = (pose.props || []).map(p => {
      const H = p.hand === 'C' ? [(arms.L.H[0] + arms.R.H[0]) / 2, (arms.L.H[1] + arms.R.H[1]) / 2] : arms[p.hand].H
      return { z: p.z || 'front', s: prop(p, [H[0] + (p.dx || 0), H[1] + (p.dy || 0)]) }
    })
    const z = k => props.filter(p => p.z === k).map(p => p.s).join('')
    let body = G(hairBack(sway, sit), { transform: headT })
    body += z('back')
    if (!sit) body += legs()
    body += skirt(U, sit) + bodice(U, sit) + collar(U) + neck(U)
    body += z('mid')
    if (!pose.overL) body += arms.L.out
    if (!pose.overR) body += arms.R.out
    body += z('front')
    body += G(face(pose.face) + hairFront(pose.face) + hairAcc(pose.face, sway), { transform: headT })
    if (pose.overL) body += arms.L.out
    if (pose.overR) body += arms.R.out
    body += z('over')
    const all = G(body, { transform: `translate(${r1(view.tx)} ${r1(view.ty + (pose.lift || 0) * view.s)}) scale(${view.s})` })
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
