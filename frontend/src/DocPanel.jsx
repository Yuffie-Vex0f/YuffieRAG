import { useRef, useState } from 'react'

const s = {
  wrap: { flex: 1, overflow: 'auto', padding: 12 },
  upload: {
    width: '100%',
    padding: '10px 0',
    border: '1px dashed #d0d0d8',
    borderRadius: 8,
    background: 'transparent',
    cursor: 'pointer',
    fontSize: 13,
    fontWeight: 500,
    color: 'var(--text-secondary)',
    marginBottom: 12,
    transition: 'border-color 0.15s, color 0.15s',
  },
  item: (active) => ({
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    padding: '8px 10px',
    borderRadius: 8,
    cursor: 'pointer',
    marginBottom: 4,
    background: active ? 'var(--accent-soft)' : 'transparent',
    border: active ? '1px solid var(--accent-border)' : '1px solid transparent',
    transition: 'background 0.12s',
  }),
  name: {
    flex: 1,
    minWidth: 0,                     // 关键：让 flex 子项可以正常 ellipsis
    fontSize: 13,
    lineHeight: 1.5,
    color: 'var(--text-primary)',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  badge: {
    fontSize: 11,
    fontWeight: 500,
    color: 'var(--text-tertiary)',
    flexShrink: 0,
    padding: '2px 6px',
    background: 'var(--border-soft)',
    borderRadius: 4,
  },
  del: {
    background: 'none',
    border: 'none',
    cursor: 'pointer',
    color: '#cfcfd6',
    fontSize: 16,
    lineHeight: 1,
    padding: 2,
    flexShrink: 0,
  },
  allBtn: (active) => ({
    width: '100%',
    textAlign: 'left',
    padding: '9px 10px',
    borderRadius: 8,
    cursor: 'pointer',
    marginBottom: 8,
    background: active ? 'var(--accent-soft)' : '#eeeef2',
    border: active ? '1px solid var(--accent-border)' : '1px solid transparent',
    fontSize: 13,
    fontWeight: 600,
    color: active ? 'var(--accent)' : 'var(--text-primary)',
    letterSpacing: '0.01em',
  }),
  uploading: {
    fontSize: 12,
    color: 'var(--text-secondary)',
    textAlign: 'center',
    padding: 8,
    lineHeight: 1.5,
  },
  empty: {
    fontSize: 12,
    color: 'var(--text-tertiary)',
    textAlign: 'center',
    marginTop: 24,
    lineHeight: 1.6,
  },
}

export default function DocPanel({ docs, selectedDocId, onSelect, onRefresh }) {
  const inputRef = useRef()
  const [uploading, setUploading] = useState(false)

  const handleUpload = async (e) => {
    const file = e.target.files?.[0]
    if (!file) return
    setUploading(true)
    const form = new FormData()
    form.append('file', file)
    try {
      const res = await fetch('/api/documents/upload', { method: 'POST', body: form })
      if (!res.ok) {
        const err = await res.json()
        alert(err.detail || '上传失败')
      } else {
        await onRefresh()
      }
    } finally {
      setUploading(false)
      e.target.value = ''
    }
  }

  const handleDelete = async (e, docId) => {
    e.stopPropagation()
    if (!confirm('确认删除该文档？')) return
    await fetch(`/api/documents/${docId}`, { method: 'DELETE' })
    await onRefresh()
    if (selectedDocId === docId) onSelect(null)
  }

  return (
    <div style={s.wrap}>
      <input ref={inputRef} type="file" accept=".pdf,.txt,.docx"
             style={{ display: 'none' }} onChange={handleUpload} />
      <button style={s.upload} onClick={() => inputRef.current.click()}>
        + 上传文档 · PDF / DOCX / TXT
      </button>
      {uploading && <p style={s.uploading}>正在解析并建立索引…</p>}

      <button style={s.allBtn(!selectedDocId)} onClick={() => onSelect(null)}>
        全文档问答
      </button>

      {docs.map(doc => (
        <div key={doc.doc_id} style={s.item(selectedDocId === doc.doc_id)}
             onClick={() => onSelect(doc.doc_id)}>
          <span style={s.name} title={doc.original_name}>{doc.original_name}</span>
          <span style={s.badge} className="tnum">{doc.chunk_count}</span>
          <button style={s.del} onClick={(e) => handleDelete(e, doc.doc_id)}
                  title="删除文档">×</button>
        </div>
      ))}

      {docs.length === 0 && !uploading && (
        <p style={s.empty}>暂无文档<br />请先上传一个文件</p>
      )}
    </div>
  )
}
