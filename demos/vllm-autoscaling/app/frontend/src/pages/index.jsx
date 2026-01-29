import { useState, useEffect } from 'react'
import axios from 'axios'

export default function Home() {
  const [mode, setMode] = useState('loading')
  const [winnersPicked, setWinnersPicked] = useState(false)
  const [sessionId, setSessionId] = useState(null)
  const [question, setQuestion] = useState('')
  const [loading, setLoading] = useState(false)
  const [submitted, setSubmitted] = useState(false)
  const [answer, setAnswer] = useState('')
  const [responseTime, setResponseTime] = useState(0)
  const [isTest, setIsTest] = useState(false)
  const [showAskAgain, setShowAskAgain] = useState(false)
  const [stats, setStats] = useState(null)

  useEffect(() => {
    const checkMode = async () => {
      try {
        const res = await axios.get('/api/config')
        setMode(res.data.mode)
        setWinnersPicked(res.data.winnersPicked || false)
        
        if (res.data.sessionId) {
          setSessionId(res.data.sessionId)
        }
      } catch (e) {
        setMode('quiz')
      }
    }
    checkMode()
    const interval = setInterval(checkMode, 5000)
    return () => clearInterval(interval)
  }, [])

  useEffect(() => {
    if (submitted) {
      const fetchStats = async () => {
        try {
          const res = await axios.get('/api/stats')
          setStats(res.data)
        } catch (e) {
          console.error(e)
        }
      }
      fetchStats()
      const interval = setInterval(fetchStats, 3000)
      return () => clearInterval(interval)
    }
  }, [submitted])

  const handleSend = async (e, testMode = false) => {
    e.preventDefault()
    if (!question.trim()) return
    
    setLoading(true)
    setIsTest(testMode)
    try {
      const res = await axios.post('/api/question/submit', {
        question: question.trim(),
        test: testMode
      })
      setAnswer(res.data.answer || 'Answer coming soon!')
      setResponseTime(res.data.response_time_ms || 0)
      setSubmitted(true)
      setQuestion('')
      setShowAskAgain(false)
    } catch (e) {
      console.error(e)
      alert('Failed to submit question. Please try again.')
    } finally {
      setLoading(false)
    }
  }

  const handleAskAgain = () => {
    setSubmitted(false)
    setAnswer('')
    setResponseTime(0)
    setShowAskAgain(false)
  }

  if (mode === 'loading') return <div className="loader">Loading...</div>
  if (mode === 'survey') {
    return <SurveyPage winnersPicked={winnersPicked} sessionId={sessionId} />
  }

  if (submitted) {
    return (
      <div className="success-container">
        <div className="success-card">
          <h1>✅ Question {isTest ? 'Tested' : 'Submitted'}!</h1>
          
          {answer && (
            <div className="answer-box">
              <h3>🚇 Your Answer:</h3>
              <p className="answer-text">{answer}</p>
              <div className="response-stats">
                {responseTime > 0 && (
                  <span className="stat-badge">⚡ {(responseTime / 1000).toFixed(2)}s response time</span>
                )}
                {isTest && <span className="stat-badge test-badge">🧪 Test mode (no traffic amplification)</span>}
              </div>
            </div>
          )}
          
          {!isTest && (
            <>
              <p className="thanks-message">
                Thanks! Your question is now powering the demo! 🚇
              </p>
              <p className="watch-message">
                Watch the big screen to see Kubernetes scale!
              </p>
            </>
          )}
          
          {isTest && (
            <p className="test-message">
              This was a test question - no scaling triggered! 😉
            </p>
          )}
          
          {stats && (
            <div className="stats-box">
              <h3>📊 Current Status</h3>
              <div className="stat-row">
                <span className="stat-label">Queue:</span>
                <span className="stat-value">{stats.queueDepth} requests</span>
              </div>
              <div className="stat-row">
                <span className="stat-label">Pods:</span>
                <span className="stat-value">
                  {stats.currentPods} / {stats.maxPods}
                  {stats.scaling && <span className="scaling-badge">SCALING!</span>}
                </span>
              </div>
              {!isTest && (
                <>
                  <div className="stat-row">
                    <span className="stat-label">Your contribution:</span>
                    <span className="stat-value highlight">50x multiplier 🚀</span>
                  </div>
                  <div className="stat-row">
                    <span className="stat-label">Total questions:</span>
                    <span className="stat-value">{stats.totalQuestions}</span>
                  </div>
                </>
              )}
            </div>
          )}
          
          {!showAskAgain && (
            <div className="ask-again-hint">
              <p className="hint-text">
                👀 Eyes on the screen for the scaling magic!
              </p>
              <button 
                className="subtle-button"
                onClick={() => setShowAskAgain(true)}
              >
                (Psst... want to test another question?)
              </button>
            </div>
          )}
          
          {showAskAgain && (
            <div className="ask-again-box">
              <p className="ask-again-message">
                Fancy another go? This one won't add to the scaling load - just for fun! 😄
              </p>
              <form onSubmit={(e) => handleSend(e, true)}>
                <textarea
                  value={question}
                  onChange={(e) => setQuestion(e.target.value)}
                  placeholder="Ask another Tube question (test mode - no scaling)"
                  disabled={loading}
                  rows="2"
                  maxLength="200"
                />
                <div className="button-group">
                  <button type="submit" disabled={loading || !question.trim()} className="test-button">
                    {loading ? 'Testing...' : 'Test Question'}
                  </button>
                  <button type="button" onClick={() => setShowAskAgain(false)} className="cancel-button">
                    Nah, I'll watch
                  </button>
                </div>
              </form>
            </div>
          )}
          
          {!isTest && (
            <p className="footer-message">
              Stay tuned for the survey at the end! 🎁
            </p>
          )}
        </div>
      </div>
    )
  }

  return (
    <div className="quiz-container">
      <div className="quiz-card">
        <h1>🚇 Tube Scaling Challenge</h1>
        <p className="subtitle">Help us scale Kubernetes!</p>
        
        <div className="info-box">
          <p>Ask ONE question about the London Underground.</p>
          <p className="multiplier">Your question will be amplified <strong>50x</strong> to create scaling load! 🚀</p>
        </div>
        
        <form onSubmit={handleSend}>
          <label htmlFor="question">Your question:</label>
          <textarea
            id="question"
            value={question}
            onChange={(e) => setQuestion(e.target.value)}
            placeholder="e.g., How many lines does the London Underground have?"
            disabled={loading}
            rows="3"
            maxLength="200"
          />
          <div className="char-count">{question.length}/200</div>
          <button type="submit" disabled={loading || !question.trim()}>
            {loading ? 'Submitting...' : 'Submit Question'}
          </button>
        </form>
      </div>
    </div>
  )
}

function SessionClosedPage() {
  return (
    <div className="survey-container">
      <div className="survey-card">
        <h1>🎁 Session Complete!</h1>
        <div className="thanks-content">
          <p className="tube-emoji">🚇</p>
          <p>Thanks for participating!</p>
          <p className="closed-message">
            Winners have been announced for this session.
          </p>
          <p className="next-session-message">
            See you at the next demo! 👋
          </p>
        </div>
      </div>
    </div>
  )
}

function SurveyPage({ winnersPicked, sessionId }) {
  const [rating, setRating] = useState(5)
  const [company, setCompany] = useState('')
  const [feedback, setFeedback] = useState('')
  const [submitted, setSubmitted] = useState(false)
  const [isWinner, setIsWinner] = useState(false)
  const [responseId, setResponseId] = useState(null)

  useEffect(() => {
    const savedSessionId = localStorage.getItem('surveySessionId')
    if (savedSessionId && sessionId && savedSessionId === sessionId) {
      const savedResponseId = localStorage.getItem('surveyResponseId')
      if (savedResponseId) {
        setSubmitted(true)
        setResponseId(savedResponseId)
      }
    }
  }, [sessionId])

  useEffect(() => {
    if (responseId) {
      const checkWinner = async () => {
        try {
          const res = await axios.get('/api/survey/winners')
          if (res.data.winners && Array.isArray(res.data.winners) && res.data.winners.includes(responseId)) {
            setIsWinner(true)
          }
        } catch (e) {
          console.error('Error checking winners:', e)
        }
      }
      checkWinner()
      const interval = setInterval(checkWinner, 2000)
      return () => clearInterval(interval)
    }
  }, [responseId])

  const handleSubmit = async (e) => {
    e.preventDefault()
    try {
      const res = await axios.post('/api/survey/submit', { 
        rating, 
        company,
        feedback 
      })
      const newResponseId = res.data.id
      setResponseId(newResponseId)
      setSubmitted(true)
      localStorage.setItem('surveyResponseId', newResponseId)
      localStorage.setItem('surveySessionId', sessionId)
    } catch (e) {
      console.error(e)
      alert('Failed to submit survey. Please try again.')
    }
  }

  if (isWinner) {
    return (
      <div className="winner-container">
        <div className="winner-card">
          <h1>🎉 CONGRATULATIONS! 🎉</h1>
          <div className="winner-content">
            <p className="winner-message">You won a copy of</p>
            <p className="book-title">"Kubernetes Autoscaling"!</p>
            <p className="claim-message">
              🏃‍♂️ Quick! Find the speaker before they scale away!
            </p>
            <p className="claim-submessage">
              Your mission: Locate and claim your prize! ⏱️
            </p>
          </div>
        </div>
      </div>
    )
  }

  if (submitted) {
    // If winners have been picked but user is not a winner, show closed page
    if (winnersPicked) {
      return <SessionClosedPage />
    }
    
    return (
      <div className="survey-container">
        <div className="survey-card">
          <h2>Thanks for participating!</h2>
          <div className="thanks-content">
            <p className="tube-emoji">🚇</p>
            <p>You helped scale Kubernetes today!</p>
            <p className="waiting-message">Waiting for raffle results...</p>
            <div className="spinner"></div>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="survey-container">
      <div className="survey-card">
        <h1>📝 Session Survey</h1>
        <p className="survey-subtitle">Help us improve & enter the raffle!</p>
        
        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label htmlFor="rating">How was the session?</label>
            <div className="rating-container">
              <input
                id="rating"
                type="range"
                min="1"
                max="5"
                value={rating}
                onChange={(e) => setRating(e.target.value)}
              />
              <div className="stars">
                {'⭐'.repeat(parseInt(rating))}
              </div>
            </div>
          </div>
          
          <div className="form-group">
            <label htmlFor="company">Your company (optional):</label>
            <input
              id="company"
              type="text"
              value={company}
              onChange={(e) => setCompany(e.target.value)}
              placeholder="e.g., Acme Corp"
              maxLength="100"
            />
          </div>
          
          <div className="form-group">
            <label htmlFor="feedback">Any feedback for the speaker? (optional):</label>
            <textarea
              id="feedback"
              value={feedback}
              onChange={(e) => setFeedback(e.target.value)}
              placeholder="Share your thoughts, suggestions, or what you loved! 💭"
              rows="3"
              maxLength="500"
            />
            <div className="char-count">{feedback.length}/500</div>
          </div>
          
          <button type="submit">Submit & Enter Raffle</button>
          
          <p className="raffle-info">🎁 Win a Kubernetes Autoscaling book!</p>
        </form>
      </div>
    </div>
  )
}
