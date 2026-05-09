import { useState, useEffect } from 'react'
import DocPanel from './DocPanel.jsx'
import ChatPanel from './ChatPanel.jsx'

const s = {
  app: { display: 'flex', height: '100vh', overflow: 'hidden' },
  sidebar: {
    width: 280,
    borderRight: '1px solid var(--border)',
    background: 'var(--bg-elevated)',
    display: 'flex', flexDirection: 'column', flexShrink: 0,
  },
  sidebarHeader: {
    padding: '18px 20px 14px',
    borderBottom: '1px solid var(--border-soft)',
    fontSize: 13,
    fontWeight: 600,
    letterSpacing: '0.04em',
    textTransform: 'uppercase',
    color: 'var(--text-tertiary)',
  },
  main: { flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' },
  mainHeader: {
    padding: '14px 24px',
    borderBottom: '1px solid var(--border)',
    background: 'var(--bg-elevated)',
    display: 'flex', flexDirection: 'column', gap: 2,
    minHeight: 60,
    justifyContent: 'center',
  },
  title: {
    fontSize: 15,
    fontWeight: 600,
    color: 'var(--text-primary)',
    lineHeight: 1.4,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  subtitle: {
    fontSize: 12,
    color: 'var(--text-tertiary)',
    lineHeight: 1.4,
  },
}

export default function App() {
  const [docs, setDocs] = useState([])
  const [selectedDocId, setSelectedDocId] = useState(null)

  const fetchDocs = async () => {
    const res = await fetch('/api/documents/')
    if (res.ok) setDocs(await res.json())
  }

  useEffect(() => { fetchDocs() }, [])

  const currentDoc = docs.find(d => d.doc_id === selectedDocId)

  return (
    <div style={s.app}>
      <aside style={s.sidebar}>
        <div style={s.sidebarHeader}>文档库</div>
        <DocPanel
          docs={docs}
          selectedDocId={selectedDocId}
          onSelect={setSelectedDocId}
          onRefresh={fetchDocs}
        />
      </aside>
      <main style={s.main}>
        <div style={s.mainHeader}>
          <div style={s.title} title={currentDoc?.original_name}>
            {currentDoc ? currentDoc.original_name : '全文档问答'}
          </div>
          <div style={s.subtitle}>
            {currentDoc
              ? <>仅在该文档范围内检索 · <span className="tnum">{currentDoc.chunk_count}</span> 个文本块</>
              : '在所有已上传的文档中检索作答'}
          </div>
        </div>
        <ChatPanel docId={selectedDocId} key={selectedDocId ?? 'all'} />
      </main>
    </div>
  )
}
