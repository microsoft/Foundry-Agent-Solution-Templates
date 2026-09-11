export type FoundryOutputItem = {
  id?: string
  type: string
  role?: string
  name?: string
  status?: string
  content?: unknown
  arguments?: unknown
  output?: unknown
  call_id?: string
  server_label?: string
  [key: string]: unknown
}

export type FoundryResponse = {
  id: string
  status: string
  output: FoundryOutputItem[]
  output_text?: string
  agent_session_id?: string
  metadata?: Record<string, string>
  error?: { message: string; code?: string } | null
}

export type ProjectRecord = {
  id: string
  ownerId: string
  name: string
  description: string
  sessionId: string
  createdAt: string
  updatedAt: string
}

export type ConversationRecord = {
  id: string
  ownerId: string
  projectId: string
  title: string
  createdAt: string
  updatedAt: string
}

export type UserProfile = {
  name: string
  email: string
}

export type ModelDeployment = {
  name: string
  modelName: string
  modelVersion: string
  modelPublisher: string
  isDefault: boolean
}

export type ProjectFile = {
  name: string
  path: string
  size: number
  isDirectory: boolean
  modifiedAt: string
}

export type BackendStatus = {
  ready: boolean
  credential: string
  agentName: string
  projectEndpoint: string
  defaultModel?: string
  user: UserProfile
}

export type StreamEvent = {
  type: string
  sequence_number?: number
  response_id?: string
  delta?: string
  item?: FoundryOutputItem
  response?: FoundryResponse
  error?: { message?: string }
  [key: string]: unknown
}

type ResponseRequest = {
  input: string | Record<string, unknown>[]
  execution_mode: 'default' | 'auto'
  conversation?: string
  previous_response_id?: string
  agent_session_id?: string
}

type ResponseStreamState = {
  responseId: string
  cursor?: number
  admitted: boolean
  terminal?: FoundryResponse
  terminalType?: string
}

const terminalResponseEvents = new Set(['response.completed', 'response.failed', 'response.cancelled', 'response.incomplete'])
const recoveryDelayMs = 500
const recoveryTimeoutMs = 120_000

export class ApiError extends Error {
  readonly status: number
  readonly requestId?: string

  constructor(message: string, status: number, requestId?: string) {
    super(message)
    this.status = status
    this.requestId = requestId
  }
}

class TerminalResponseError extends ApiError {}

export class FoundryClient {
  private readonly apiBaseUrl: string

  constructor(apiBaseUrl: string) {
    this.apiBaseUrl = apiBaseUrl
  }

  getStatus(): Promise<BackendStatus> {
    return this.request('/status')
  }

  async getUserProfile(fallback: UserProfile): Promise<UserProfile> {
    try {
      const response = await fetch('/.auth/me', { headers: { Accept: 'application/json' } })
      if (!response.ok) return fallback
      const payload = await response.json() as StaticWebAppsIdentity
      const principal = payload.clientPrincipal
      if (!principal) return fallback
      const claim = (names: string[]) => principal.claims?.find((item) => names.includes(item.typ.toLowerCase()))?.val
      const email = claim(['email', 'emails', 'preferred_username', 'upn', 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress']) || principal.userDetails || fallback.email
      const name = claim(['name', 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name']) || fallback.name
      return { name, email }
    } catch {
      return fallback
    }
  }

  listProjects(): Promise<ProjectRecord[]> {
    return this.request('/projects')
  }

  listModels(): Promise<ModelDeployment[]> {
    return this.request('/models')
  }

  createProject(name: string): Promise<ProjectRecord> {
    return this.request('/projects', { method: 'POST', body: JSON.stringify({ name }) })
  }

  async deleteProject(projectId: string): Promise<void> {
    await this.request(`/projects/${encodeURIComponent(projectId)}`, { method: 'DELETE' })
  }

  listProjectFiles(projectId: string, path = '/'): Promise<ProjectFile[]> {
    return this.request(`/projects/${encodeURIComponent(projectId)}/files?path=${encodeURIComponent(path)}`)
  }

  async downloadProjectFile(projectId: string, path: string): Promise<Blob> {
    const response = await fetch(`${this.apiBaseUrl}/projects/${encodeURIComponent(projectId)}/files/download?path=${encodeURIComponent(path)}`)
    if (!response.ok) throw await createApiError(response)
    return response.blob()
  }

  async getProjectFileText(projectId: string, path: string): Promise<string> {
    const response = await fetch(`${this.apiBaseUrl}/projects/${encodeURIComponent(projectId)}/files/text?path=${encodeURIComponent(path)}`, {
      headers: { Accept: 'text/plain' },
    })
    if (!response.ok) throw await createApiError(response)
    return response.text()
  }

  listConversations(projectId: string): Promise<ConversationRecord[]> {
    return this.request(`/projects/${encodeURIComponent(projectId)}/conversations`)
  }

  createConversation(projectId: string, title = 'New research'): Promise<ConversationRecord> {
    return this.request(`/projects/${encodeURIComponent(projectId)}/conversations`, { method: 'POST', body: JSON.stringify({ title }) })
  }

  updateConversation(projectId: string, conversationId: string, title: string): Promise<ConversationRecord> {
    return this.request(`/projects/${encodeURIComponent(projectId)}/conversations/${encodeURIComponent(conversationId)}`, { method: 'PATCH', body: JSON.stringify({ title }) })
  }

  listConversationItems(projectId: string, conversationId: string): Promise<FoundryOutputItem[]> {
    return this.request(`/projects/${encodeURIComponent(projectId)}/conversations/${encodeURIComponent(conversationId)}/items`)
  }

  async deleteConversation(projectId: string, conversationId: string): Promise<void> {
    await this.request(`/projects/${encodeURIComponent(projectId)}/conversations/${encodeURIComponent(conversationId)}`, { method: 'DELETE' })
  }

  async createResponse(projectId: string, conversationId: string, modelName: string, body: ResponseRequest, onEvent?: (event: StreamEvent) => void): Promise<FoundryResponse> {
    const responseId = createResponseId(body.previous_response_id ?? conversationId)
    const basePath = `/projects/${encodeURIComponent(projectId)}/conversations/${encodeURIComponent(conversationId)}/responses`
    const state: ResponseStreamState = { responseId, admitted: false }
    const deadline = Date.now() + recoveryTimeoutMs
    let recovering = false
    let lastError: unknown

    while (Date.now() < deadline) {
      try {
        const cursor = state.cursor === undefined ? '' : `?starting_after=${state.cursor}`
        const response = recovering
          ? await fetch(`${this.apiBaseUrl}${basePath}/${encodeURIComponent(state.responseId)}${cursor}`, { headers: { Accept: 'text/event-stream' } })
          : await fetch(`${this.apiBaseUrl}${basePath}`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream', 'x-model-deployment-name': modelName },
              body: JSON.stringify({ ...body, response_id: responseId }),
            })

        if (!response.ok) {
          const error = await createApiError(response)
          if (recovering && error.status === 404) {
            recovering = state.admitted
            lastError = error
            await delay(recoveryDelayMs)
            continue
          }
          throw error
        }

        await consumeResponseStream(response, state, onEvent)
        if (state.terminal) {
          if (state.terminalType === 'response.failed' || state.terminalType === 'response.cancelled') {
            throw new TerminalResponseError(state.terminal.error?.message ?? `The agent response ${state.terminal.status}.`, 500)
          }
          return state.terminal
        }
        recovering = true
        lastError = undefined
      } catch (error) {
        if (!isRetryableResponseError(error)) throw error
        recovering = true
        lastError = error
      }
      await delay(recoveryDelayMs)
    }

    const detail = lastError instanceof Error ? `: ${lastError.message}` : ''
    throw new ApiError(`Timed out recovering response ${state.responseId}${detail}`, 504)
  }

  private async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const response = await fetch(`${this.apiBaseUrl}${path}`, {
      ...init,
      headers: { 'Content-Type': 'application/json', ...init.headers },
    })
    if (!response.ok) throw await createApiError(response)
    if (response.status === 204) return undefined as T
    return response.json() as Promise<T>
  }
}

async function consumeResponseStream(response: Response, state: ResponseStreamState, onEvent?: (event: StreamEvent) => void): Promise<void> {
  if (!response.body) throw new ApiError('The backend returned an empty response stream.', response.status)
  const reader = response.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''
  for (;;) {
    const { done, value } = await reader.read()
    buffer += decoder.decode(value, { stream: !done })
    const lines = buffer.split('\n')
    buffer = lines.pop() ?? ''
    for (const line of lines) {
      if (!line.startsWith('data:')) continue
      const payload = line.slice(5).trim()
      if (!payload || payload === '[DONE]') continue
      const event = JSON.parse(payload) as StreamEvent
      if (typeof event.sequence_number === 'number') {
        if (state.cursor !== undefined && event.sequence_number <= state.cursor) continue
        state.cursor = event.sequence_number
      }
      const advertisedResponseId = event.response?.id ?? event.response_id ?? event.item?.response_id
      if (typeof advertisedResponseId === 'string' && advertisedResponseId) {
        state.admitted = true
        state.responseId = advertisedResponseId
      }
      onEvent?.(event)
      if (terminalResponseEvents.has(event.type)) {
        state.terminalType = event.type
        state.terminal = event.response ?? {
          id: state.responseId,
          status: event.type.slice('response.'.length),
          output: [],
          error: event.error?.message ? { message: event.error.message } : undefined,
        }
      }
    }
    if (done) return
  }
}

function createResponseId(partitionHint: string): string {
  const separator = partitionHint.indexOf('_')
  const body = separator < 0 ? '' : partitionHint.slice(separator + 1)
  let partitionKey: string
  if (body.length === 50) partitionKey = body.slice(0, 18)
  else if (body.length === 48) partitionKey = `${body.slice(-16)}00`
  else partitionKey = `${randomHex().slice(0, 16)}00`
  return `caresp_${partitionKey}${randomHex()}`
}

function randomHex(): string {
  return crypto.randomUUID().replaceAll('-', '')
}

function isRetryableResponseError(error: unknown): boolean {
  if (error instanceof TerminalResponseError) return false
  if (error instanceof ApiError) {
    return error.status >= 500 || (error.status === 424 && error.message.includes('session_not_ready'))
  }
  return error instanceof TypeError || (error instanceof DOMException && error.name !== 'AbortError')
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds))
}

export function getItemText(item: FoundryOutputItem): string {
  if (typeof item.content === 'string') return item.content
  if (!Array.isArray(item.content)) return ''
  return item.content.map((part) => {
    if (!part || typeof part !== 'object') return ''
    return (part as { text?: string }).text ?? ''
  }).filter(Boolean).join('\n')
}

async function createApiError(response: Response) {
  let message = `${response.status} ${response.statusText}`
  let requestId = response.headers.get('x-ms-request-id') ?? undefined
  try {
    const body = await response.json() as { detail?: string; error?: { message?: string; requestId?: string }; message?: string }
    message = body.error?.message ?? body.detail ?? body.message ?? message
    requestId = body.error?.requestId ?? requestId
  } catch {
    // Keep the HTTP status when the backend doesn't return JSON.
  }
  return new ApiError(message, response.status, requestId)
}

type StaticWebAppsIdentity = {
  clientPrincipal?: {
    userDetails?: string
    claims?: Array<{ typ: string; val: string }>
  } | null
}