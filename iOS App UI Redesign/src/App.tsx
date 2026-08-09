import { useState, useRef, type ReactElement } from 'react'

// ─── Color tokens ─────────────────────────────────────────────────────────────
const C = {
  blue: '#007AFF', orange: '#FF9500', red: '#FF3B30', green: '#34C759',
  bg: '#F2F2F7', card: '#FFFFFF', label: '#000', label2: '#3C3C43',
  label3: '#8E8E93', sep: 'rgba(60,60,67,0.29)',
} as const

// ─── SVG Icon library (SF Symbols approximations) ────────────────────────────
function Ic({ n, s = 20, c = '#000', w = 1.6 }: { n: string; s?: number; c?: string; w?: number }) {
  const p: Record<string, ReactElement> = {
    folder: <svg width={s} height={s} viewBox="0 0 24 24"><path d="M3 7.5A2.5 2.5 0 015.5 5h3.76a1 1 0 01.707.293l1.12 1.12A1 1 0 0011.794 6.7H18.5A2.5 2.5 0 0121 9.2V17.5A2.5 2.5 0 0118.5 20h-13A2.5 2.5 0 013 17.5v-10z" fill={c}/></svg>,
    doc: <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={w} strokeLinecap="round" strokeLinejoin="round"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><line x1="10" y1="9" x2="8" y2="9"/></svg>,
    cal: <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={w} strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>,
    bell: <svg width={s} height={s} viewBox="0 0 24 24"><path d="M18 8A6 6 0 006 8c0 7-3 9-3 9h18s-3-2-3-9z" fill={c}/><path d="M13.73 21a2 2 0 01-3.46 0" fill="none" stroke={c} strokeWidth={w} strokeLinecap="round"/></svg>,
    'bell-off': <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={w} strokeLinecap="round" strokeLinejoin="round"><path d="M13.73 21a2 2 0 01-3.46 0"/><path d="M18.63 13A17.89 17.89 0 0118 8"/><path d="M6.26 6.26A5.86 5.86 0 006 8c0 7-3 9-3 9h14"/><path d="M18 8a6 6 0 00-9.33-5"/><line x1="1" y1="1" x2="23" y2="23"/></svg>,
    mic: <svg width={s} height={s} viewBox="0 0 24 24"><rect x="9" y="1" width="6" height="13" rx="3" fill={c}/><path d="M19 10v2a7 7 0 01-14 0v-2" fill="none" stroke={c} strokeWidth={w} strokeLinecap="round"/><line x1="12" y1="19" x2="12" y2="23" stroke={c} strokeWidth={w} strokeLinecap="round"/><line x1="8" y1="23" x2="16" y2="23" stroke={c} strokeWidth={w} strokeLinecap="round"/></svg>,
    chat: <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={w} strokeLinecap="round" strokeLinejoin="round"><path d="M21 15a2 2 0 01-2 2H7l-4 4V5a2 2 0 012-2h14a2 2 0 012 2z"/></svg>,
    pencil: <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={w} strokeLinecap="round" strokeLinejoin="round"><path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/><path d="M18.5 2.5a2.12 2.12 0 013 3L12 15l-4 1 1-4z"/></svg>,
    trash: <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={w} strokeLinecap="round" strokeLinejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14H6L5 6m3 0V4a1 1 0 011-1h4a1 1 0 011 1v2"/><line x1="10" y1="11" x2="10" y2="17"/><line x1="14" y1="11" x2="14" y2="17"/></svg>,
    plus: <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={2.4} strokeLinecap="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>,
    x: <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={2.4} strokeLinecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>,
    check: <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"/></svg>,
    chevR: <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"><polyline points="9 18 15 12 9 6"/></svg>,
    chevD: <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"><polyline points="6 9 12 15 18 9"/></svg>,
    chevL: <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"><polyline points="15 18 9 12 15 6"/></svg>,
    up: <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={2.4} strokeLinecap="round" strokeLinejoin="round"><line x1="12" y1="19" x2="12" y2="5"/><polyline points="5 12 12 5 19 12"/></svg>,
    undo: <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={w} strokeLinecap="round" strokeLinejoin="round"><path d="M3 7v6h6"/><path d="M21 17a9 9 0 00-9-9 9 9 0 00-6 2.3L3 13"/></svg>,
    brain: <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={w} strokeLinecap="round" strokeLinejoin="round"><path d="M9 3C6.24 3 4 5.24 4 8c0 1.16.39 2.23 1.04 3.09A5 5 0 007 21h10a5 5 0 001.96-9.91A5 5 0 0015 3a3 3 0 00-6 0z"/></svg>,
    menu: <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={w} strokeLinecap="round"><line x1="3" y1="7" x2="21" y2="7"/><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="17" x2="21" y2="17"/></svg>,
    compose: <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={w} strokeLinecap="round" strokeLinejoin="round"><path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 013 3L7 19l-4 1 1-4z"/></svg>,
    refresh: <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={w} strokeLinecap="round" strokeLinejoin="round"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 11-2.12-9.36L23 10"/></svg>,
    text: <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth={w} strokeLinecap="round" strokeLinejoin="round"><polyline points="4 7 4 4 20 4 20 7"/><line x1="9" y1="20" x2="15" y2="20"/><line x1="12" y1="4" x2="12" y2="20"/></svg>,
    wifi: <svg width={s} height={s} viewBox="0 0 24 24" fill="none" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12.55a11 11 0 0114.08 0" stroke={c} strokeWidth={w}/><path d="M1.42 9a16 16 0 0121.16 0" stroke={c} strokeWidth={w}/><path d="M8.53 16.11a6 6 0 016.95 0" stroke={c} strokeWidth={w}/><circle cx="12" cy="20" r="1.2" fill={c}/></svg>,
    bat: <svg width={s} height={s} viewBox="0 0 25 13"><rect x=".5" y=".5" width="21" height="12" rx="3.5" fill="none" stroke={c} strokeWidth="1.1"/><rect x="2" y="2" width="16" height="9" rx="2" fill={c}/><path d="M23 4.5v4a2 2 0 000-4z" fill={c}/></svg>,
    sig: <svg width={s} height={s} viewBox="0 0 17 12"><rect x="0" y="8" width="3" height="4" rx="1" fill={c}/><rect x="4.5" y="5" width="3" height="7" rx="1" fill={c}/><rect x="9" y="2" width="3" height="10" rx="1" fill={c}/><rect x="13.5" y="0" width="3" height="12" rx="1" fill={c} opacity=".3"/></svg>,
  }
  return p[n] ?? <svg width={s} height={s} viewBox="0 0 24 24"/>
}

// ─── Primitives ───────────────────────────────────────────────────────────────
function StatusBar({ inv = false }) {
  const c = inv ? '#fff' : C.label
  return (
    <div className="sb">
      <div className="di" />
      <span className="sb-time" style={{ color: c }}>9:41</span>
      <div className="sb-icons">
        <Ic n="sig" s={18} c={c} />
        <Ic n="wifi" s={16} c={c} />
        <Ic n="bat" s={25} c={c} />
      </div>
    </div>
  )
}

function NavBar({ left, title, right, white = false }: {
  left?: ReactElement; title?: string; right?: ReactElement; white?: boolean
}) {
  return (
    <div className="nb" style={white ? { background: 'rgba(255,255,255,.9)' } : undefined}>
      <div style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 4 }}>{left}</div>
      {title && <span className="nb-title">{title}</span>}
      <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: 4 }}>{right}</div>
    </div>
  )
}

function TabBar({ active, onTab }: { active: number; onTab: (i: number) => void }) {
  const tabs = [
    { lbl: '文件', icon: 'doc' },
    { lbl: '日历', icon: 'cal' },
    { lbl: '提醒', icon: 'bell' },
  ]
  return (
    <div className="tabbar">
      {tabs.map((t, i) => (
        <div key={i} className="tab no-select" onClick={() => onTab(i)}>
          <Ic n={t.icon} s={26} c={i === active ? C.blue : C.label3} w={i === active ? 2 : 1.6} />
          <span className="tab-lbl" style={{ color: i === active ? C.blue : C.label3 }}>{t.lbl}</span>
        </div>
      ))}
    </div>
  )
}

// ─── Illustrations ────────────────────────────────────────────────────────────
function NoteIllustration() {
  return (
    <svg width="120" height="130" viewBox="0 0 120 130" fill="none">
      {/* Notebook body */}
      <rect x="18" y="18" width="84" height="94" rx="10" fill="#fff" filter="url(#ns)"/>
      <defs><filter id="ns" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="4" stdDeviation="6" floodOpacity=".12"/></filter></defs>
      {/* Spine lines */}
      <rect x="18" y="18" width="10" height="94" rx="5" fill="#E5E5EA"/>
      {/* Text lines */}
      <rect x="36" y="36" width="48" height="5" rx="2.5" fill="#D1D1D6"/>
      <rect x="36" y="48" width="38" height="5" rx="2.5" fill="#D1D1D6"/>
      <rect x="36" y="60" width="44" height="5" rx="2.5" fill="#D1D1D6"/>
      <rect x="36" y="72" width="32" height="5" rx="2.5" fill="#D1D1D6"/>
      {/* Mic badge */}
      <circle cx="86" cy="100" r="22" fill={C.blue} filter="url(#ms)"/>
      <defs><filter id="ms" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="6" stdDeviation="8" floodColor={C.blue} floodOpacity=".45"/></filter></defs>
      {/* Mic icon in badge */}
      <rect x="80" y="85" width="12" height="18" rx="6" fill="#fff"/>
      <path d="M76 99v2a10 10 0 0020 0v-2" stroke="#fff" strokeWidth="2" strokeLinecap="round" fill="none"/>
      <line x1="86" y1="111" x2="86" y2="115" stroke="#fff" strokeWidth="2" strokeLinecap="round"/>
      <line x1="82" y1="115" x2="90" y2="115" stroke="#fff" strokeWidth="2" strokeLinecap="round"/>
    </svg>
  )
}

function BellIllustration() {
  return (
    <svg width="80" height="80" viewBox="0 0 80 80" fill="none">
      <circle cx="40" cy="40" r="40" fill="rgba(142,142,147,.1)"/>
      <path d="M40 16a18 18 0 00-18 18c0 13-5 17-5 17h46s-5-4-5-17A18 18 0 0040 16z" stroke={C.label3} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" fill="none"/>
      <path d="M44 57a4 4 0 01-8 0" stroke={C.label3} strokeWidth="2" strokeLinecap="round" fill="none"/>
      <line x1="24" y1="24" x2="56" y2="56" stroke={C.label3} strokeWidth="2.5" strokeLinecap="round"/>
    </svg>
  )
}

// ─── Screen: File List ────────────────────────────────────────────────────────
interface FileListProps {
  onNote: () => void; onChat: () => void; onRecord: () => void; onNew: () => void
}
function FileList({ onNote, onChat, onRecord, onNew }: FileListProps) {
  const [exp, setExp] = useState<Record<string, boolean>>({ work: true, study: false, personal: false })
  const [swipedRow, setSwipedRow] = useState<string | null>(null)
  const [deletedRow, setDeletedRow] = useState<string | null>(null)

  const toggle = (k: string) => setExp(p => ({ ...p, [k]: !p[k] }))

  function FolderRow({ id, color, name, children }: { id: string; color: string; name: string; children?: ReactElement[] }) {
    return (
      <>
        <div
          className="lrow no-select"
          style={{ cursor: 'pointer' }}
          onClick={() => { toggle(id); setSwipedRow(null) }}
          onDoubleClick={() => setSwipedRow(swipedRow === id ? null : id)}
        >
          <div className="licon" style={{ background: color }}>
            <Ic n="folder" s={16} c="#fff" />
          </div>
          <span className="row-title" style={{ flex: 1, fontWeight: 500 }}>{name}</span>
          {!exp[id] && <span style={{ fontSize: 13, color: C.label3, marginRight: 4 }}>{children?.length ?? 0}项</span>}
          <div style={{ transform: exp[id] ? 'rotate(90deg)' : 'rotate(0)', transition: 'transform .2s', marginLeft: 4 }}>
            <Ic n="chevR" s={16} c={C.label3} />
          </div>
        </div>
        {/* Swipe actions */}
        {swipedRow === id && (
          <div style={{ display: 'flex', height: 0, overflow: 'visible', position: 'relative', zIndex: 5 }}>
            <div style={{ position: 'absolute', right: 0, top: -44, display: 'flex', height: 44 }}>
              <div className="action-rename" onClick={() => setSwipedRow(null)}>
                <Ic n="pencil" s={14} c="#fff" /><span>重命名</span>
              </div>
              <div className="action-delete" onClick={() => { setDeletedRow(id); setSwipedRow(null) }}>
                <Ic n="trash" s={14} c="#fff" /><span>删除</span>
              </div>
            </div>
          </div>
        )}
        {exp[id] && children}
      </>
    )
  }

  function NoteRow({ id, icon, iconColor, name, time, badge }: {
    id: string; icon: string; iconColor: string; name: string; time: string; badge?: string
  }) {
    if (id === deletedRow) return null
    return (
      <div
        className="lrow no-select"
        style={{ paddingLeft: 52, cursor: 'pointer', position: 'relative' }}
        onClick={onNote}
        onDoubleClick={() => setSwipedRow(swipedRow === id ? null : id)}
      >
        <div className="licon" style={{ background: iconColor }}>
          <Ic n={icon} s={14} c="#fff" />
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span className="row-title" style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{name}</span>
            {badge && <span className="badge" style={{ background: C.orange, color: '#fff' }}>{badge}</span>}
          </div>
          <span className="row-sub">{time}</span>
        </div>
        <Ic n="chevR" s={14} c={C.label3} />
        {swipedRow === id && (
          <div style={{ position: 'absolute', right: 0, top: 0, display: 'flex', height: '100%' }}>
            <div className="action-rename" onClick={(e) => { e.stopPropagation(); setSwipedRow(null) }}>
              <Ic n="pencil" s={13} c="#fff" /><span>重命名</span>
            </div>
            <div className="action-delete" onClick={(e) => { e.stopPropagation(); setDeletedRow(id); setSwipedRow(null) }}>
              <Ic n="trash" s={13} c="#fff" /><span>删除</span>
            </div>
          </div>
        )}
      </div>
    )
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: C.bg }}>
      <StatusBar />
      <NavBar
        right={
          <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
            <div style={{ width: 32, height: 32, borderRadius: 8, background: 'rgba(0,122,255,.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }} onClick={onChat}>
              <Ic n="chat" s={18} c={C.blue} />
            </div>
            <div style={{ width: 32, height: 32, borderRadius: 8, background: C.blue, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }} onClick={onNew}>
              <Ic n="plus" s={18} c="#fff" />
            </div>
          </div>
        }
      />
      <div style={{ padding: '4px 20px 2px' }}>
        <span className="lt">SayMark</span>
      </div>
      <div className="scroll" style={{ flex: 1, paddingTop: 4 }}>
        <div className="list">
          <div className="lcard">
            <FolderRow id="work" color={C.blue} name="工作">
              {[
                <NoteRow key="n1" id="n1" icon="doc" iconColor={C.label3} name="产品需求文档 v2.3" time="今天 09:15" />,
                <NoteRow key="n2" id="n2" icon="cal" iconColor={C.orange} name="Q3 评审会议" time="昨天 15:30" badge="日程" />,
                <NoteRow key="n3" id="n3" icon="doc" iconColor={C.label3} name="竞品分析报告" time="08月07日" />,
              ]}
            </FolderRow>
          </div>
          <div className="lcard">
            <FolderRow id="personal" color={C.orange} name="个人">
              {[
                <NoteRow key="n4" id="n4" icon="doc" iconColor={C.label3} name="买菜清单" time="今天 08:00" />,
                <NoteRow key="n5" id="n5" icon="doc" iconColor={C.label3} name="读书笔记 —《原子习惯》" time="08月05日" />,
              ]}
            </FolderRow>
          </div>
          <div className="lcard">
            <FolderRow id="study" color={C.green} name="学习">
              {[
                <NoteRow key="n6" id="n6" icon="doc" iconColor={C.label3} name="Swift 并发编程笔记" time="08月06日" />,
                <NoteRow key="n7" id="n7" icon="doc" iconColor={C.label3} name="机器学习基础概念" time="08月04日" />,
              ]}
            </FolderRow>
          </div>
        </div>
        <div style={{ height: 80 }} />
      </div>
      <div className="fab" onClick={onRecord}>
        <Ic n="mic" s={28} c="#fff" />
      </div>
    </div>
  )
}

// ─── Screen: File List Empty ──────────────────────────────────────────────────
function FileListEmpty({ onChat, onRecord, onNew }: Omit<FileListProps, 'onNote'>) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: C.bg }}>
      <StatusBar />
      <NavBar
        right={
          <div style={{ display: 'flex', gap: 12 }}>
            <span style={{ cursor: 'pointer' }} onClick={onChat}><Ic n="chat" s={20} c={C.blue} /></span>
            <span style={{ cursor: 'pointer' }} onClick={onNew}><Ic n="plus" s={20} c={C.blue} /></span>
          </div>
        }
      />
      <div style={{ padding: '4px 20px 2px' }}><span className="lt">SayMark</span></div>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 14, padding: '0 40px' }}>
        <NoteIllustration />
        <div style={{ textAlign: 'center', marginTop: 8 }}>
          <p style={{ margin: '0 0 6px', fontSize: 20, fontWeight: 600, color: C.label, letterSpacing: -.5 }}>还没有笔记</p>
          <p style={{ margin: 0, fontSize: 15, color: C.label3, lineHeight: 1.5, letterSpacing: -.24 }}>按住话筒开始说话吧，AI 会自动整理成结构化笔记</p>
        </div>
        <div
          style={{ marginTop: 12, padding: '12px 28px', background: C.blue, borderRadius: 14, cursor: 'pointer', boxShadow: `0 4px 16px ${C.blue}55` }}
          onClick={onRecord}
        >
          <span style={{ color: '#fff', fontSize: 16, fontWeight: 600 }}>开始录音</span>
        </div>
      </div>
      <div className="fab" onClick={onRecord}><Ic n="mic" s={28} c="#fff" /></div>
    </div>
  )
}

// ─── Screen: Calendar ─────────────────────────────────────────────────────────
const CAL_DATA = [
  [null,null,null,null,null,1,2],[3,4,5,6,7,8,9],
  [10,11,12,13,14,15,16],[17,18,19,20,21,22,23],
  [24,25,26,27,28,29,30],[31,null,null,null,null,null,null],
]
const EVENT_DAYS = new Set([3,5,9,12,15,19,21,26,28])
const EVENTS_9 = [
  { title: '产品评审会议', preview: '讨论 Q3 路线图，邀请设计、研发、运营', time: '10:00' },
  { title: '与李明一对一', preview: '月度进度同步，回顾 OKR 完成情况', time: '14:30' },
  { title: '用户访谈', preview: '访谈对象：王女士，了解产品使用感受', time: '16:00' },
]

function CalendarScreen({ onTab }: { onTab: (i: number) => void }) {
  const [sel, setSel] = useState(9)
  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: C.bg }}>
      <StatusBar />
      <NavBar title="日历" />
      <div style={{ background: '#fff', paddingBottom: 8 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '10px 20px 4px' }}>
          <Ic n="chevL" s={20} c={C.blue} />
          <span style={{ fontSize: 17, fontWeight: 600, letterSpacing: -.41 }}>2026年8月</span>
          <Ic n="chevR" s={20} c={C.blue} />
        </div>
        <div className="cal-grid" style={{ padding: '2px 12px 0' }}>
          {['一','二','三','四','五','六','日'].map((d,i) => (
            <div key={i} style={{ textAlign: 'center', fontSize: 11, color: C.label3, fontWeight: 500, padding: '4px 0' }}>{d}</div>
          ))}
        </div>
        <div style={{ padding: '0 12px 4px' }}>
          {CAL_DATA.map((week, wi) => (
            <div key={wi} className="cal-grid">
              {week.map((day, di) => {
                const today = day === 9
                const selected = day === sel
                const hasEv = day !== null && EVENT_DAYS.has(day)
                return (
                  <div key={di} className="cal-cell">
                    <div
                      className="cal-day no-select"
                      style={{
                        background: selected ? C.blue : 'transparent',
                        color: !day ? 'transparent' : selected ? '#fff' : today ? C.blue : C.label,
                        fontWeight: today ? 700 : 400,
                        border: today && !selected ? `2px solid ${C.blue}` : 'none',
                      }}
                      onClick={() => day && setSel(day)}
                    >{day ?? ''}</div>
                    {hasEv && <div style={{ width: 5, height: 5, borderRadius: '50%', background: C.orange }} />}
                  </div>
                )
              })}
            </div>
          ))}
        </div>
      </div>
      <div style={{ height: 1, background: 'rgba(60,60,67,.18)' }} />
      <div className="scroll" style={{ flex: 1, background: C.bg }}>
        <div style={{ padding: '12px 20px 6px' }}>
          <span style={{ fontSize: 15, fontWeight: 600, color: C.label }}>{sel}月{sel}日</span>
        </div>
        <div className="list">
          <div className="lcard">
            {EVENTS_9.map((ev, i) => (
              <div key={i} className="lrow" style={{ alignItems: 'flex-start', paddingTop: 13, paddingBottom: 13 }}>
                <div style={{ width: 4, height: 44, background: C.blue, borderRadius: 2, marginRight: 12, marginTop: 2, flexShrink: 0 }} />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                    <span style={{ fontSize: 16, fontWeight: 500, letterSpacing: -.32 }}>{ev.title}</span>
                    <span style={{ fontSize: 13, color: C.blue, marginLeft: 8, flexShrink: 0, fontWeight: 500 }}>{ev.time}</span>
                  </div>
                  <p style={{ margin: '3px 0 0', fontSize: 13, color: C.label3, lineHeight: 1.35 }}>{ev.preview}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
        <div style={{ height: 20 }} />
      </div>
      <TabBar active={1} onTab={onTab} />
    </div>
  )
}

// ─── Screen: Reminders ────────────────────────────────────────────────────────
const REMINDERS = [
  { id: 'r1', title: '产品评审会议', dt: '2026-08-09 10:00', adv: '提前30分钟' },
  { id: 'r2', title: '与李明一对一', dt: '2026-08-09 14:30', adv: '提前15分钟' },
  { id: 'r3', title: '提交季度报告', dt: '2026-08-11 09:00', adv: '提前1小时' },
  { id: 'r4', title: 'Figma 设计评审', dt: '2026-08-12 15:00', adv: '提前30分钟' },
]

function RemindersScreen({ onTab, empty = false }: { onTab: (i: number) => void; empty?: boolean }) {
  const [cancelled, setCancelled] = useState<Set<string>>(new Set())
  const items = REMINDERS.filter(r => !cancelled.has(r.id))
  const isEmpty = empty || items.length === 0

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: C.bg }}>
      <StatusBar />
      <NavBar
        title="提醒"
        right={!isEmpty ? <Ic n="refresh" s={20} c={C.blue} /> : undefined}
      />
      {isEmpty ? (
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 14, padding: 40 }}>
          <BellIllustration />
          <div style={{ textAlign: 'center', marginTop: 4 }}>
            <p style={{ margin: '0 0 6px', fontSize: 20, fontWeight: 600 }}>暂无提醒</p>
            <p style={{ margin: 0, fontSize: 15, color: C.label3, lineHeight: 1.5 }}>还没有设置任何日程提醒</p>
          </div>
        </div>
      ) : (
        <div className="scroll" style={{ flex: 1, paddingTop: 16 }}>
          <div className="list">
            <div className="lcard">
              {items.map((r, i) => (
                <div key={r.id} className="lrow" style={{ alignItems: 'flex-start', paddingTop: 13, paddingBottom: 13 }}>
                  <div style={{ marginRight: 12, marginTop: 1 }}>
                    <Ic n="bell" s={22} c={C.orange} />
                  </div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <span style={{ fontSize: 16, fontWeight: 500, letterSpacing: -.32, display: 'block' }}>{r.title}</span>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 4, marginTop: 4 }}>
                      <Ic n="cal" s={11} c={C.label3} />
                      <span style={{ fontSize: 12, color: C.label3 }}>{r.dt}</span>
                    </div>
                    <span className="badge" style={{ background: 'rgba(255,149,0,.12)', color: C.orange, marginTop: 5, fontSize: 12 }}>{r.adv}</span>
                  </div>
                  <div style={{ cursor: 'pointer', padding: 4 }} onClick={() => setCancelled(s => new Set([...s, r.id]))}>
                    <Ic n="bell-off" s={18} c={C.label3} />
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
      <TabBar active={2} onTab={onTab} />
    </div>
  )
}

// ─── Screen: Note Detail ──────────────────────────────────────────────────────
function NoteDetail({ onBack, onRecord }: { onBack: () => void; onRecord: () => void }) {
  const [editMode, setEditMode] = useState(false)
  const [loading, setLoading] = useState(false)

  function handleVoiceEdit() {
    setLoading(true)
    setTimeout(() => setLoading(false), 2200)
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: editMode ? C.bg : '#fff' }}>
      <StatusBar />
      <NavBar
        left={
          <div style={{ display: 'flex', alignItems: 'center', gap: 2, cursor: 'pointer' }} onClick={onBack}>
            <Ic n="chevL" s={20} c={C.blue} />
            <span className="nb-btn">文件</span>
          </div>
        }
        title={editMode ? '编辑' : '产品需求文档'}
        right={editMode
          ? <span className="nb-btn-bold" onClick={() => setEditMode(false)}>保存</span>
          : <span className="nb-btn" onClick={() => setEditMode(true)}><Ic n="pencil" s={18} c={C.blue} /></span>
        }
        white={!editMode}
      />

      {editMode ? (
        <div style={{ flex: 1, padding: '12px 16px', display: 'flex', flexDirection: 'column', gap: 12 }}>
          <div style={{ border: `1px solid rgba(60,60,67,.22)`, borderRadius: 10, padding: '10px 12px', fontSize: 17, fontWeight: 500, background: '#fff' }}>
            产品需求文档 v2.3
          </div>
          <textarea
            readOnly
            style={{
              flex: 1, border: `1px solid rgba(60,60,67,.22)`, borderRadius: 10, padding: '10px 12px',
              fontSize: 14, lineHeight: 1.7, fontFamily: 'monospace', resize: 'none',
              background: '#fff', color: C.label, minHeight: 320,
            }}
            defaultValue={`# 产品需求文档 v2.3\n\n## 背景与目标\n本文档描述 SayMark 2.0 核心功能需求，旨在提升用户语音记录效率。\n\n## 核心功能\n\n### 1. 语音转录优化\n- 支持中英文混合识别\n- 实时转录延迟 <500ms\n- 离线模式基础支持\n\n### 2. AI 结构化处理\n- 自动提取关键信息\n- 生成摘要与标签\n\n## 时间节点\n1. 需求冻结：2026-08-15\n2. 设计完成：2026-08-25\n3. 开发上线：2026-09-10`}
          />
        </div>
      ) : (
        <div className="scroll" style={{ flex: 1, background: '#fff', padding: '16px 20px 0' }}>
          <p style={{ margin: '0 0 8px', fontSize: 26, fontWeight: 700, letterSpacing: .3, color: C.label }}>产品需求文档 v2.3</p>
          <p style={{ margin: '0 0 14px', fontSize: 16, fontWeight: 700, letterSpacing: -.32, color: C.label }}>背景与目标</p>
          <p style={{ margin: '0 0 12px', fontSize: 16, lineHeight: 1.55, letterSpacing: -.32, color: C.label }}>
            本文档描述 SayMark 2.0 版本的核心功能需求，旨在提升用户的语音记录效率与体验。
          </p>
          <div style={{ borderLeft: '3px solid rgba(60,60,67,.25)', paddingLeft: 12, margin: '12px 0', fontStyle: 'italic', color: C.label3, fontSize: 15, lineHeight: 1.5 }}>
            好的工具应该像空气一样，用的时候感觉不到它的存在。
          </div>
          <p style={{ margin: '12px 0 6px', fontSize: 17, fontWeight: 700, color: C.label }}>核心功能</p>
          <p style={{ margin: '8px 0 4px', fontSize: 15, fontWeight: 600, color: C.label }}>1. 语音转录优化</p>
          {['支持中英文混合识别', '实时转录延迟 &lt;500ms', '离线模式基础支持'].map((t, i) => (
            <p key={i} style={{ margin: '3px 0', fontSize: 15, lineHeight: 1.5, color: C.label, paddingLeft: 12 }}>• {t}</p>
          ))}
          <p style={{ margin: '10px 0 4px', fontSize: 15, fontWeight: 600, color: C.label }}>2. AI 结构化处理</p>
          {['自动提取关键信息', '生成摘要与标签', '智能分类到文件夹'].map((t, i) => (
            <p key={i} style={{ margin: '3px 0', fontSize: 15, lineHeight: 1.5, color: C.label, paddingLeft: 12 }}>• {t}</p>
          ))}
          <p style={{ margin: '12px 0 6px', fontSize: 17, fontWeight: 700, color: C.label }}>时间节点</p>
          {['需求冻结：2026-08-15', '设计完成：2026-08-25', '开发上线：2026-09-10'].map((t, i) => (
            <div key={i} style={{ display: 'flex', gap: 10, margin: '4px 0', fontSize: 15, color: C.label }}>
              <span style={{ fontWeight: 600, minWidth: 20 }}>{i + 1}.</span><span>{t}</span>
            </div>
          ))}
          <div style={{ height: 80 }} />
        </div>
      )}

      {/* Bottom toolbar */}
      <div style={{ height: 54, background: editMode ? C.bg : 'rgba(242,242,247,.95)', borderTop: `.5px solid ${C.sep}`, display: 'flex', alignItems: 'center', justifyContent: 'space-around' }}>
        <div style={{ opacity: .45, cursor: 'pointer' }}><Ic n="undo" s={22} c={C.label3} /></div>
        <div
          style={{ width: 46, height: 46, borderRadius: 23, background: C.blue, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', boxShadow: `0 2px 10px ${C.blue}60` }}
          onClick={handleVoiceEdit}
        >
          <Ic n="mic" s={22} c="#fff" />
        </div>
        <div style={{ cursor: 'pointer' }} onClick={() => setEditMode(!editMode)}><Ic n="pencil" s={22} c={C.blue} /></div>
      </div>
      <div style={{ height: 34, background: editMode ? C.bg : 'rgba(242,242,247,.95)' }} />

      {/* Voice edit loading overlay */}
      {loading && (
        <div style={{ position: 'absolute', inset: 0, background: 'rgba(255,255,255,.82)', backdropFilter: 'blur(4px)', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 14, zIndex: 50 }}>
          <div style={{ width: 48, height: 48, border: `3px solid ${C.blue}`, borderTopColor: 'transparent', borderRadius: '50%', animation: 'spin .8s linear infinite' }} />
          <style>{`@keyframes spin{to{transform:rotate(360deg)}}`}</style>
          <span style={{ fontSize: 16, color: C.label3, fontWeight: 500 }}>正在调整笔记...</span>
        </div>
      )}
    </div>
  )
}

// ─── Screen: AI Chat ──────────────────────────────────────────────────────────
function ChatScreen({ onClose }: { onClose: () => void }) {
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const [thinkExpanded, setThinkExpanded] = useState(false)
  const [input, setInput] = useState('')
  const [textEditOpen, setTextEditOpen] = useState(false)

  const histConvos = [
    { title: '创建日历事件', preview: '已为你添加产品路线图评审...' },
    { title: '整理工作笔记', preview: '已将三篇笔记移动到工作文件夹' },
    { title: '查询本周日程', preview: '本周共有5个日程，最近的是...' },
  ]

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: '#fff', position: 'relative' }}>
      <StatusBar />
      <NavBar
        white
        left={
          <div style={{ cursor: 'pointer' }} onClick={() => setSidebarOpen(true)}>
            <Ic n="menu" s={22} c={C.blue} />
          </div>
        }
        title="AI 助手"
        right={
          <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
            <div style={{ cursor: 'pointer' }}><Ic n="compose" s={20} c={C.blue} /></div>
            <div style={{ cursor: 'pointer' }} onClick={onClose}><Ic n="x" s={20} c={C.label3} /></div>
          </div>
        }
      />

      <div className="scroll" style={{ flex: 1, padding: '16px 16px 0', display: 'flex', flexDirection: 'column', gap: 12 }}>
        {/* User */}
        <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
          <div className="bubble bubble-u">帮我把明天下午三点的会议记到日历里，主题是「产品路线图评审」</div>
        </div>

        {/* Thinking card */}
        <div style={{ display: 'flex' }}>
          <div className="think-card" style={{ cursor: 'pointer' }} onClick={() => setThinkExpanded(p => !p)}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <Ic n="brain" s={18} c={C.orange} />
              <span style={{ fontSize: 14, fontWeight: 600, color: C.orange, flex: 1 }}>
                {thinkExpanded ? '正在处理...' : '处理完成（3步）'}
              </span>
              <span className="badge" style={{ background: 'rgba(255,149,0,.14)', color: C.orange, fontSize: 11 }}>3步</span>
              <div style={{ transform: thinkExpanded ? 'rotate(180deg)' : 'none', transition: 'transform .2s' }}>
                <Ic n="chevD" s={14} c={C.orange} />
              </div>
            </div>
            {thinkExpanded && (
              <div style={{ marginTop: 10, display: 'flex', flexDirection: 'column', gap: 6 }}>
                {['解析时间：明天（2026-08-10）15:00', '识别意图：创建日历事件', '调用日历写入 API → 成功'].map((s, i) => (
                  <div key={i} style={{ display: 'flex', gap: 7, alignItems: 'flex-start' }}>
                    <div style={{ width: 5, height: 5, borderRadius: '50%', background: C.orange, marginTop: 5, flexShrink: 0, opacity: .7 }} />
                    <span style={{ fontSize: 12, color: `rgba(255,149,0,.85)`, lineHeight: 1.4 }}>{s}</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* AI */}
        <div style={{ display: 'flex' }}>
          <div className="bubble bubble-ai">
            已为你添加日历事件：<br />
            <span style={{ fontWeight: 700 }}>📅 产品路线图评审</span><br />
            2026年8月10日 15:00–16:00<br />
            <span style={{ color: C.blue, fontSize: 14 }}>→ 查看日历</span>
          </div>
        </div>

        {/* User 2 */}
        <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
          <div className="bubble bubble-u">再帮我设置提前30分钟的提醒</div>
        </div>
        <div style={{ display: 'flex' }}>
          <div className="bubble bubble-ai">好的，已设置 14:30 的提醒，届时会收到通知 🔔</div>
        </div>

        {/* Streaming dots */}
        <div style={{ display: 'flex', gap: 4, padding: '4px 8px', alignItems: 'center' }}>
          <div className="tdot" /><div className="tdot" /><div className="tdot" />
        </div>
        <div style={{ height: 24 }} />
      </div>

      {/* Input bar */}
      <div style={{ display: 'flex', alignItems: 'flex-end', gap: 8, padding: '8px 12px 28px', borderTop: `.5px solid ${C.sep}`, background: '#fff' }}>
        <div style={{ width: 36, height: 36, borderRadius: 18, background: C.blue, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, cursor: 'pointer' }}
          onClick={() => setTextEditOpen(true)}>
          <Ic n="mic" s={18} c="#fff" />
        </div>
        <div style={{ flex: 1, border: `1px solid rgba(60,60,67,.22)`, borderRadius: 20, padding: '8px 14px', fontSize: 16, color: input ? C.label : C.label3, background: C.bg, minHeight: 36, display: 'flex', alignItems: 'center' }}>
          {input || '继续说话或输入...'}
        </div>
        {input && (
          <div style={{ width: 36, height: 36, borderRadius: 18, background: C.blue, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
            <Ic n="up" s={18} c="#fff" />
          </div>
        )}
      </div>

      {/* History sidebar */}
      {sidebarOpen && (
        <>
          <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,.4)', backdropFilter: 'blur(2px)', zIndex: 40 }} onClick={() => setSidebarOpen(false)} />
          <div className="slide-panel" style={{ left: 0, width: '75%', top: 0 }}>
            <div style={{ height: 59 }} />
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '14px 20px 10px' }}>
              <span style={{ fontSize: 18, fontWeight: 700 }}>历史会话</span>
              <Ic n="compose" s={20} c={C.blue} />
            </div>
            {histConvos.map((c, i) => (
              <div key={i} style={{ padding: '12px 20px', borderBottom: `.5px solid ${C.sep}`, cursor: 'pointer' }} onClick={() => setSidebarOpen(false)}>
                <div style={{ fontSize: 15, fontWeight: 500, marginBottom: 3 }}>{c.title}</div>
                <div style={{ fontSize: 13, color: C.label3, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{c.preview}</div>
              </div>
            ))}
          </div>
        </>
      )}

      {/* Text edit panel */}
      {textEditOpen && (
        <>
          <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,.3)', backdropFilter: 'blur(3px)', zIndex: 70 }} />
          <div className="sheet" style={{ zIndex: 80 }}>
            <div className="sheet-handle" />
            <div style={{ display: 'flex', alignItems: 'center', padding: '10px 16px 14px', gap: 8 }}>
              <div style={{ width: 32, height: 32, borderRadius: 16, background: 'rgba(120,120,128,.16)', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }} onClick={() => setTextEditOpen(false)}>
                <Ic n="x" s={14} c={C.label3} />
              </div>
              <span style={{ flex: 1, textAlign: 'center', fontSize: 17, fontWeight: 700 }}>确认文字</span>
              <div style={{ width: 32, height: 32, borderRadius: 16, background: C.green, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }} onClick={() => setTextEditOpen(false)}>
                <Ic n="check" s={16} c="#fff" />
              </div>
            </div>
            <div style={{ margin: '0 20px 20px', background: 'rgba(0,0,0,.04)', borderRadius: 10, padding: '12px 14px', minHeight: 110 }}>
              <p style={{ margin: 0, fontSize: 16, lineHeight: 1.6, color: C.label }}>
                明天下午三点产品路线图评审会议，记到日历，提前30分钟提醒。
              </p>
            </div>
          </div>
        </>
      )}
    </div>
  )
}

// ─── Screen: Recording Overlay ────────────────────────────────────────────────
type RecZone = 'normal' | 'cancel' | 'text'
function RecordingOverlay({ zone, onClose }: { zone: RecZone; onClose: () => void }) {
  const zoneConfig = {
    normal: { bg: 'rgba(0,0,0,.58)', color: '#fff', label: '松开 发送', icon: null },
    cancel: { bg: 'rgba(0,0,0,.58)', color: C.red, label: '松开 取消', icon: 'x' },
    text: { bg: 'rgba(0,0,0,.58)', color: C.green, label: '松开 转文字', icon: 'text' },
  }
  const conf = zoneConfig[zone]

  return (
    <div className="rec-overlay" onClick={onClose}>
      {zone === 'normal' && (
        <>
          <div style={{ display: 'flex', gap: 7, alignItems: 'center', marginBottom: 32 }}>
            <div className="wbar" /><div className="wbar" /><div className="wbar" />
            <div className="wbar" /><div className="wbar" /><div className="wbar" />
          </div>
          <span style={{ fontSize: 26, fontWeight: 700, color: '#fff', letterSpacing: -.5, marginBottom: 14 }}>松开 发送</span>
          <p style={{ margin: '0 0 60px', fontSize: 15, color: 'rgba(255,255,255,.75)', textAlign: 'center', maxWidth: 280, lineHeight: 1.5 }}>
            明天下午三点产品路线图评审...
          </p>
          <div style={{ position: 'absolute', bottom: 116, left: 0, right: 0, display: 'flex', justifyContent: 'space-between', padding: '0 40px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
              <Ic n="x" s={12} c="rgba(255,255,255,.6)" />
              <span style={{ fontSize: 11.5, color: 'rgba(255,255,255,.6)' }}>松开取消</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
              <span style={{ fontSize: 11.5, color: 'rgba(255,255,255,.6)' }}>转文字</span>
              <Ic n="text" s={12} c="rgba(255,255,255,.6)" />
            </div>
          </div>
        </>
      )}
      {zone === 'cancel' && (
        <div style={{ background: 'rgba(255,59,48,.18)', borderRadius: 28, padding: '48px 64px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 18 }}>
          <div style={{ width: 88, height: 88, borderRadius: 44, background: C.red, display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: `0 0 0 14px rgba(255,59,48,.2)` }}>
            <Ic n="x" s={44} c="#fff" />
          </div>
          <span style={{ fontSize: 28, fontWeight: 700, color: C.red, letterSpacing: -.5 }}>松开 取消</span>
        </div>
      )}
      {zone === 'text' && (
        <div style={{ background: 'rgba(52,199,89,.18)', borderRadius: 28, padding: '48px 64px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 18 }}>
          <div style={{ width: 88, height: 88, borderRadius: 44, background: C.green, display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: `0 0 0 14px rgba(52,199,89,.2)` }}>
            <Ic n="text" s={44} c="#fff" />
          </div>
          <span style={{ fontSize: 28, fontWeight: 700, color: C.green, letterSpacing: -.5 }}>松开 转文字</span>
        </div>
      )}
      {/* Mic at bottom */}
      <div style={{
        position: 'absolute', bottom: 108, left: '50%', transform: 'translateX(-50%)',
        width: 72, height: 72, borderRadius: 36,
        background: zone === 'cancel' ? C.red : zone === 'text' ? C.green : C.blue,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        boxShadow: `0 0 0 10px ${zone === 'cancel' ? 'rgba(255,59,48,.25)' : zone === 'text' ? 'rgba(52,199,89,.25)' : 'rgba(0,122,255,.25)'}`
      }}>
        <Ic n="mic" s={32} c="#fff" />
      </div>
    </div>
  )
}

// ─── Screen: Voice Input Sheet ────────────────────────────────────────────────
function VoiceInputSheet({ onClose }: { onClose: () => void }) {
  const [result, setResult] = useState<'none' | 'success' | 'fail'>('none')
  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: C.bg }}>
      <StatusBar />
      <NavBar
        left={<span className="nb-btn" onClick={onClose}>关闭</span>}
        title="语音输入"
      />
      <div style={{ flex: 1, padding: '20px 16px', display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start' }}>
          <div style={{ flex: 1, background: '#fff', borderRadius: 12, border: `1px solid rgba(60,60,67,.2)`, padding: '12px 14px', fontSize: 16, color: C.label, lineHeight: 1.55, minHeight: 100 }}>
            明天下午3点面试，地点在字节跳动上海办公室，需要提前准备个人介绍和作品集
          </div>
          <div style={{ width: 44, height: 44, borderRadius: 22, background: C.blue, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, boxShadow: `0 4px 14px ${C.blue}55`, cursor: 'pointer' }}>
            <Ic n="mic" s={22} c="#fff" />
          </div>
        </div>

        <div style={{ background: 'rgba(142,142,147,.1)', borderRadius: 10, padding: '10px 14px' }}>
          <span style={{ fontSize: 13, color: C.label3, lineHeight: 1.5 }}>例：明天下午3点面试 / 定位到工作文件夹 / 把这条笔记移到个人</span>
        </div>

        <div
          style={{ background: C.blue, borderRadius: 12, height: 52, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', boxShadow: `0 4px 16px ${C.blue}44` }}
          onClick={() => setResult('success')}
        >
          <span style={{ color: '#fff', fontSize: 17, fontWeight: 600 }}>发送</span>
        </div>

        {result === 'success' && (
          <div style={{ background: 'rgba(52,199,89,.08)', border: `1px solid rgba(52,199,89,.25)`, borderRadius: 12, padding: '14px 16px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 7 }}>
              <div style={{ width: 24, height: 24, borderRadius: 12, background: C.green, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Ic n="check" s={14} c="#fff" />
              </div>
              <span style={{ fontSize: 15, fontWeight: 600, color: C.green }}>成功</span>
            </div>
            <p style={{ margin: 0, fontSize: 14, color: C.label, lineHeight: 1.5 }}>
              已创建日历事件「面试」，时间 2026-08-10 15:00，并设置提前30分钟提醒。
            </p>
          </div>
        )}
        {result === 'fail' && (
          <div style={{ background: 'rgba(255,59,48,.06)', border: `1px solid rgba(255,59,48,.2)`, borderRadius: 12, padding: '14px 16px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 7 }}>
              <div style={{ width: 24, height: 24, borderRadius: 12, background: C.red, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Ic n="x" s={12} c="#fff" />
              </div>
              <span style={{ fontSize: 15, fontWeight: 600, color: C.red }}>失败</span>
            </div>
            <p style={{ margin: 0, fontSize: 14, color: C.label3, lineHeight: 1.5 }}>未能识别目标文件夹，请重新描述或手动选择位置。</p>
          </div>
        )}

        <div style={{ display: 'flex', gap: 10 }}>
          <div style={{ flex: 1, padding: '10px 0', textAlign: 'center', background: 'rgba(52,199,89,.1)', borderRadius: 10, cursor: 'pointer', color: C.green, fontSize: 14, fontWeight: 600 }} onClick={() => setResult('success')}>显示成功</div>
          <div style={{ flex: 1, padding: '10px 0', textAlign: 'center', background: 'rgba(255,59,48,.1)', borderRadius: 10, cursor: 'pointer', color: C.red, fontSize: 14, fontWeight: 600 }} onClick={() => setResult('fail')}>显示失败</div>
        </div>
      </div>
    </div>
  )
}

// ─── Screen: New Item / Rename Sheets ─────────────────────────────────────────
function NewItemSheet({ onClose }: { onClose: () => void }) {
  const [type, setType] = useState<'folder' | 'note'>('folder')
  const [name, setName] = useState('新工作文件夹')
  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: C.bg }}>
      <StatusBar />
      <NavBar
        left={<span className="nb-btn" onClick={onClose}>取消</span>}
        title="新建"
        right={<span style={{ fontSize: 17, fontWeight: 600, color: name ? C.blue : 'rgba(0,122,255,.35)', cursor: name ? 'pointer' : 'default' }}>创建</span>}
      />
      <div style={{ padding: '20px 0' }}>
        <div className="list">
          <div style={{ fontSize: 13, color: C.label3, textTransform: 'uppercase', letterSpacing: '.065em', padding: '0 4px 6px', marginBottom: 0 }}>类型</div>
          <div className="lcard">
            {[['folder', '文件夹', C.blue], ['doc', '笔记', C.label3]].map(([id, lbl, color]) => (
              <div key={id} className="lrow" style={{ cursor: 'pointer' }} onClick={() => setType(id as 'folder' | 'note')}>
                <div className="licon" style={{ background: color as string }}><Ic n={id as string} s={15} c="#fff" /></div>
                <span className="row-title" style={{ flex: 1 }}>{lbl}</span>
                {type === id && <Ic n="check" s={20} c={C.blue} />}
              </div>
            ))}
          </div>
          <div style={{ fontSize: 13, color: C.label3, textTransform: 'uppercase', letterSpacing: '.065em', padding: '14px 4px 6px' }}>名称</div>
          <div className="lcard">
            <div className="lrow">
              <input
                value={name}
                onChange={e => setName(e.target.value)}
                style={{ flex: 1, border: 'none', background: 'transparent', fontSize: 17, color: C.label, letterSpacing: '-.41px' }}
                placeholder="输入名称"
              />
              {name && <div style={{ width: 18, height: 18, borderRadius: 9, background: C.label3, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }} onClick={() => setName('')}><Ic n="x" s={10} c="#fff" /></div>}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

// ─── Screen: Delete Dialog ────────────────────────────────────────────────────
function DeleteDialog({ onClose }: { onClose: () => void }) {
  return (
    <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,.42)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 90, padding: 20 }}>
      <div style={{ background: 'rgba(242,242,247,.98)', backdropFilter: 'blur(40px)', borderRadius: 14, width: 270, overflow: 'hidden', boxShadow: '0 24px 64px rgba(0,0,0,.45)' }}>
        <div style={{ padding: '22px 16px 16px', textAlign: 'center' }}>
          <p style={{ margin: '0 0 8px', fontSize: 17, fontWeight: 600, letterSpacing: -.41 }}>确定删除文件夹？</p>
          <p style={{ margin: 0, fontSize: 13, color: C.label3, lineHeight: 1.5, letterSpacing: -.08 }}>
            将删除「工作」及其内部 5 个文件。此操作不可撤销。
          </p>
        </div>
        <div style={{ borderTop: `.5px solid ${C.sep}`, display: 'flex' }}>
          <div style={{ flex: 1, padding: '14px 0', textAlign: 'center', borderRight: `.5px solid ${C.sep}`, cursor: 'pointer' }} onClick={onClose}>
            <span style={{ fontSize: 17, color: C.blue }}>取消</span>
          </div>
          <div style={{ flex: 1, padding: '14px 0', textAlign: 'center', cursor: 'pointer' }} onClick={onClose}>
            <span style={{ fontSize: 17, color: C.red, fontWeight: 600 }}>删除</span>
          </div>
        </div>
      </div>
    </div>
  )
}

// ─── Interactive Phone Demo ───────────────────────────────────────────────────
type Screen = 'files' | 'files-empty' | 'calendar' | 'reminders' | 'reminders-empty' | 'note' | 'chat' | 'voice-input' | 'new-item'

function InteractiveDemo() {
  const [screen, setScreen] = useState<Screen>('files')
  const [tab, setTab] = useState(0)
  const [recZone, setRecZone] = useState<RecZone | null>(null)
  const [showDelete, setShowDelete] = useState(false)
  const [populated, setPopulated] = useState(true)

  function onTab(i: number) {
    setTab(i)
    if (i === 0) setScreen('files')
    if (i === 1) setScreen('calendar')
    if (i === 2) setScreen('reminders')
  }

  const tabScreens: Screen[] = ['files', 'calendar', 'reminders']

  function renderScreen() {
    switch (screen) {
      case 'files':
      case 'files-empty':
        return populated
          ? <FileList onNote={() => setScreen('note')} onChat={() => setScreen('chat')} onRecord={() => setRecZone('normal')} onNew={() => setScreen('new-item')} />
          : <FileListEmpty onChat={() => setScreen('chat')} onRecord={() => setRecZone('normal')} onNew={() => setScreen('new-item')} />
      case 'calendar': return <CalendarScreen onTab={onTab} />
      case 'reminders': return <RemindersScreen onTab={onTab} />
      case 'reminders-empty': return <RemindersScreen onTab={onTab} empty />
      case 'note': return <NoteDetail onBack={() => { setScreen('files'); setTab(0) }} onRecord={() => setRecZone('normal')} />
      case 'chat': return <ChatScreen onClose={() => { setScreen(tabScreens[tab]); }} />
      case 'voice-input': return <VoiceInputSheet onClose={() => setScreen(tabScreens[tab])} />
      case 'new-item': return <NewItemSheet onClose={() => setScreen(tabScreens[tab])} />
    }
  }

  // Screens that don't show the standard tab bar (they manage their own)
  const noTab = new Set(['note', 'chat', 'voice-input', 'new-item', 'files', 'files-empty'])

  const showTabBar = !noTab.has(screen) || false

  return (
    <div className="demo-wrap">
      <div style={{ position: 'relative' }}>
        <div className="shell">
          <div style={{ height: '100%', display: 'flex', flexDirection: 'column', position: 'relative' }}>
            {renderScreen()}
            {/* Show tabbar under files screens */}
            {(screen === 'files' || screen === 'files-empty') && (
              <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 5 }}>
                <TabBar active={0} onTab={onTab} />
              </div>
            )}
            {/* Recording overlay */}
            {recZone && <RecordingOverlay zone={recZone} onClose={() => setRecZone(null)} />}
            {/* Delete dialog */}
            {showDelete && <DeleteDialog onClose={() => setShowDelete(false)} />}
          </div>
        </div>
      </div>

      <div className="demo-info">
        <div className="demo-tag">Interactive Prototype · iPhone 15 Pro</div>
        <h1 className="demo-title">SayMark UI Kit</h1>
        <p className="demo-sub">点击下方按钮切换屏幕状态，体验完整交互流程。文件列表中的文件夹可以展开/折叠，思考卡片可以展开/收起。</p>

        <div style={{ marginBottom: 12 }}>
          <div className="gal-label" style={{ marginBottom: 8 }}>主界面</div>
          <div className="demo-ctrl">
            {([
              ['files', '文件列表（有数据）'],
              ['files-empty', '文件列表（空）'],
              ['calendar', '日历'],
              ['reminders', '提醒（有数据）'],
              ['reminders-empty', '提醒（空）'],
            ] as [Screen, string][]).map(([s, lbl]) => (
              <div key={s} className={`ctrl-btn ${screen === s ? 'active' : ''}`} onClick={() => { setScreen(s); const i = s.startsWith('files') ? 0 : s.startsWith('cal') ? 1 : 2; setTab(s.includes('empty') && !s.startsWith('rem') ? 0 : i) }}>
                {lbl}
              </div>
            ))}
          </div>
        </div>

        <div style={{ marginBottom: 12 }}>
          <div className="gal-label" style={{ marginBottom: 8 }}>导航流程</div>
          <div className="demo-ctrl">
            {([
              ['note', '笔记详情'],
              ['chat', 'AI 对话'],
              ['voice-input', '语音输入'],
              ['new-item', '新建条目'],
            ] as [Screen, string][]).map(([s, lbl]) => (
              <div key={s} className={`ctrl-btn ${screen === s ? 'active' : ''}`} onClick={() => setScreen(s)}>{lbl}</div>
            ))}
          </div>
        </div>

        <div style={{ marginBottom: 12 }}>
          <div className="gal-label" style={{ marginBottom: 8 }}>叠加层</div>
          <div className="demo-ctrl">
            {([
              [() => setRecZone('normal'), '录音 - 正常'],
              [() => setRecZone('cancel'), '录音 - 取消区'],
              [() => setRecZone('text'), '录音 - 转文字'],
              [() => setShowDelete(true), '删除确认'],
            ] as [() => void, string][]).map(([fn, lbl], i) => (
              <div key={i} className="ctrl-btn" onClick={fn}>{lbl}</div>
            ))}
          </div>
        </div>

        <div>
          <div className="gal-label" style={{ marginBottom: 8 }}>文件列表</div>
          <div className="demo-ctrl">
            <div className={`ctrl-btn ${populated ? 'active' : ''}`} onClick={() => setPopulated(true)}>显示有数据</div>
            <div className={`ctrl-btn ${!populated ? 'active' : ''}`} onClick={() => setPopulated(false)}>显示空状态</div>
          </div>
        </div>
      </div>
    </div>
  )
}

// ─── Static Gallery Frames ────────────────────────────────────────────────────
function Frame({ label, children }: { label: string; children: ReactElement }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
      <div className="shell">{children}</div>
      <div className="frame-cap">{label}</div>
    </div>
  )
}

function GallerySection({ title, children }: { title: string; children: ReactElement }) {
  return (
    <div className="gal-section">
      <div className="gal-label">{title}</div>
      <div className="gal-row">{children}</div>
    </div>
  )
}

// Minimal static wrappers (no interaction handlers needed for gallery)
function StaticFilesPopulated() {
  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', background: C.bg }}>
      <FileList onNote={() => {}} onChat={() => {}} onRecord={() => {}} onNew={() => {}} />
    </div>
  )
}

function StaticFilesEmpty() {
  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', background: C.bg }}>
      <FileListEmpty onChat={() => {}} onRecord={() => {}} onNew={() => {}} />
    </div>
  )
}

function StaticNote() {
  return <NoteDetail onBack={() => {}} onRecord={() => {}} />
}
function StaticNoteEdit() {
  const [, setE] = useState(true)
  return <NoteDetail onBack={() => {}} onRecord={() => {}} />
}
function StaticVoiceInput() {
  return <VoiceInputSheet onClose={() => {}} />
}
function StaticNewItem() {
  return <NewItemSheet onClose={() => {}} />
}

// Rename sheet (standalone)
function RenameSheet({ onClose }: { onClose: () => void }) {
  const [name, setName] = useState('工作项目 2026')
  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: C.bg }}>
      <StatusBar />
      <NavBar
        left={<span className="nb-btn" onClick={onClose}>取消</span>}
        title="重命名"
        right={<span style={{ fontSize: 17, fontWeight: 600, color: name ? C.blue : 'rgba(0,122,255,.35)' }}>确定</span>}
      />
      <div style={{ padding: '20px 0' }}>
        <div className="list">
          <div style={{ fontSize: 13, color: C.label3, textTransform: 'uppercase', letterSpacing: '.065em', padding: '0 4px 6px' }}>文件夹名称</div>
          <div className="lcard">
            <div className="lrow">
              <input
                value={name}
                onChange={e => setName(e.target.value)}
                style={{ flex: 1, border: 'none', background: 'transparent', fontSize: 17, color: C.label, letterSpacing: '-.41px' }}
              />
              {name && <div style={{ width: 18, height: 18, borderRadius: 9, background: C.label3, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }} onClick={() => setName('')}><Ic n="x" s={10} c="#fff" /></div>}
            </div>
          </div>
        </div>
        {/* Keyboard mockup */}
        <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0 }}>
          <div style={{ background: '#D1D5DA', padding: '8px 4px 20px' }}>
            {['QWERTYUIOP','ASDFGHJKL','ZXCVBNM'].map((row, ri) => (
              <div key={ri} style={{ display: 'flex', justifyContent: 'center', gap: 5, marginBottom: 8 }}>
                {row.split('').map((k) => (
                  <div key={k} style={{ width: ri === 1 ? 32 : 29, height: 42, background: '#fff', borderRadius: 5, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 16, boxShadow: '0 1px 0 rgba(0,0,0,.25)' }}>{k}</div>
                ))}
              </div>
            ))}
            <div style={{ display: 'flex', justifyContent: 'center', gap: 5 }}>
              <div style={{ width: 42, height: 42, background: '#ADB5BC', borderRadius: 5, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 14, boxShadow: '0 1px 0 rgba(0,0,0,.25)' }}>⇧</div>
              <div style={{ flex: 1, maxWidth: 196, height: 42, background: '#fff', borderRadius: 5, boxShadow: '0 1px 0 rgba(0,0,0,.25)' }} />
              <div style={{ width: 42, height: 42, background: '#ADB5BC', borderRadius: 5, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 13, boxShadow: '0 1px 0 rgba(0,0,0,.25)' }}>⌫</div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

// ─── Root App ─────────────────────────────────────────────────────────────────
export default function App() {
  return (
    <div style={{ background: '#111', minHeight: '100vh' }}>
      <InteractiveDemo />

      <div className="gallery">
        {/* Section header */}
        <div className="gal-header">
          <div style={{ width: 48, height: 48, background: C.blue, borderRadius: 14, display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: `0 6px 24px ${C.blue}66` }}>
            <Ic n="mic" s={26} c="#fff" />
          </div>
          <div>
            <p style={{ margin: '0 0 2px', fontSize: 22, fontWeight: 700, color: '#fff', letterSpacing: -.5 }}>SayMark iOS UI Kit</p>
            <p style={{ margin: 0, fontSize: 13, color: 'rgba(255,255,255,.4)' }}>All Screens · iPhone 15 Pro 393×852pt · Light Mode</p>
          </div>
        </div>

        <GallerySection title="Screen 1 — File List">
          <>
            <Frame label="有数据（展开/收起文件夹）">
              <div style={{ height: '100%', position: 'relative' }}>
                <FileList onNote={() => {}} onChat={() => {}} onRecord={() => {}} onNew={() => {}} />
                <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 5 }}>
                  <TabBar active={0} onTab={() => {}} />
                </div>
              </div>
            </Frame>
            <Frame label="空状态">
              <div style={{ height: '100%', position: 'relative' }}>
                <FileListEmpty onChat={() => {}} onRecord={() => {}} onNew={() => {}} />
                <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 5 }}>
                  <TabBar active={0} onTab={() => {}} />
                </div>
              </div>
            </Frame>
          </>
        </GallerySection>

        <GallerySection title="Screen 2 — Calendar">
          <>
            <Frame label="月视图 + 事件列表">
              <CalendarScreen onTab={() => {}} />
            </Frame>
          </>
        </GallerySection>

        <GallerySection title="Screen 3 — Reminders">
          <>
            <Frame label="有提醒">
              <RemindersScreen onTab={() => {}} />
            </Frame>
            <Frame label="空状态">
              <RemindersScreen onTab={() => {}} empty />
            </Frame>
          </>
        </GallerySection>

        <GallerySection title="Screen 4 — AI Chat">
          <>
            <Frame label="活跃对话 + 思考卡片">
              <ChatScreen onClose={() => {}} />
            </Frame>
          </>
        </GallerySection>

        <GallerySection title="Screen 5 — Note Detail">
          <>
            <Frame label="查看模式（Markdown 渲染）">
              <NoteDetail onBack={() => {}} onRecord={() => {}} />
            </Frame>
          </>
        </GallerySection>

        <GallerySection title="Screen 6 — Voice Input Sheet">
          <>
            <Frame label="语音指令输入 + 结果卡片">
              <VoiceInputSheet onClose={() => {}} />
            </Frame>
          </>
        </GallerySection>

        <GallerySection title="Screens 7 & 8 — Sheets">
          <>
            <Frame label="新建条目">
              <NewItemSheet onClose={() => {}} />
            </Frame>
            <Frame label="重命名（带键盘）">
              <RenameSheet onClose={() => {}} />
            </Frame>
          </>
        </GallerySection>

        <GallerySection title="Screen 9 — Delete Dialog">
          <>
            <Frame label="删除文件夹确认">
              <div style={{ height: '100%', display: 'flex', flexDirection: 'column', background: C.bg, position: 'relative' }}>
                <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
                  <FileList onNote={() => {}} onChat={() => {}} onRecord={() => {}} onNew={() => {}} />
                  <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 5 }}>
                    <TabBar active={0} onTab={() => {}} />
                  </div>
                </div>
                <DeleteDialog onClose={() => {}} />
              </div>
            </Frame>
          </>
        </GallerySection>

        <GallerySection title="Screen 10 — Recording Overlay (3 Zones)">
          <>
            {(['normal', 'cancel', 'text'] as RecZone[]).map((zone) => (
              <Frame key={zone} label={zone === 'normal' ? '正常模式（波形动画）' : zone === 'cancel' ? '取消区（向左拖动）' : '转文字区（向右拖动）'}>
                <div style={{ height: '100%', position: 'relative' }}>
                  <FileList onNote={() => {}} onChat={() => {}} onRecord={() => {}} onNew={() => {}} />
                  <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 5 }}>
                    <TabBar active={0} onTab={() => {}} />
                  </div>
                  <RecordingOverlay zone={zone} onClose={() => {}} />
                </div>
              </Frame>
            ))}
          </>
        </GallerySection>

        <GallerySection title="Screen 11 — Text Edit Panel (Bottom Sheet)">
          <>
            <Frame label="文字编辑底部弹窗">
              <div style={{ height: '100%', position: 'relative' }}>
                <ChatScreen onClose={() => {}} />
              </div>
            </Frame>
          </>
        </GallerySection>
      </div>
    </div>
  )
}
