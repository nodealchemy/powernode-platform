import axios, { AxiosInstance, AxiosRequestConfig, AxiosResponse } from 'axios';
import { store } from './index';
import { refreshAccessToken, clearAuth, stopImpersonation } from './slices/authSlice';

// Dynamic API base URL detection for remote access
const getAPIBaseURL = (): string => {
  const envBaseURL = process.env.REACT_APP_API_BASE_URL || 'http://localhost:3000/api/v1';
  const autoDetect = process.env.REACT_APP_AUTO_DETECT_BACKEND === 'true';
  
  if (autoDetect && typeof window !== 'undefined') {
    const currentHostname = window.location.hostname;
    const currentProtocol = window.location.protocol;
    
    // Use current hostname with port 3000 for backend
    if (currentHostname !== 'localhost' && currentHostname !== '127.0.0.1') {
      // Parse the env base URL to extract the path
      try {
        const envUrl = new URL(envBaseURL);
        const apiPath = envUrl.pathname || '/api/v1';
        const result = `${currentProtocol}//${currentHostname}:3000${apiPath}`;
        return result;
      } catch (e) {
        // Fallback if URL parsing fails
        const fallback = `${currentProtocol}//${currentHostname}:3000/api/v1`;
        return fallback;
      }
    }
  }
  return envBaseURL;
};

// Log the API base URL in development
if (process.env.NODE_ENV === 'development') {
}

class APIClient {
  private client: AxiosInstance;
  private isRefreshing = false;
  private failedQueue: Array<{
    resolve: (value: any) => void;
    reject: (error: any) => void;
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
        if (state.auth.impersonation.isImpersonating && state.auth.impersonation.sessionId) {
          token = state.auth.impersonation.sessionId;
        } else {
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

export const api = new APIClient(API_BASE_URL);
export default api;