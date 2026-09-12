import {
  AlertCircle, Archive, Bot, Check, ChevronDown, ChevronRight, Code2,
  Download, FileText, Folder, FolderOpen, FolderTree, LoaderCircle, MessageSquareText, PanelLeftClose,
  PanelLeftOpen, PanelRightClose, Plus, RefreshCw, Search, Send, ShieldCheck, TerminalSquare,
  Trash2, User, X,
} from 'lucide-react'
import { useEffect, useRef, useState, type ReactNode } from 'react'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import './App.css'
import type { AppConfig } from './config'
import {
  ApiError, FoundryClient, getItemText, type BackendStatus, type FoundryOutputItem, type FoundryResponse,
  type ModelDeployment, type ProjectFile, type ProjectRecord, type ConversationRecord, type StreamEvent,
} from './foundry'

type ChatEntry = { id: string; role: 'user' | 'assistant'; text: string; items: FoundryOutputItem[]; responseId?: string; sessionId?: string; pending?: boolean; queued?: boolean; steered?: boolean; error?: string }
type QueuedMessage = { userEntryId: string; input: string; modelName: string; executionMode: ExecutionMode; conversation: ConversationRecord }
type SendMode = 'queue' | 'steer'
type ExecutionMode = 'default' | 'auto'
const newId = () => crypto.randomUUID()

function App({ config }: { config: AppConfig }) {
  const [client] = useState(() => new FoundryClient(config.apiBaseUrl))
  const [backendStatus, setBackendStatus] = useState<BackendStatus>()
  const [backendError, setBackendError] = useState<string>()
  const [sidebarOpen, setSidebarOpen] = useState(() => window.matchMedia('(min-width: 821px)').matches)
  const [projects, setProjects] = useState<ProjectRecord[]>([])
  const [conversations, setConversations] = useState<ConversationRecord[]>([])
  const [models, setModels] = useState<ModelDeployment[]>([])
  const [selectedModel, setSelectedModel] = useState('')
  const [filesOpen, setFilesOpen] = useState(false)
  const [filesByPath, setFilesByPath] = useState<Record<string, ProjectFile[]>>({})
  const [expandedPaths, setExpandedPaths] = useState<string[]>([])
  const [loadingPaths, setLoadingPaths] = useState<string[]>([])
  const [downloadingPath, setDownloadingPath] = useState<string>()
  const [previewFile, setPreviewFile] = useState<ProjectFile>()
  const [previewContent, setPreviewContent] = useState('')
  const [previewLoading, setPreviewLoading] = useState(false)
  const [activeProjectId, setActiveProjectId] = useState<string>()
  const [activeConversationId, setActiveConversationId] = useState<string>()
  const [projectDialogOpen, setProjectDialogOpen] = useState(false)
  const [projectName, setProjectName] = useState('')
  const [entries, setEntries] = useState<ChatEntry[]>([])
  const [prompt, setPrompt] = useState('')
  const [busy, setBusy] = useState(false)
  const [sendMode, setSendMode] = useState<SendMode>('queue')
  const [executionMode, setExecutionMode] = useState<ExecutionMode>('default')
  const [queuedCount, setQueuedCount] = useState(0)
  const [activeResponseId, setActiveResponseId] = useState<string>()
  const [loadingHistory, setLoadingHistory] = useState(false)
  const [fatalError, setFatalError] = useState<string>()
  const responseQueue = useRef<QueuedMessage[]>([])
  const drainingQueue = useRef(false)
  const activeRequests = useRef(0)
  const activeResponse = useRef<{ assistantId: string; responseId: string } | undefined>(undefined)
  const scrollAnchor = useRef<HTMLDivElement>(null)
  useEffect(() => { scrollAnchor.current?.scrollIntoView({ behavior: 'smooth' }) }, [entries])

  const formatError = (error: unknown) => {
    if (error instanceof ApiError) {
      if (error.status === 401) return 'The backend Azure credential expired. Run az login or azd auth login again.'
      if (error.status === 403) return 'Access denied. Ask for the Foundry User role on this project.'
      if (error.status === 404) return 'This project or conversation no longer exists.'
      if (error.status === 424) return 'The project workspace is warming up. Try again in a moment.'
      if (error.status === 429) return 'The model is at its rate limit. Wait briefly, then retry.'
      return `${error.message}${error.requestId ? ` (request ${error.requestId})` : ''}`
    }
    return error instanceof Error ? error.message : 'An unexpected error occurred.'
  }

  const refreshBackend = async () => {
    setBackendError(undefined)
    try {
      const status = await client.getStatus()
      const user = config.environment === 'local' ? status.user : await client.getUserProfile(status.user)
      setBackendStatus({ ...status, user })
    }
    catch (error) {
      if (error instanceof ApiError && error.status === 401 && config.environment !== 'local') {
        window.location.assign('/.auth/login/aad?post_login_redirect_uri=/')
        return
      }
      setBackendError(formatError(error))
    }
  }
  useEffect(() => { void refreshBackend() }, [client])

  const refreshWorkspace = async () => {
    const projectRecords = await client.listProjects()
    const conversationGroups = await Promise.all(projectRecords.map(async (project) => {
      return client.listConversations(project.id)
    }))
    setProjects(projectRecords)
    setConversations(conversationGroups.flat().sort((left, right) => right.updatedAt.localeCompare(left.updatedAt)))
    setActiveProjectId((current) => current && projectRecords.some((project) => project.id === current) ? current : projectRecords[0]?.id)
  }
  useEffect(() => {
    if (!backendStatus?.ready) return
    void Promise.all([refreshWorkspace(), client.listModels()]).then(([, modelRecords]) => {
      setModels(modelRecords)
      setSelectedModel((current) => {
        if (modelRecords.some((model) => model.name === current)) return current
        return modelRecords.find((model) => model.isDefault)?.name ?? modelRecords[0]?.name ?? ''
      })
    }).catch((error) => setFatalError(formatError(error)))
  }, [backendStatus?.ready])

  const createProject = async () => {
    const name = projectName.trim()
    if (!client || busy || !name) return undefined
    setBusy(true); setFatalError(undefined)
    try {
      const project = await client.createProject(name)
      setProjects((current) => [project, ...current]); setActiveProjectId(project.id); setActiveConversationId(undefined); setEntries([]); setProjectDialogOpen(false); setProjectName('')
      return project
    } catch (error) { setFatalError(formatError(error)); return undefined }
    finally { setBusy(false) }
  }

  const createConversation = async (projectId?: string) => {
    if (!client || busy) return undefined
    let project = projects.find((item) => item.id === projectId) ?? projects.find((item) => item.id === activeProjectId)
    if (!project) { setProjectDialogOpen(true); return undefined }
    setBusy(true); setFatalError(undefined)
    try {
      const created = await client.createConversation(project.id)
      setConversations((current) => [created, ...current]); setActiveProjectId(project.id); setActiveConversationId(created.id); setEntries([])
      return created
    } catch (error) { setFatalError(formatError(error)); return undefined }
    finally { setBusy(false) }
  }

  const selectProject = (project: ProjectRecord) => {
    setActiveProjectId(project.id)
    setFilesByPath({}); setExpandedPaths([]); setPreviewFile(undefined); setPreviewContent('')
    if (filesOpen) void loadDirectory(project.id, '/')
    if (conversations.find((record) => record.id === activeConversationId)?.projectId !== project.id) { setActiveConversationId(undefined); setEntries([]) }
  }

  const deleteProject = async (project: ProjectRecord) => {
    if (!client || busy || !confirm(`Delete “${project.name}” and all of its conversations and files?`)) return
    setBusy(true); setFatalError(undefined)
    try {
      await client.deleteProject(project.id)
      const remaining = projects.filter((item) => item.id !== project.id)
      setProjects(remaining); setConversations((current) => current.filter((record) => record.projectId !== project.id))
      if (activeProjectId === project.id) { setActiveProjectId(remaining[0]?.id); setActiveConversationId(undefined); setEntries([]); setFilesByPath({}); setExpandedPaths([]); setFilesOpen(false); setPreviewFile(undefined); setPreviewContent('') }
    } catch (error) { setFatalError(formatError(error)) }
    finally { setBusy(false) }
  }

  const selectConversation = async (record: ConversationRecord) => {
    if (!client || busy) return
    setActiveProjectId(record.projectId); setActiveConversationId(record.id); setLoadingHistory(true); setFatalError(undefined)
    try { setEntries((await client.listConversationItems(record.projectId, record.id)).map(itemToChatEntry)) }
    catch (error) { setEntries([]); setFatalError(formatError(error)) }
    finally { setLoadingHistory(false) }
  }
  const deleteConversation = async (record: ConversationRecord) => {
    if (!client || busy) return
    try {
      await client.deleteConversation(record.projectId, record.id)
      setConversations((current) => current.filter((item) => item.id !== record.id))
      if (activeConversationId === record.id) { setActiveConversationId(undefined); setEntries([]) }
    } catch (error) { setFatalError(formatError(error)) }
  }

  const loadDirectory = async (projectId: string, path: string) => {
    setLoadingPaths((current) => current.includes(path) ? current : [...current, path])
    try {
      const files = await client.listProjectFiles(projectId, path)
      setFilesByPath((current) => ({ ...current, [path]: files }))
    } catch (error) { setFatalError(formatError(error)) }
    finally { setLoadingPaths((current) => current.filter((item) => item !== path)) }
  }

  const toggleFiles = () => {
    if (!activeProject) return
    const opening = !filesOpen
    setFilesOpen(opening)
    if (opening && !filesByPath['/']) void loadDirectory(activeProject.id, '/')
  }

  const toggleDirectory = (entry: ProjectFile) => {
    if (!activeProject) return
    const expanded = expandedPaths.includes(entry.path)
    setExpandedPaths((current) => expanded ? current.filter((path) => path !== entry.path) : [...current, entry.path])
    if (!expanded && !filesByPath[entry.path]) void loadDirectory(activeProject.id, entry.path)
  }

  const downloadFile = async (entry: ProjectFile) => {
    if (!activeProject || downloadingPath) return
    setDownloadingPath(entry.path)
    try {
      const blob = await client.downloadProjectFile(activeProject.id, entry.path)
      const url = URL.createObjectURL(blob)
      const anchor = document.createElement('a')
      anchor.href = url; anchor.download = entry.name; anchor.click()
      URL.revokeObjectURL(url)
    } catch (error) { setFatalError(formatError(error)) }
    finally { setDownloadingPath(undefined) }
  }

  const previewTextFile = async (entry: ProjectFile) => {
    if (!activeProject || !canPreviewText(entry) || previewLoading) return
    setPreviewFile(entry); setPreviewContent(''); setPreviewLoading(true)
    try { setPreviewContent(await client.getProjectFileText(activeProject.id, entry.path)) }
    catch (error) { setPreviewFile(undefined); setFatalError(formatError(error)) }
    finally { setPreviewLoading(false) }
  }

  const updateAssistantDraft = (entryId: string, event: StreamEvent) => {
    const eventItem = event.item as (FoundryOutputItem & { response_id?: string }) | undefined
    const responseId = event.response?.id ?? event.response_id ?? eventItem?.response_id
    if (responseId && activeResponse.current?.assistantId !== entryId) {
      activeResponse.current = { assistantId: entryId, responseId }
      setActiveResponseId(responseId)
      setEntries((current) => current.map((entry) => entry.id === entryId ? { ...entry, responseId } : entry))
    }
    setEntries((current) => current.map((entry) => {
      if (entry.id !== entryId) return entry
      if (event.type === 'response.output_text.delta' && typeof event.delta === 'string') return { ...entry, text: entry.text + event.delta }
      const item = event.item as FoundryOutputItem | undefined
      if (item && (event.type === 'response.output_item.added' || event.type === 'response.output_item.done')) {
        return { ...entry, items: [...entry.items.filter((existing) => existing.id !== item.id), item] }
      }
      return entry
    }))
  }
  const finishResponse = (entryId: string, response: FoundryResponse, conversationId?: string) => {
    const text = response.output_text || response.output.map(getItemText).filter(Boolean).join('\n\n')
    setEntries((current) => current.map((entry) => entry.id === entryId ? { ...entry, text: text || entry.text, items: response.output, responseId: response.id, sessionId: response.agent_session_id, pending: false, error: response.error?.message } : entry))
    if (conversationId && response.agent_session_id) {
      setConversations((current) => current.map((record) => record.id === conversationId ? { ...record, updatedAt: new Date().toISOString() } : record))
    }
    if (activeResponse.current?.assistantId === entryId) {
      activeResponse.current = undefined
      setActiveResponseId(undefined)
    }
  }

  const beginResponse = () => {
    activeRequests.current += 1
    setBusy(true)
  }

  const endResponse = () => {
    activeRequests.current = Math.max(0, activeRequests.current - 1)
    if (activeRequests.current === 0) setBusy(false)
  }

  const drainResponseQueue = async () => {
    if (drainingQueue.current || activeRequests.current > 0) return
    const message = responseQueue.current.shift()
    if (!message) return
    drainingQueue.current = true
    setQueuedCount(responseQueue.current.length)
    setEntries((current) => current.map((entry) => entry.id === message.userEntryId ? { ...entry, queued: false } : entry))
    const { id: conversationId, projectId } = message.conversation
    const assistantId = newId()
    setEntries((current) => [...current, { id: assistantId, role: 'assistant', text: '', items: [], pending: true }])
    beginResponse(); setFatalError(undefined)
    const title = message.conversation.title === 'New research' ? message.input.slice(0, 54) : message.conversation.title
    setConversations((current) => current.map((record) => record.id === conversationId ? { ...record, title, updatedAt: new Date().toISOString() } : record))
    try {
      if (title !== message.conversation.title) await client.updateConversation(projectId, conversationId, title)
      const response = await client.createResponse(projectId, conversationId, message.modelName, { input: message.input, execution_mode: message.executionMode }, (event) => updateAssistantDraft(assistantId, event))
      finishResponse(assistantId, response, conversationId)
    } catch (error) {
      setEntries((current) => current.map((entry) => entry.id === assistantId ? { ...entry, pending: false, error: entry.steered ? undefined : formatError(error) } : entry))
    } finally {
      endResponse()
      drainingQueue.current = false
      if (responseQueue.current.length) void drainResponseQueue()
    }
  }

  const steer = async (input: string, conversation: ConversationRecord, modelName: string, mode: ExecutionMode, parentResponseId: string) => {
    const previousAssistantId = activeResponse.current?.assistantId
    if (previousAssistantId) {
      setEntries((current) => current.map((entry) => entry.id === previousAssistantId ? { ...entry, pending: false, steered: true } : entry))
    }
    const userEntry: ChatEntry = { id: newId(), role: 'user', text: input, items: [] }
    const assistantId = newId()
    setEntries((current) => [...current, userEntry, { id: assistantId, role: 'assistant', text: '', items: [], pending: true }])
    setPrompt(''); beginResponse(); setFatalError(undefined)
    try {
      const response = await client.createResponse(conversation.projectId, conversation.id, modelName, { input, execution_mode: mode, previous_response_id: parentResponseId }, (event) => updateAssistantDraft(assistantId, event))
      finishResponse(assistantId, response, conversation.id)
    } catch (error) {
      setEntries((current) => current.map((entry) => entry.id === assistantId ? { ...entry, pending: false, error: formatError(error) } : entry))
    } finally {
      endResponse()
      if (activeRequests.current === 0 && responseQueue.current.length) void drainResponseQueue()
    }
  }

  const send = async () => {
    const input = prompt.trim()
    if (!input || !client || !selectedModel || loadingHistory) return
    let conversation = conversations.find((record) => record.id === activeConversationId)
    if (!conversation) conversation = await createConversation()
    if (!conversation) return
    if (busy && sendMode === 'steer') {
      if (!activeResponseId) return
      void steer(input, conversation, selectedModel, executionMode, activeResponseId)
      return
    }
    const userEntry: ChatEntry = { id: newId(), role: 'user', text: input, items: [], queued: drainingQueue.current }
    setEntries((current) => [...current, userEntry])
    setPrompt('')
    responseQueue.current.push({ userEntryId: userEntry.id, input, modelName: selectedModel, executionMode, conversation })
    setQueuedCount(Math.max(0, responseQueue.current.length - (drainingQueue.current ? 0 : 1)))
    void drainResponseQueue()
  }

  const answerApproval = async (entry: ChatEntry, item: FoundryOutputItem, approve: boolean) => {
    const conversation = conversations.find((record) => record.id === activeConversationId)
    if (!client || !conversation || !selectedModel || !entry.responseId || !item.id || busy) return
    let approvalInput: Record<string, unknown>
    try { approvalInput = buildApprovalInput(item, approve) }
    catch (error) { setFatalError(formatError(error)); return }
    setBusy(true); setFatalError(undefined)
    setEntries((current) => current.map((entryItem) => entryItem.id === entry.id
      ? { ...entryItem, items: entryItem.items.map((toolItem) => toolItem.id === item.id ? { ...toolItem, status: approve ? 'approved' : 'rejected' } : toolItem) }
      : entryItem))
    const assistantId = newId()
    setEntries((current) => [...current, { id: assistantId, role: 'assistant', text: '', items: [], pending: true }])
    try {
      const response = await client.createResponse(conversation.projectId, conversation.id, selectedModel, { input: [approvalInput], execution_mode: executionMode, previous_response_id: entry.responseId, agent_session_id: entry.sessionId }, (event) => updateAssistantDraft(assistantId, event))
      finishResponse(assistantId, response, activeConversationId)
    } catch (error) {
      setEntries((current) => current.map((entryItem) => entryItem.id === assistantId ? { ...entryItem, pending: false, error: formatError(error) } : entryItem))
    } finally { setBusy(false) }
  }

  if (!backendStatus) return <ConnectionScreen config={config} error={backendError} onRetry={refreshBackend} />
  const activeProject = projects.find((item) => item.id === activeProjectId)
  const activeConversation = conversations.find((item) => item.id === activeConversationId)
  const currentUser = backendStatus.user ?? { name: 'Signed-in user', email: '' }

  return <div className="app-shell">
    <header className="topbar">
      <div className="brand-lockup"><div className="brand-mark"><Search size={18} /></div><span>Deep Agent</span></div>
      <div className="account-menu"><div className="account-copy"><strong>{currentUser.name}</strong><span>{currentUser.email}</span></div><div className="account-avatar" aria-label={`${currentUser.name}'s avatar`}>{initials(currentUser)}</div></div>
    </header>
    <div className={`workspace ${filesOpen ? 'files-visible' : ''}`}>
      <aside className={`sidebar ${sidebarOpen ? '' : 'sidebar-collapsed'}`}>
        <div className="sidebar-toolbar"><button className="new-chat-button" onClick={() => setProjectDialogOpen(true)} disabled={busy}><Plus size={17} /><span>New project</span></button><button className="icon-button collapse-button" onClick={() => setSidebarOpen(false)} title="Collapse sidebar"><PanelLeftClose size={18} /></button></div>
        <div className="sidebar-section-title"><span>Projects</span></div>
        <div className="sidebar-content">
          {projects.length ? projects.map((project) => {
            const projectConversations = conversations.filter((record) => record.projectId === project.id)
            const isActive = project.id === activeProjectId
            return <section className={`project-group ${isActive ? 'active' : ''}`} key={project.id}><div className="project-row"><button className="project-select" onClick={() => selectProject(project)}>{isActive ? <FolderOpen size={15} /> : <Folder size={15} />}<span>{project.name}</span></button><div className="project-actions"><button className="row-action project-add" title="New conversation" onClick={() => createConversation(project.id)}><Plus size={14} /></button><button className="row-action" title="Delete project" onClick={() => deleteProject(project)}><Trash2 size={14} /></button></div></div>{isActive && <div className="project-conversations">{projectConversations.length ? projectConversations.map((record) => <div className={`conversation-row ${record.id === activeConversationId ? 'active' : ''}`} key={record.id}><button className="conversation-select" onClick={() => selectConversation(record)}><MessageSquareText size={13} /><span>{record.title}</span><small>{relativeTime(record.updatedAt)}</small></button><button className="row-action" title="Delete conversation" onClick={() => deleteConversation(record)}><Trash2 size={13} /></button></div>) : <button className="empty-project" onClick={() => createConversation(project.id)}><Plus size={13} /> Start a conversation</button>}</div>}</section>
          }) : <EmptySidebar icon={<Folder size={20} />} text="Create a project to organize your research." />}
        </div>
        <div className="sidebar-footer"><ShieldCheck size={15} /> Private project workspace</div>
      </aside>
      <main className="chat-panel">
        {!sidebarOpen && <button className="icon-button sidebar-open-button" onClick={() => setSidebarOpen(true)} title="Open sidebar"><PanelLeftOpen size={19} /></button>}
        <div className="conversation-header"><div><span className="header-kicker">{activeProject?.name ?? 'Project workspace'}</span><h1>{activeConversation?.title ?? (activeProject ? 'Start a conversation' : 'Create a project to begin')}</h1></div><button className={`files-toggle ${filesOpen ? 'active' : ''}`} onClick={toggleFiles} disabled={!activeProject}><FolderTree size={15} /> Files</button></div>
        {fatalError && <ErrorBanner message={fatalError} onClose={() => setFatalError(undefined)} />}
        <div className="message-stream" aria-live="polite">{loadingHistory ? <LoadingState label="Loading conversation" /> : entries.length ? entries.map((entry) => <MessageEntry key={entry.id} entry={entry} busy={busy} onApproval={answerApproval} />) : <WelcomeState onPrompt={setPrompt} />}<div ref={scrollAnchor} /></div>
        <div className="composer-wrap"><div className="composer"><textarea value={prompt} onChange={(event) => setPrompt(event.target.value)} onKeyDown={(event) => { if (event.key === 'Enter' && !event.shiftKey) { event.preventDefault(); void send() } }} rows={1} placeholder="Input your message" disabled={!selectedModel} aria-label="Message" /><div className="composer-controls"><div className="composer-left"><label className="composer-model"><select value={selectedModel} onChange={(event) => setSelectedModel(event.target.value)} disabled={!models.length} aria-label="Model">{models.map((model) => <option key={model.name} value={model.name}>{model.name}</option>)}</select></label><label className="composer-option"><select value={executionMode} onChange={(event) => setExecutionMode(event.target.value as ExecutionMode)} aria-label="Execution mode"><option value="default">Default</option><option value="auto">Auto</option></select></label><label className="composer-option"><select value={sendMode} onChange={(event) => setSendMode(event.target.value as SendMode)} aria-label="Send behavior"><option value="queue">Queue</option><option value="steer">Steer</option></select></label>{queuedCount > 0 && <span className="queue-count">{queuedCount} queued</span>}</div><button className="send-button" onClick={send} disabled={!prompt.trim() || !selectedModel || loadingHistory || (busy && sendMode === 'steer' && !activeResponseId)} title={busy ? (sendMode === 'steer' ? 'Steer active response' : 'Queue message') : 'Send message'}><Send size={18} /></button></div></div></div>
      </main>
      {filesOpen && activeProject && <aside className="files-panel"><div className="files-panel-header"><div><span className="header-kicker">Project files</span><strong>{activeProject.name}</strong></div><div><button className="icon-button" title="Refresh files" onClick={() => loadDirectory(activeProject.id, '/')}><RefreshCw size={15} className={loadingPaths.includes('/') ? 'spin' : ''} /></button><button className="icon-button" title="Close files" onClick={() => setFilesOpen(false)}><PanelRightClose size={17} /></button></div></div><div className="file-tree" role="tree">{loadingPaths.includes('/') && !filesByPath['/'] ? <LoadingState label="Loading files" /> : filesByPath['/']?.length ? <FileTree path="/" filesByPath={filesByPath} expandedPaths={expandedPaths} loadingPaths={loadingPaths} downloadingPath={downloadingPath} previewLoading={previewLoading} onToggle={toggleDirectory} onDownload={downloadFile} onPreview={previewTextFile} /> : <EmptySidebar icon={<FolderTree size={20} />} text="This project has no files yet." />}</div></aside>}
    </div>
    {projectDialogOpen && <div className="dialog-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) setProjectDialogOpen(false) }}><form className="project-dialog" role="dialog" aria-modal="true" aria-labelledby="project-dialog-title" onSubmit={(event) => { event.preventDefault(); void createProject() }}><div className="dialog-heading"><div><span className="header-kicker">Research workspace</span><h2 id="project-dialog-title">Create a project</h2></div><button type="button" className="icon-button" title="Close" onClick={() => setProjectDialogOpen(false)}><X size={17} /></button></div><label htmlFor="project-name">Project name</label><input id="project-name" autoFocus value={projectName} onChange={(event) => setProjectName(event.target.value)} maxLength={100} placeholder="e.g. Consumer AI landscape" /><p>Conversations in this project share files and working context.</p><div className="dialog-actions"><button type="button" className="dialog-cancel" onClick={() => setProjectDialogOpen(false)}>Cancel</button><button type="submit" className="dialog-submit" disabled={!projectName.trim() || busy}>{busy ? <LoaderCircle size={15} className="spin" /> : <Plus size={15} />} Create project</button></div></form></div>}
    {previewFile && <div className="file-viewer-backdrop"><section className="file-viewer" role="dialog" aria-modal="true" aria-labelledby="file-viewer-title"><header><div><span className="header-kicker">Text preview</span><h2 id="file-viewer-title">{previewFile.name}</h2><small>{previewFile.path} · {formatBytes(previewFile.size)}</small></div><div><button className="icon-button" title={`Download ${previewFile.name}`} onClick={() => downloadFile(previewFile)}><Download size={16} /></button><button className="icon-button" title="Close preview" onClick={() => { setPreviewFile(undefined); setPreviewContent('') }}><X size={17} /></button></div></header><pre>{previewLoading ? 'Loading file…' : previewContent}</pre></section></div>}
  </div>
}

function ConnectionScreen({ config, error, onRetry }: { config: AppConfig; error?: string; onRetry: () => void }) {
  return <main className="login-page"><div className="login-grid" aria-hidden="true" /><section className="login-content"><div className="brand-lockup login-brand"><div className="brand-mark"><Search size={19} /></div><span>Deep Agent</span></div><p className="login-kicker">Deep research, grounded in current sources</p><h1>Give complex questions<br />room to unfold.</h1><p className="login-description">A focused workspace for the <strong>{config.agentName}</strong> agent. The local backend authenticates with your Azure developer credential and keeps tokens out of the browser.</p>{error ? <><div className="login-error"><AlertCircle size={16} /> {error}</div><button className="login-button" onClick={onRetry}><RefreshCw size={18} /> Retry connection</button></> : <div className="connection-progress"><LoaderCircle className="spin" size={18} /> Connecting with DefaultAzureCredential</div>}<div className="login-capabilities"><span><Search size={15} /> Managed web search</span><span><TerminalSquare size={15} /> Approved terminal access</span><span><Archive size={15} /> Persistent project files</span></div></section><aside className="login-aside"><div className="field-note"><span>FIELD NOTE 06</span><blockquote>“Research is formalized curiosity. It is poking and prying with a purpose.”</blockquote><cite>Zora Neale Hurston</cite></div><div className="contour-lines" /></aside></main>
}

function MessageEntry({ entry, busy, onApproval }: { entry: ChatEntry; busy: boolean; onApproval: (entry: ChatEntry, item: FoundryOutputItem, approve: boolean) => void }) {
  const visibleItems = entry.items.filter((item) => item.type !== 'message')
  if (entry.role === 'user') return <article className="message user-message"><div className="avatar user-avatar"><User size={15} /></div><div><p>{entry.text}</p>{entry.queued && <span className="queued-label">Queued</span>}</div></article>
  return <article className="message assistant-message"><div className="avatar agent-avatar"><Bot size={16} /></div><div className="assistant-body">{visibleItems.length > 0 && <div className="tool-stack">{visibleItems.map((item, index) => <ToolItem key={item.id ?? `${item.type}-${index}`} item={item} response={entry} busy={busy} onApproval={onApproval} />)}</div>}{entry.text && <div className="markdown-body"><ReactMarkdown remarkPlugins={[remarkGfm]}>{entry.text}</ReactMarkdown></div>}{entry.error && <div className="entry-error"><AlertCircle size={16} /> {entry.error}</div>}{entry.steered && <span className="steered-label">Steered</span>}{entry.pending && <Thinking />}</div></article>
}

function ToolItem({ item, response, busy, onApproval }: { item: FoundryOutputItem; response: ChatEntry; busy: boolean; onApproval: (entry: ChatEntry, item: FoundryOutputItem, approve: boolean) => void }) {
  const [expanded, setExpanded] = useState(item.type === 'mcp_approval_request')
  const isApproval = item.type === 'mcp_approval_request'
  const approvalResolved = isApproval && (item.status === 'approved' || item.status === 'rejected')
  const isCall = item.type.includes('call') || item.type === 'function_call'
  const decide = (approve: boolean) => { setExpanded(false); onApproval(response, item, approve) }
  return <div className={`tool-item ${isApproval ? 'approval-item' : ''}`}><button className="tool-summary" onClick={() => setExpanded((value) => !value)}><span className="tool-icon">{isApproval ? <ShieldCheck size={15} /> : isCall ? <Code2 size={15} /> : <FileText size={15} />}</span><span className="tool-label">{approvalResolved ? `Approval ${item.status}` : isApproval ? 'Approval required' : item.name || humanize(item.type)}</span><span className="tool-status">{item.status || (isApproval ? 'waiting' : 'completed')}</span>{expanded ? <ChevronDown size={15} /> : <ChevronRight size={15} />}</button>{expanded && <div className="tool-details"><pre>{prettyDetails(item)}</pre>{isApproval && !approvalResolved && <div className="approval-actions"><button className="reject-button" disabled={busy} onClick={() => decide(false)}><X size={15} /> Reject</button><button className="approve-button" disabled={busy} onClick={() => decide(true)}><Check size={15} /> Approve</button></div>}</div>}</div>
}

function FileTree({ path, filesByPath, expandedPaths, loadingPaths, downloadingPath, previewLoading, onToggle, onDownload, onPreview }: { path: string; filesByPath: Record<string, ProjectFile[]>; expandedPaths: string[]; loadingPaths: string[]; downloadingPath?: string; previewLoading: boolean; onToggle: (entry: ProjectFile) => void; onDownload: (entry: ProjectFile) => void; onPreview: (entry: ProjectFile) => void }) {
  return <ul>{(filesByPath[path] ?? []).map((entry) => { const previewable = canPreviewText(entry); return <li key={entry.path} role="treeitem" aria-expanded={entry.isDirectory ? expandedPaths.includes(entry.path) : undefined}><div className="file-row">{entry.isDirectory ? <button className="file-entry" onClick={() => onToggle(entry)}>{expandedPaths.includes(entry.path) ? <ChevronDown size={13} /> : <ChevronRight size={13} />}<Folder size={14} /><span>{entry.name}</span></button> : <button className={`file-entry file-entry-static ${previewable ? 'previewable' : ''}`} title={previewable ? 'Double-click to open' : 'Download only'} onDoubleClick={() => onPreview(entry)} onKeyDown={(event) => { if (previewable && event.key === 'Enter') onPreview(entry) }} disabled={previewLoading}><span className="file-indent" /><FileText size={14} /><span>{entry.name}</span><small>{formatBytes(entry.size)}</small></button>}{!entry.isDirectory && <button className="file-download" title={`Download ${entry.name}`} onClick={() => onDownload(entry)} disabled={downloadingPath === entry.path}>{downloadingPath === entry.path ? <LoaderCircle size={14} className="spin" /> : <Download size={14} />}</button>}</div>{entry.isDirectory && expandedPaths.includes(entry.path) && <div className="file-children">{loadingPaths.includes(entry.path) && !filesByPath[entry.path] ? <LoadingState label="Loading folder" /> : <FileTree path={entry.path} filesByPath={filesByPath} expandedPaths={expandedPaths} loadingPaths={loadingPaths} downloadingPath={downloadingPath} previewLoading={previewLoading} onToggle={onToggle} onDownload={onDownload} onPreview={onPreview} />}</div>}</li> })}</ul>
}

function WelcomeState({ onPrompt }: { onPrompt: (value: string) => void }) {
  const prompts = ['Compare the latest approaches to small language models on consumer devices.', 'Research current Foundry hosted-agent capabilities using official sources.', 'Map the tradeoffs between project memory and conversation history.']
  return <section className="welcome-state"><div className="prompt-list">{prompts.map((item) => <button key={item} onClick={() => onPrompt(item)}>{item}<ChevronRight size={16} /></button>)}</div></section>
}

function EmptySidebar({ icon, text }: { icon: ReactNode; text: string }) { return <div className="empty-sidebar">{icon}<span>{text}</span></div> }
function ErrorBanner({ message, onClose }: { message: string; onClose: () => void }) { return <div className="banner error-banner"><AlertCircle size={17} /><span>{message}</span><button onClick={onClose}><X size={15} /></button></div> }
function LoadingState({ label }: { label: string }) { return <div className="loading-state"><LoaderCircle className="spin" size={20} /> {label}</div> }
function Thinking() { return <div className="thinking" aria-label="Agent is working"><span /><span /><span /></div> }
function itemToChatEntry(item: FoundryOutputItem): ChatEntry { return { id: item.id ?? newId(), role: item.role === 'user' ? 'user' : 'assistant', text: getItemText(item), items: item.type === 'message' ? [] : [item] } }
function prettyDetails(item: FoundryOutputItem) { const value = item.arguments ?? item.output ?? item.content ?? item; if (typeof value === 'string') { try { return JSON.stringify(JSON.parse(value), null, 2) } catch { return value } } return JSON.stringify(value, null, 2) }
function buildApprovalInput(item: FoundryOutputItem, approve: boolean): Record<string, unknown> {
  const envelope = typeof item.arguments === 'string' ? JSON.parse(item.arguments) as unknown : item.arguments
  if (!envelope || typeof envelope !== 'object') throw new Error('The approval request is missing its LangGraph interrupt payload.')
  const interruptId = (envelope as { interrupt_id?: unknown }).interrupt_id
  const value = (envelope as { value?: unknown }).value
  if (typeof interruptId !== 'string' || !interruptId) throw new Error('The approval request is missing its LangGraph interrupt ID.')
  const actionRequests = value && typeof value === 'object' ? (value as { action_requests?: unknown }).action_requests : undefined
  const decisionCount = Array.isArray(actionRequests) ? actionRequests.length : 1
  const decisions = Array.from({ length: Math.max(1, decisionCount) }, () => ({ type: approve ? 'approve' : 'reject' }))
  return {
    type: 'function_call_output',
    call_id: interruptId,
    output: JSON.stringify({ resume: { decisions } }),
  }
}
function humanize(value: string) { return value.replaceAll('_', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase()) }
function relativeTime(timestamp: string | number) { const value = typeof timestamp === 'number' ? timestamp : new Date(timestamp).getTime(); const minutes = Math.floor((Date.now() - value) / 60_000); if (minutes < 1) return 'now'; if (minutes < 60) return `${minutes}m`; const hours = Math.floor(minutes / 60); return hours < 24 ? `${hours}h` : `${Math.floor(hours / 24)}d` }
function formatBytes(bytes: number) { if (bytes < 1024) return `${bytes} B`; if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`; return `${(bytes / (1024 * 1024)).toFixed(1)} MB` }
function canPreviewText(file: ProjectFile) { const name = file.name.toLowerCase(); const suffix = name.includes('.') ? name.slice(name.lastIndexOf('.')) : ''; return !file.isDirectory && file.size < 1024 * 1024 && (TEXT_FILE_SUFFIXES.has(suffix) || TEXT_FILE_NAMES.has(name)) }
const TEXT_FILE_SUFFIXES = new Set(['.bat', '.c', '.cfg', '.conf', '.cpp', '.cs', '.css', '.csv', '.env', '.go', '.h', '.hpp', '.html', '.ini', '.java', '.js', '.json', '.jsx', '.log', '.md', '.mjs', '.ps1', '.py', '.rb', '.rs', '.sh', '.sql', '.toml', '.ts', '.tsx', '.txt', '.xml', '.yaml', '.yml'])
const TEXT_FILE_NAMES = new Set(['dockerfile', 'makefile', 'readme', 'license'])
function initials(user: BackendStatus['user']) { const parts = user.name.trim().split(/\s+/).filter(Boolean); if (parts.length > 1) return `${parts[0][0]}${parts.at(-1)?.[0]}`.toUpperCase(); const source = parts[0] || user.email.split('@')[0] || 'U'; return source.slice(0, 2).toUpperCase() }

export default App