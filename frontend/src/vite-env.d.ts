/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_API_BASE_URL: string
  readonly VITE_WS_BASE_URL: string
  readonly VITE_BEHIND_PROXY: string
  readonly VITE_PROXY_HOST: string
  readonly VITE_PROXY_PROTOCOL: string
  // Add more env variables as needed
  
  // Keep compatibility with REACT_APP_ prefixed variables
  readonly REACT_APP_API_BASE_URL: string
  readonly REACT_APP_WS_BASE_URL: string
  readonly REACT_APP_AUTO_DETECT_BACKEND: string
  readonly REACT_APP_VERSION: string
  readonly REACT_APP_BEHIND_PROXY: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}