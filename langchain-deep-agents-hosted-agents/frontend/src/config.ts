export type AppConfig = {
  agentName: string
  apiBaseUrl: string
  environment: string
}

export async function loadConfig(): Promise<AppConfig> {
  const response = await fetch('/config.json', { cache: 'no-store' })
  if (!response.ok) {
    throw new Error('Missing /config.json. Run the azd provisioning workflow to configure the frontend.')
  }

  const config = await response.json() as Partial<AppConfig>
  const required: (keyof AppConfig)[] = ['agentName', 'apiBaseUrl', 'environment']
  const missing = required.filter((key) => !config[key])
  if (missing.length) throw new Error(`Frontend configuration is missing: ${missing.join(', ')}`)
  return config as AppConfig
}