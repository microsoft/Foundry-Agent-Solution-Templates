import '@fontsource-variable/manrope'
import '@fontsource-variable/newsreader'
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App'
import { loadConfig } from './config'
import './index.css'

const root = createRoot(document.getElementById('root')!)

async function bootstrap() {
  try {
    root.render(<StrictMode><App config={await loadConfig()} /></StrictMode>)
  } catch (error) {
    root.render(<main className="configuration-error"><strong>Deep Agent could not start</strong><p>{error instanceof Error ? error.message : 'Invalid frontend configuration.'}</p></main>)
  }
}

void bootstrap()