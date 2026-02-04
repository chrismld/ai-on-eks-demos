import { useState, useRef, useEffect } from 'react'
import axios from 'axios'

export default function Home() {
  const [messages, setMessages] = useState([])
  const [question, setQuestion] = useState('')
  const [loading, setLoading] = useState(false)
  const messagesEndRef = useRef(null)

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }

  useEffect(() => {
    scrollToBottom()
  }, [messages])

  const handleSend = async (e) => {
    e.preventDefault()
    if (!question.trim() || loading) return
    
    const userMessage = question.trim()
    setQuestion('')
    
    // Add user message
    setMessages(prev => [...prev, { type: 'user', text: userMessage }])
    
    // Add thinking message
    const thinkingId = Date.now()
    setMessages(prev => [...prev, { type: 'thinking', id: thinkingId }])
    
    setLoading(true)
    try {
      const res = await axios.post('/api/question/submit', {
        question: userMessage,
        test: true
      })
      
      // Remove thinking message and add response
      setMessages(prev => {
        const filtered = prev.filter(m => m.id !== thinkingId)
        return [...filtered, {
          type: 'assistant',
          text: res.data.answer || 'Sorry, no answer available.',
          responseTime: res.data.response_time_ms || 0
        }]
      })
    } catch (e) {
      console.error(e)
      // Remove thinking message and add error
      setMessages(prev => {
        const filtered = prev.filter(m => m.id !== thinkingId)
        return [...filtered, {
          type: 'assistant',
          text: 'Sorry, something went wrong. Please try again.',
          isError: true
        }]
      })
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="chat-container">
      <div className="chat-header">
        <h1>🚇 Tube Assistant</h1>
        <p>Ask me anything about the London Underground!</p>
      </div>
      
      <div className="chat-messages">
        {messages.length === 0 && (
          <div className="welcome-message">
            <p>👋 Hello! Ask me a question about the Tube.</p>
          </div>
        )}
        
        {messages.map((msg, idx) => (
          <div key={idx} className={`message ${msg.type}`}>
            {msg.type === 'user' && (
              <div className="message-bubble user-bubble">
                {msg.text}
              </div>
            )}
            {msg.type === 'thinking' && (
              <div className="message-bubble assistant-bubble thinking">
                <span className="thinking-text">Mind the gap</span>
                <span className="thinking-dots">
                  <span>.</span><span>.</span><span>.</span>
                </span>
              </div>
            )}
            {msg.type === 'assistant' && (
              <div className={`message-bubble assistant-bubble ${msg.isError ? 'error' : ''}`}>
                <p>{msg.text}</p>
                {msg.responseTime > 0 && (
                  <span className="response-time">⚡ {(msg.responseTime / 1000).toFixed(2)}s</span>
                )}
              </div>
            )}
          </div>
        ))}
        <div ref={messagesEndRef} />
      </div>
      
      <form className="chat-input" onSubmit={handleSend}>
        <textarea
          value={question}
          onChange={(e) => setQuestion(e.target.value)}
          placeholder="Ask about the Tube..."
          disabled={loading}
          rows="1"
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault()
              handleSend(e)
            }
          }}
        />
        <button type="submit" disabled={loading || !question.trim()}>
          Send
        </button>
      </form>
    </div>
  )
}
