import { mkdirSync, writeFileSync } from 'node:fs'
import path from 'node:path'

const config = {
  agentName: process.env.AGENT_LANGGRAPH_DEEP_AGENTS_NAME || 'langgraph-deep-agents',
  apiBaseUrl: '/api',
  environment: process.env.AZURE_ENV_NAME || 'local',
}

const publicDirectory = path.resolve('public')
mkdirSync(publicDirectory, { recursive: true })
writeFileSync(path.join(publicDirectory, 'config.json'), `${JSON.stringify(config, null, 2)}\n`)
console.log('Generated public/config.json from the active azd environment.')