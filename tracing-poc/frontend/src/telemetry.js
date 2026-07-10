import { context, trace } from '@opentelemetry/api'
import { ZoneContextManager } from '@opentelemetry/context-zone'
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http'
import { registerInstrumentations } from '@opentelemetry/instrumentation'
import { DocumentLoadInstrumentation } from '@opentelemetry/instrumentation-document-load'
import { FetchInstrumentation } from '@opentelemetry/instrumentation-fetch'
import { resourceFromAttributes } from '@opentelemetry/resources'
import { BatchSpanProcessor, WebTracerProvider } from '@opentelemetry/sdk-trace-web'
import { SEMRESATTRS_SERVICE_NAME } from '@opentelemetry/semantic-conventions'

const agentApiBaseUrl = import.meta.env.VITE_AGENT_API_BASE_URL ?? 'http://localhost:8080'
const exporterUrl =
  import.meta.env.VITE_OTEL_EXPORTER_URL ?? 'http://localhost:4318/v1/traces'
const serviceName = 'frontend-web'

function escapeForRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

const apiUrlPatterns = [new RegExp(`^${escapeForRegExp(agentApiBaseUrl)}`)]

const provider = new WebTracerProvider({
  resource: resourceFromAttributes({
    [SEMRESATTRS_SERVICE_NAME]: serviceName,
  }),
  spanProcessors: [
    new BatchSpanProcessor(
      new OTLPTraceExporter({
        url: exporterUrl,
      }),
      { scheduledDelayMillis: 500 },
    ),
  ],
})

provider.register({
  contextManager: new ZoneContextManager(),
})

registerInstrumentations({
  instrumentations: [
    new DocumentLoadInstrumentation(),
    new FetchInstrumentation({
      propagateTraceHeaderCorsUrls: apiUrlPatterns,
    }),
  ],
})

const tracer = trace.getTracer(serviceName)

async function fetchTraceSnapshot(baseUrl) {
  const response = await fetch(`${baseUrl}/api/trace`)
  const payload = await response.json()

  if (!response.ok) {
    throw new Error(`Backend returned ${response.status}`)
  }

  return payload
}

export async function runTraceSequence() {
  const span = tracer.startSpan('frontend.call-backend-chain')
  const frontendSpanContext = span.spanContext()

  console.info('Starting traced frontend request', {
    traceId: frontendSpanContext.traceId,
    spanId: frontendSpanContext.spanId,
    agentApiBaseUrl,
  })

  return context.with(trace.setSpan(context.active(), span), async () => {
    try {
      const agentBackend = await fetchTraceSnapshot(agentApiBaseUrl)
      const result = {
        frontendSpan: frontendSpanContext,
        agentBackend,
        sdkBackend: agentBackend.downstreamBackend,
      }

      console.info('Completed traced frontend request', {
        frontendTraceId: result.frontendSpan.traceId,
        agentBackendTraceId: result.agentBackend.traceId,
        sdkBackendTraceId: result.sdkBackend.traceId,
      })

      return result
    } catch (error) {
      console.error('Traced frontend request failed', {
        traceId: frontendSpanContext.traceId,
        spanId: frontendSpanContext.spanId,
        error,
      })
      throw error
    } finally {
      span.end()
    }
  })
}

export const frontendRuntime = {
  agentApiBaseUrl,
  exporterUrl,
}
