import { useEffect, useState } from 'react'
import './App.css'
import { frontendRuntime, runTraceSequence } from './telemetry'

function App() {
  const [result, setResult] = useState(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [hasLoadedOnce, setHasLoadedOnce] = useState(false)

  const handleSendRequest = async () => {
    setLoading(true)
    setError('')

    try {
      const nextResult = await runTraceSequence()
      setResult(nextResult)
    } catch (nextError) {
      setError(nextError instanceof Error ? nextError.message : 'Unexpected error')
    } finally {
      setLoading(false)
      setHasLoadedOnce(true)
    }
  }

  useEffect(() => {
    const timer = window.setTimeout(() => {
      void handleSendRequest()
    }, 0)

    return () => window.clearTimeout(timer)
  }, [])

  return (
    <main className="layout">
      <section className="card">
        <p className="eyebrow">Grafana Tempo + OpenTelemetry</p>
        <h1>Browser to chained Spring backend trace propagation</h1>
        <p className="lead">
          Opening this page starts one frontend span. The browser calls the Java-agent backend,
          and that backend then calls the SDK-instrumented backend. All spans should stay inside
          the same trace.
        </p>

        <div className="runtime-grid">
          <div>
            <span className="label">Frontend service.name</span>
            <code>frontend-web</code>
          </div>
          <div>
            <span className="label">Agent backend</span>
            <code>{frontendRuntime.agentApiBaseUrl}</code>
          </div>
          <div>
            <span className="label">OTLP HTTP exporter</span>
            <code>{frontendRuntime.exporterUrl}</code>
          </div>
        </div>

        <button className="primary-button" type="button" onClick={handleSendRequest} disabled={loading}>
          {loading ? 'Sending traced request...' : 'Send chained backend request again'}
        </button>

        {error ? <p className="error-banner">{error}</p> : null}
        {!error && loading ? <p className="status-banner">Page load triggered the chained traced call...</p> : null}
        {!error && !loading && hasLoadedOnce ? (
          <p className="status-banner success-banner">
            The browser called backend 1, which then called backend 2. The frontend span and both server spans should share one trace ID.
          </p>
        ) : null}
      </section>

      <section className="card">
        <h2>What to verify</h2>
        <ol>
          <li>The frontend creates one parent span named <code>frontend.call-backend-chain</code>.</li>
          <li>The Java-agent backend receives a non-missing <code>traceparent</code> from the browser.</li>
          <li>The SDK backend receives a non-missing <code>traceparent</code> from the Java-agent backend.</li>
          <li>The frontend trace ID, agent backend trace ID, and SDK backend trace ID all match in Grafana.</li>
        </ol>
      </section>

      <section className="card">
        <h2>Latest trace snapshot</h2>

        {result ? (
          <>
            <div className="result-grid">
              <div>
                <span className="label">Frontend trace ID</span>
                <code>{result.frontendSpan.traceId}</code>
              </div>
              <div>
                <span className="label">Frontend span ID</span>
                <code>{result.frontendSpan.spanId}</code>
              </div>
              <div>
                <span className="label">Agent backend trace ID</span>
                <code>{result.agentBackend.traceId}</code>
              </div>
              <div>
                <span className="label">SDK backend trace ID</span>
                <code>{result.sdkBackend.traceId}</code>
              </div>
              <div>
                <span className="label">Agent backend traceparent</span>
                <code>{result.agentBackend.incomingTraceparent}</code>
              </div>
              <div>
                <span className="label">SDK backend downstream traceparent</span>
                <code>{result.sdkBackend.incomingTraceparent}</code>
              </div>
            </div>

            <pre>{JSON.stringify(result, null, 2)}</pre>
          </>
        ) : (
          <p className="placeholder">
            Waiting for the automatic chained traced call to complete...
          </p>
        )}
      </section>
    </main>
  )
}

export default App
