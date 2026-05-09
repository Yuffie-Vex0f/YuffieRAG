import { useState, useRef, useEffect } from 'react'

const s = {
  wrap: { flex: 1, display: 'flex', flexDirection: 'column', overflow: 'hidden' },
  messages: {
    flex: 1, overflow: 'auto',
    padding: '24px 28px',
    display: 'flex', flexDirection: 'column', gap: 20,
  },
  msgBlock: (role) => ({
    display: 'flex', flexDirection: 'column',
    alignItems: role === 'user' ? 'flex-end' : 'flex-start',
    gap: 6,
    maxWidth: '75%',
    alignSelf: role === 'user' ? 'flex-end' : 'flex-start',
  }),
  bubble: (role) => ({
    padding: '12px 16px',
    borderRadius: role === 'user' ? '14px 14px 4px 14px' : '14px 14px 14px 4px',
    fontSize: 14,
    /* 中文气泡用 1.75 行高，更松弛、更易读 */
    lineHeight: 1.75,
    /* 保留换行；长 URL/英文长串自动断行，避免撑破气泡 */
    whiteSpace: 'pre-wrap',
    overflowWrap: 'anywhere',
    wordBreak: 'break-word',
    background: role === 'user' ? 'var(--accent)' : 'var(--bg-elevated)',
    color: role === 'user' ? '#fff' : 'var(--text-primary)',
    border: role === 'user' ? 'none' : '1px solid var(--border)',
    boxShadow: role === 'assistant' ? '0 1px 2px rgba(0,0,0,0.02)' : 'none',
  }),
  caret: {
    display: 'inline-block',
    width: 2, height: '1em',
    background: 'currentColor',
    verticalAlign: '-2px',
    marginLeft: 1,
    animation: 'blink 1s steps(2, start) infinite',
  },
  sourcesWrap: {
    width: '100%',
    marginTop: 4,
    display: 'flex', flexDirection: 'column', gap: 6,
  },
  sourcesLabel: {
    fontSize: 11,
    fontWeight: 600,
    letterSpacing: '0.06em',
    textTransform: 'uppercase',
    color: 'var(--text-tertiary)',
  },
  srcItem: {
    background: 'var(--bg-elevated)',
    border: '1px solid var(--border)',
    borderRadius: 8,
    padding: '8px 12px',
    display: 'flex', flexDirection: 'column', gap: 4,
  },
  srcMeta: {
    fontSize: 11,
    fontWeight: 600,
    color: 'var(--accent)',
    letterSpacing: '0.02em',
  },
  srcText: {
    fontSize: 12.5,
    lineHeight: 1.65,
    color: 'var(--text-secondary)',
  },
  inputRow: {
    padding: '14px 20px 18px',
    borderTop: '1px solid var(--border)',
    background: 'var(--bg-elevated)',
    display: 'flex', gap: 10, alignItems: 'flex-end',
  },
  input: {
    flex: 1,
    padding: '10px 14px',
    border: '1px solid var(--border)',
    borderRadius: 10,
    fontSize: 14,
    lineHeight: 1.6,
    outline: 'none',
    resize: 'none',
    background: 'var(--bg)',
    transition: 'border-color 0.15s, background 0.15s',
  },
  btn: (disabled) => ({
    padding: '10px 22px',
    borderRadius: 10,
    border: 'none',
    background: disabled ? '#d8d8de' : 'var(--accent)',
    color: '#fff',
    cursor: disabled ? 'not-allowed' : 'pointer',
    fontSize: 14,
    fontWeight: 600,
    letterSpacing: '0.02em',
    transition: 'background 0.15s, transform 0.05s',
    flexShrink: 0,
    height: 'fit-content',
  }),
  hint: {
    fontSize: 11,
    color: 'var(--text-tertiary)',
    padding: '0 20px 10px',
    background: 'var(--bg-elevated)',
  },
  empty: {
    flex: 1, display: 'flex', flexDirection: 'column',
    alignItems: 'center', justifyContent: 'center',
    color: 'var(--text-tertiary)',
    gap: 8,
  },
  emptyTitle: { fontSize: 15, color: 'var(--text-secondary)', fontWeight: 500 },
  emptySub: { fontSize: 13, color: 'var(--text-tertiary)' },
}

export default function ChatPanel({ docId }) {
  const [messages, setMessages] = useState([])
  const [input, setInput] = useState('')
  const [loading, setLoading] = useState(false)
  const [sessionId, setSessionId] = useState(null)
  const [focused, setFocused] = useState(false)
  const bottomRef = useRef()

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  const send = async () => {
    const q = input.trim()
    if (!q || loading) return
    setInput('')
    setLoading(true)

    setMessages(prev => [...prev, { role: 'user', content: q }])
    setMessages(prev => [...prev, { role: 'assistant', content: '', sources: [], streaming: true }])

    try {
      const res = await fetch('/api/ask/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ question: q, doc_id: docId, session_id: sessionId }),
      })

      const reader = res.body.getReader()
      const decoder = new TextDecoder()
      let buffer = ''

      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        buffer += decoder.decode(value, { stream: true })
        const lines = buffer.split('\n\n')
        buffer = lines.pop()

        for (const line of lines) {
          if (!line.startsWith('data: ')) continue
          const data = JSON.parse(line.slice(6))
          if (data.type === 'meta') {
            if (data.session_id) setSessionId(data.session_id)
            setMessages(prev => {
              const next = [...prev]
              next[next.length - 1] = { ...next[next.length - 1], sources: data.sources }
              return next
            })
          } else if (data.type === 'token') {
            setMessages(prev => {
              const next = [...prev]
              next[next.length - 1] = {
                ...next[next.length - 1],
                content: next[next.length - 1].content + data.text,
              }
              return next
            })
          } else if (data.type === 'done') {
            setMessages(prev => {
              const next = [...prev]
              next[next.length - 1] = { ...next[next.length - 1], streaming: false }
              return next
            })
          }
        }
      }
    } catch (err) {
      setMessages(prev => {
        const next = [...prev]
        next[next.length - 1] = { role: 'assistant', content: `请求失败：${err.message}`, sources: [] }
        return next
      })
    } finally {
      setLoading(false)
    }
  }

  const focusedInputStyle = focused
    ? { ...s.input, borderColor: 'var(--accent-border)', background: '#fff',
        boxShadow: '0 0 0 3px var(--accent-soft)' }
    : s.input

  return (
    <div style={s.wrap}>
      <style>{`@keyframes blink { 50% { opacity: 0; } }`}</style>

      {messages.length === 0
        ? (
          <div style={s.empty}>
            <div style={s.emptyTitle}>开始与你的文档对话</div>
            <div style={s.emptySub}>上传文档后，在下方输入问题</div>
          </div>
        )
        : (
          <div style={s.messages}>
            {messages.map((msg, i) => (
              <div key={i} style={s.msgBlock(msg.role)}>
                <div style={s.bubble(msg.role)}>
                  {msg.content}
                  {msg.streaming && <span style={s.caret} />}
                </div>
                {msg.role === 'assistant' && msg.sources?.length > 0 && (
                  <div style={s.sourcesWrap}>
                    <div style={s.sourcesLabel}>
                      来源参考 · <span className="tnum">{msg.sources.length}</span> 段
                    </div>
                    {msg.sources.map((src, j) => (
                      <div key={j} style={s.srcItem}>
                        <div style={s.srcMeta} className="tnum">第 {src.page} 页</div>
                        <div style={s.srcText} className="clamp-2">{src.text}</div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            ))}
            <div ref={bottomRef} />
          </div>
        )
      }
      <div style={s.inputRow}>
        <textarea
          style={focusedInputStyle}
          rows={2}
          placeholder="输入问题，按 Ctrl + Enter 发送…"
          value={input}
          onChange={e => setInput(e.target.value)}
          onFocus={() => setFocused(true)}
          onBlur={() => setFocused(false)}
          onKeyDown={e => { if (e.key === 'Enter' && e.ctrlKey) send() }}
        />
        <button style={s.btn(loading || !input.trim())}
                onClick={send}
                disabled={loading || !input.trim()}>
          {loading ? '思考中…' : '发送'}
        </button>
      </div>
    </div>
  )
}
