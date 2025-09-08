import axios, { AxiosInstance, AxiosRequestConfig, AxiosResponse } from 'axios';
import { store } from './index';
import { refreshAccessToken, clearAuth, stopImpersonation } from './slices/authSlice';

// Get environment variable with Vite/CRA/Jest compatibility
const getEnvVar = (viteKey: string, craKey: string, defaultValue: string = ''): string => {
  // Check if we're in Jest testing environment first
  if (typeof process !== 'undefined' && process.env.NODE_ENV === 'test') {
    return (process.env as any)[craKey] || defaultValue;
  }
  
  // Check if we're in Vite environment (using dynamic access to avoid Jest parsing errors)
  const importMeta = (globalThis as any).import?.meta || (typeof window !== 'undefined' && (window as any).import?.meta);
  if (importMeta && importMeta.env) {
    return importMeta.env[viteKey] || importMeta.env[craKey] || defaultValue;
  }
  
  // Fallback to process.env for CRA and other environments
  return (process.env as any)[craKey] || defaultValue;
};

// Dynamic API base URL detection for remote access
const getAPIBaseURL = (): string => {
  const envBaseURL = getEnvVar('VITE_API_BASE_URL', 'REACT_APP_API_BASE_URL', '/api/v1');
  const autoDetect = getEnvVar('VITE_AUTO_DETECT_BACKEND', 'REACT_APP_AUTO_DETECT_BACKEND', 'true') === 'true';
  const behindProxy = getEnvVar('VITE_BEHIND_PROXY', 'REACT_APP_BEHIND_PROXY', 'false') === 'true';
  
  if (autoDetect && typeof window !== 'undefined') {
    const currentHostname = window.location.hostname;
    const currentProtocol = window.location.protocol;
    const currentPort = window.location.port;
    
    // Use current hostname for backend API
    if (currentHostname !== 'localhost' && currentHostname !== '127.0.0.1') {
      // Parse the env base URL to extract the path
      try {
        // If envBaseURL is a relative path, use it directly
        const apiPath = envBaseURL.startsWith('/') ? envBaseURL : 
                       (new URL(envBaseURL).pathname || '/api/v1');
        
        // Detect if we're behind a reverse proxy
        // Check explicit env variable first, then auto-detect based on connection patterns
        
        // Direct development connections typically use non-standard ports (3001, 4000, 5000, etc.)
        const isDirectDevConnection = currentPort && !['80', '443'].includes(currentPort);
        
        // Standard proxy ports indicate we're behind a reverse proxy
        const isStandardPort = 
          (currentProtocol === 'https:' && (!currentPort || currentPort === '443')) ||
          (currentProtocol === 'http:' && (!currentPort || currentPort === '80'));
        
        // Determine if we're behind a proxy:
        // 1. Explicit env variable override
        // 2. Standard ports (80/443) indicate proxy
        // 3. Direct dev connections (non-standard ports) are NOT proxied
        const isProxied = behindProxy || (isStandardPort && !isDirectDevConnection);
        
        if (isProxied) {
          // Behind reverse proxy - use same host and port as frontend
          const portPart = currentPort ? `:${currentPort}` : '';
          return `${currentProtocol}//${currentHostname}${portPart}${apiPath}`;
        } else {
          // Direct access - use port 3000 for backend
          return `${currentProtocol}//${currentHostname}:3000${apiPath}`;
        }
      } catch (e) {
        // Fallback if URL parsing fails
        const fallback = `${currentProtocol}//${currentHostname}:3000/api/v1`;
        return fallback;
      }
    }
  }
  return envBaseURL;
};


class APIClient {
  private client: AxiosInstance;
  private isRefreshing = false;
  private failedQueue: Array<{
    resolve: (value: unknown) => void;
    reject: (error: unknown) => void;
  }> = [];

  constructor(baseURL: string) {
    this.client = axios.create({
      baseURL,
      timeout: 30000,
      headers: {
        'Content-Type': 'application/json',
      },
    });

    this.setupInterceptors();
  }

  private setupInterceptors() {
    // Request interceptor to add auth token
    this.client.interceptors.request.use(
      (config) => {
        const state = store.getState();
        
        // Use impersonation token if active, otherwise use regular access token
        let token = state.auth.accessToken;
        const impersonationToken = localStorage.getItem('impersonationToken');
        if (state.auth.impersonation.isImpersonating && impersonationToken) {
          token = impersonationToken;
        }
        
        
        if (token) {
          config.headers.Authorization = `Bearer ${token}`;
        }

        return config;
      },
      (error) => Promise.reject(error)
    );

    // Response interceptor to handle token refresh
    this.client.interceptors.response.use(
      (response) => response,
      async (error) => {
        const originalRequest = error.config;

        if (error.response?.status === 401 && !originalRequest._retry) {
          const state = store.getState();
          
          // If we're impersonating and get 401, the impersonation session is invalid
          if (state.auth.impersonation.isImpersonating) {
            try {
              // Try to gracefully end the impersonation session
              await store.dispatch(stopImpersonation());
            } catch (stopError) {
              store.dispatch(clearAuth());
            }
            return Promise.reject(error);
          }
          
          if (this.isRefreshing) {
            // If refresh is already in progress, queue the request
            return new Promise((resolve, reject) => {
              this.failedQueue.push({ resolve, reject });
            }).then((token) => {
              originalRequest.headers.Authorization = `Bearer ${token}`;
              return this.client(originalRequest);
            }).catch((err) => {
              return Promise.reject(err);
            });
          }

          originalRequest._retry = true;
          this.isRefreshing = true;

          try {
            const resultAction = await store.dispatch(refreshAccessToken());
            
            if (refreshAccessToken.fulfilled.match(resultAction)) {
              const token = resultAction.payload.access_token;
              
              // Process queued requests
              this.failedQueue.forEach(({ resolve }) => resolve(token));
              this.failedQueue = [];
              
              originalRequest.headers.Authorization = `Bearer ${token}`;
              return this.client(originalRequest);
            } else {
              // Refresh failed, logout user
              store.dispatch(clearAuth());
              return Promise.reject(error);
            }
          } catch (refreshError) {
            // Refresh failed, logout user
            this.failedQueue.forEach(({ reject }) => reject(refreshError));
            this.failedQueue = [];
            
            store.dispatch(clearAuth());
            return Promise.reject(refreshError);
          } finally {
            this.isRefreshing = false;
          }
        }

        return Promise.reject(error);
      }
    );
  }

  // HTTP Methods
  async get<T = any>(url: string, config?: AxiosRequestConfig): Promise<AxiosResponse<T>> {
    return this.client.get(url, config);
  }

  async post<T = any>(url: string, data?: any, config?: AxiosRequestConfig): Promise<AxiosResponse<T>> {
    return this.client.post(url, data, config);
  }

  async put<T = any>(url: string, data?: any, config?: AxiosRequestConfig): Promise<AxiosResponse<T>> {
    return this.client.put(url, data, config);
  }

  async patch<T = any>(url: string, data?: any, config?: AxiosRequestConfig): Promise<AxiosResponse<T>> {
    return this.client.patch(url, data, config);
  }

  async delete<T = any>(url: string, config?: AxiosRequestConfig): Promise<AxiosResponse<T>> {
    return this.client.delete(url, config);
  }
}

const API_BASE_URL = getAPIBaseURL();

// API Client Configuration initialized (debug logs removed for production)

export const api = new APIClient(API_BASE_URL);
export default api;