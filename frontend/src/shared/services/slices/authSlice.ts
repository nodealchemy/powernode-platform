import { createSlice, createAsyncThunk } from '@reduxjs/toolkit';
import { authApi, AuthResponse } from '@/features/account/auth/services/authAPI';
import { impersonationApi } from '@/shared/services/account/impersonationApi';
import { setAuthDomain, clearAuthDomain } from '@/shared/utils/domainUtils';
import { getErrorMessage, isErrorWithResponse } from '@/shared/utils/errorHandling';

export interface User {
  id: string;
  email: string;
  name: string;
  full_name?: string;  // Full name returned from backend (typically same as name)
  roles: string[];  // Array of role names (e.g., ['system.admin', 'account.manager'])
  permissions?: string[];  // Array of permission strings (e.g., ['users.create', 'billing.read']) - optional as not always returned
  status: string;
  email_verified: boolean;
  account: {
    id: string;
    name: string;
    status: string;
  };
}

export interface ImpersonationState {
  isImpersonating: boolean;
  originalUser: User | null;
  impersonatedUser: User | null;
  sessionId: string | null;
  startedAt: string | null;
  expiresAt: string | null;
}

interface AuthState {
  user: User | null;
  access_token: string | null;
  refresh_token: string | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  error: string | null;
  resendingVerification: boolean;
  resendVerificationSuccess: boolean;
  resendCooldown: number;
  impersonation: ImpersonationState;
}

const getInitialState = (): AuthState => {
  const access_token = localStorage.getItem('access_token');
  const refresh_token = localStorage.getItem('refresh_token');
  const impersonationToken = localStorage.getItem('impersonationToken');
  
  return {
    user: null,
    access_token,
    refresh_token,
    isAuthenticated: !!access_token,
    isLoading: false,
    error: null,
    resendingVerification: false,
    resendVerificationSuccess: false,
    resendCooldown: 0,
    impersonation: {
      isImpersonating: !!impersonationToken,
      originalUser: null,
      impersonatedUser: null,
      sessionId: impersonationToken || null,
      startedAt: null,
      expiresAt: null,
    },
  };
};

const initialState: AuthState = getInitialState();

// Async thunks
export const login = createAsyncThunk(
  'auth/login',
  async ({ email, password }: { email: string; password: string }) => {
    const response = await authApi.login({ email, password });
    // Backend returns {success: true, data: {...}}, we need to unwrap the nested data
    return response.data.data || response.data;
  }
);

export const register = createAsyncThunk(
  'auth/register',
  async (userData: {
    email: string;
    password: string;
    name: string;
    account_name: string;
    plan_id?: string;
    billing_cycle?: string;
  }, { rejectWithValue }) => {
    try {
      const response = await authApi.register(userData);
      // Backend returns {success: true, data: {...}}, we need to unwrap the nested data
      return response.data.data || response.data;
    } catch (error) {
      // Handle HTTP errors properly
      if (isErrorWithResponse(error) && error.response?.data) {
        return rejectWithValue(error.response.data);
      }
      return rejectWithValue({ error: getErrorMessage(error) || 'Registration failed' });
    }
  }
);

export const logout = createAsyncThunk('auth/logout', async () => {
  await authApi.logout();
});

export const refreshAccessToken = createAsyncThunk(
  'auth/refreshToken',
  async (_, { getState, rejectWithValue }) => {
    try {
      const state = getState() as { auth: AuthState };
      const refresh_token = state.auth.refresh_token;

      if (!refresh_token) {
        throw new Error('No refresh token available');
      }

      const response = await authApi.refreshToken(refresh_token);
      // Backend returns {success: true, data: {...}}, we need to unwrap the nested data
      return response.data.data || response.data;
    } catch (error) {
      const errorMessage = isErrorWithResponse(error)
        ? (error.response?.data?.error || error.response?.data?.message || 'Token refresh failed')
        : getErrorMessage(error);

      // Check for signature verification failure or other token invalidity issues
      if (errorMessage.includes('Signature verification failed') ||
          errorMessage.includes('Invalid token') ||
          errorMessage.includes('Invalid refresh token')) {
        // These errors indicate the token is fundamentally invalid (wrong secret, corrupted, etc.)
        // Clear tokens immediately rather than retrying
        return rejectWithValue({ clearTokens: true, message: errorMessage });
      }

      return rejectWithValue({ clearTokens: false, message: errorMessage });
    }
  }
);

export const getCurrentUser = createAsyncThunk(
  'auth/getCurrentUser',
  async (silentAuth: boolean = false, { rejectWithValue }) => {
    try {
      const response = await authApi.getCurrentUser(silentAuth);
      // Backend returns {success: true, data: {...}}, we need to unwrap the nested data
      const data = response.data as AuthResponse;
      return data.data || data;
    } catch (error) {
      const errorMessage = isErrorWithResponse(error)
        ? (error.response?.data?.error || error.response?.data?.message || 'Failed to get current user')
        : getErrorMessage(error);

      // Check for token invalidity issues that require immediate token clearance
      if (isErrorWithResponse(error) && error.response?.status === 401 &&
          (errorMessage.includes('Invalid token') ||
           errorMessage.includes('Signature verification failed') ||
           errorMessage.includes('Token has been blacklisted'))) {
        return rejectWithValue({ clearTokens: true, message: errorMessage });
      }

      return rejectWithValue({ clearTokens: false, message: errorMessage });
    }
  }
);

export const resendVerificationEmail = createAsyncThunk(
  'auth/resendVerificationEmail',
  async (_, { rejectWithValue }) => {
    try {
      const response = await authApi.resendVerification();
      // Backend returns {success: true, data: {...}}, we need to unwrap the nested data
      const data = response.data as AuthResponse;
      return data.data || data;
    } catch (error) {
      return rejectWithValue(
        isErrorWithResponse(error) && error.response?.data?.error
          ? error.response.data.error
          : 'Failed to resend verification email'
      );
    }
  }
);

// Impersonation async thunks
export const startImpersonation = createAsyncThunk(
  'auth/startImpersonation',
  async ({ user_id, reason }: { user_id: string; reason?: string }, { getState, rejectWithValue }) => {
    try {
      const state = getState() as { auth: AuthState };
      const originalUser = state.auth.user;
      
      const response = await impersonationApi.startImpersonation({ user_id, reason });
      
      if (!response.success || !response.data) {
        throw new Error(response.error || 'Failed to start impersonation');
      }
      
      return {
        ...response.data,
        originalUser,
      };
    } catch (error) {
      return rejectWithValue(getErrorMessage(error) || 'Failed to start impersonation');
    }
  }
);

export const stopImpersonation = createAsyncThunk(
  'auth/stopImpersonation',
  async (_, { rejectWithValue }) => {
    try {
      const sessionToken = localStorage.getItem('impersonationToken') || '';

      if (!sessionToken) {
        throw new Error('No active impersonation session');
      }

      const response = await impersonationApi.stopImpersonation(sessionToken);

      if (!response.success) {
        throw new Error(response.error || 'Failed to stop impersonation');
      }

      return response.data;
    } catch (error) {
      return rejectWithValue(getErrorMessage(error) || 'Failed to stop impersonation');
    }
  }
);

export const checkImpersonationStatus = createAsyncThunk(
  'auth/checkImpersonationStatus',
  async (_, { rejectWithValue }) => {
    try {
      const impersonationToken = localStorage.getItem('impersonationToken');
      
      if (!impersonationToken) {
        return null;
      }
      
      const response = await impersonationApi.validateToken(impersonationToken);
      
      if (!response.success) {
        throw new Error(response.error || 'Failed to validate impersonation token');
      }
      
      // CRITICAL FIX: Backend returns 'valid' at top level, but also include session data
      return {
        valid: response.valid || false,
        session: response.data?.session || null,
        expires_at: response.data?.expires_at || null
      };
    } catch (error) {
      return rejectWithValue(
        isErrorWithResponse(error) && error.response?.data?.error
          ? error.response.data.error
          : 'Failed to get impersonation session'
      );
    }
  }
);

export const verify2FA = createAsyncThunk(
  'auth/verify2FA',
  async ({ verificationToken, code }: { verificationToken: string; code: string }, { rejectWithValue }) => {
    try {
      const response = await authApi.verify2FA(verificationToken, code);
      // Backend returns {success: true, data: {...}}, we need to unwrap the nested data
      return response.data.data || response.data;
    } catch (error) {
      return rejectWithValue(
        isErrorWithResponse(error)
          ? (error.response?.data?.error || error.response?.data?.message || '2FA verification failed')
          : getErrorMessage(error)
      );
    }
  }
);

const authSlice = createSlice({
  name: 'auth',
  initialState,
  reducers: {
    clearError: (state) => {
      state.error = null;
    },
    clearAuth: (state) => {
      state.user = null;
      state.access_token = null;
      state.refresh_token = null;
      state.isAuthenticated = false;
      state.error = null;
      state.resendingVerification = false;
      state.resendVerificationSuccess = false;
      state.resendCooldown = 0;
      state.impersonation = {
        isImpersonating: false,
        originalUser: null,
        impersonatedUser: null,
        sessionId: null,
        startedAt: null,
        expiresAt: null,
      };
      localStorage.removeItem('access_token');
      localStorage.removeItem('refresh_token');
      localStorage.removeItem('impersonationToken');
      clearAuthDomain();
    },
    forceTokenClear: (state) => {
      // Force clear tokens immediately, useful for handling invalid signatures
      // CRITICAL FIX: Don't clear impersonation token - it should be validated separately
      state.user = null;
      state.access_token = null;
      state.refresh_token = null;
      state.isAuthenticated = false;
      state.error = 'Session expired. Please log in again.';
      // DON'T reset impersonation state here - let it be validated separately
      localStorage.removeItem('access_token');
      localStorage.removeItem('refresh_token');
      // localStorage.removeItem('impersonationToken'); // REMOVED - preserve for validation
    },
    clearResendVerificationSuccess: (state) => {
      state.resendVerificationSuccess = false;
    },
    decrementResendCooldown: (state) => {
      if (state.resendCooldown > 0) {
        state.resendCooldown -= 1;
      }
    },
  },
  extraReducers: (builder) => {
    builder
      // Login
      .addCase(login.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(login.fulfilled, (state, action) => {
        state.isLoading = false;
        state.isAuthenticated = true;
        state.user = action.payload.user || null;
        state.access_token = action.payload.access_token || null;
        state.refresh_token = action.payload.refresh_token || null;
        
        if (action.payload.access_token) {
          localStorage.setItem('access_token', action.payload.access_token);
        }
        if (action.payload.refresh_token) {
          localStorage.setItem('refresh_token', action.payload.refresh_token);
        }
        
        // Track the domain where authentication was established
        setAuthDomain();
      })
      .addCase(login.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.error.message || 'Login failed';
      })
      
      // Register
      .addCase(register.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(register.fulfilled, (state, action) => {
        state.isLoading = false;
        state.isAuthenticated = true;
        state.user = action.payload.user || null;
        state.access_token = action.payload.access_token || null;
        state.refresh_token = action.payload.refresh_token || null;
        
        if (action.payload.access_token) {
          localStorage.setItem('access_token', action.payload.access_token);
        }
        if (action.payload.refresh_token) {
          localStorage.setItem('refresh_token', action.payload.refresh_token);
        }
      })
      .addCase(register.rejected, (state, action) => {
        state.isLoading = false;
        // Better error handling for registration failures
        let errorMessage = 'Registration failed';
        
        if (action.payload && typeof action.payload === 'object') {
          const payload = action.payload as { error?: string; message?: string };
          if (payload.error) {
            errorMessage = payload.error;
          } else if (payload.message) {
            errorMessage = payload.message;
          }
        } else if (action.error) {
          if (action.error.message) {
            errorMessage = action.error.message;
          }
        }
        
        state.error = errorMessage;
      })
      
      // Logout
      .addCase(logout.fulfilled, (state) => {
        state.user = null;
        state.access_token = null;
        state.refresh_token = null;
        state.isAuthenticated = false;
        localStorage.removeItem('access_token');
        localStorage.removeItem('refresh_token');
      })

      // Refresh token
      .addCase(refreshAccessToken.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(refreshAccessToken.fulfilled, (state, action) => {
        state.isLoading = false;
        state.access_token = action.payload.access_token || null;
        state.refresh_token = action.payload.refresh_token || null;

        if (action.payload.access_token) {
          localStorage.setItem('access_token', action.payload.access_token);
        }
        if (action.payload.refresh_token) {
          localStorage.setItem('refresh_token', action.payload.refresh_token);
        }
      })
      .addCase(refreshAccessToken.rejected, (state, action) => {
        state.isLoading = false;
        const payload = action.payload as { clearTokens: boolean; message: string } | string;

        // Always clear tokens on refresh failure, but handle enhanced error info if available
        state.user = null;
        state.access_token = null;
        state.refresh_token = null;
        state.isAuthenticated = false;
        state.error = typeof payload === 'object' ? payload.message : (payload || 'Token refresh failed');
        localStorage.removeItem('access_token');
        localStorage.removeItem('refresh_token');
      })

      // Get current user
      .addCase(getCurrentUser.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(getCurrentUser.fulfilled, (state, action) => {
        state.isLoading = false;
        state.user = action.payload.user || null;
        state.isAuthenticated = true;
      })
      .addCase(getCurrentUser.rejected, (state, action) => {
        state.isLoading = false;
        const payload = action.payload as { clearTokens: boolean; message: string } | string;

        // Clear all authentication data when getCurrentUser fails
        state.user = null;
        state.access_token = null;
        state.refresh_token = null;
        state.isAuthenticated = false;
        state.error = typeof payload === 'object' ? payload.message : (payload || 'Failed to get current user');
        localStorage.removeItem('access_token');
        localStorage.removeItem('refresh_token');
      })
      
      // Resend verification email
      .addCase(resendVerificationEmail.pending, (state) => {
        state.resendingVerification = true;
        state.error = null;
        state.resendVerificationSuccess = false;
      })
      .addCase(resendVerificationEmail.fulfilled, (state) => {
        state.resendingVerification = false;
        state.resendVerificationSuccess = true;
        state.resendCooldown = 60; // 60 second cooldown
      })
      .addCase(resendVerificationEmail.rejected, (state, action) => {
        state.resendingVerification = false;
        state.error = action.payload as string;
      })
      
      // Start impersonation
      .addCase(startImpersonation.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(startImpersonation.fulfilled, (state, action) => {
        state.isLoading = false;
        
        // Convert target_user to User format
        const targetUser = {
          id: action.payload.target_user.id,
          email: action.payload.target_user.email,
          name: action.payload.target_user.full_name || '',
          roles: action.payload.target_user.roles || [],
          permissions: action.payload.target_user.permissions || [],
          status: action.payload.target_user.status,
          email_verified: true, // Assuming verified users can be impersonated
          account: state.user?.account || { id: '', name: '', status: '' }
        };
        
        state.user = targetUser;
        state.impersonation = {
          isImpersonating: true,
          originalUser: action.payload.originalUser,
          impersonatedUser: targetUser,
          sessionId: action.payload.token, // Using token as session ID
          startedAt: new Date().toISOString(),
          expiresAt: action.payload.expires_at,
        };
        
        // Store impersonation token separately
        localStorage.setItem('impersonationToken', action.payload.token);
        
      })
      .addCase(startImpersonation.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      })
      
      // Stop impersonation
      .addCase(stopImpersonation.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(stopImpersonation.fulfilled, (state) => {
        state.isLoading = false;

        // Restore original user
        state.user = state.impersonation.originalUser;
        state.impersonation = {
          isImpersonating: false,
          originalUser: null,
          impersonatedUser: null,
          sessionId: null,
          startedAt: null,
          expiresAt: null,
        };

        // Remove impersonation token
        localStorage.removeItem('impersonationToken');
      })
      .addCase(stopImpersonation.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string;
      })
      
      // Check impersonation status
      .addCase(checkImpersonationStatus.fulfilled, (state, action) => {
        
        // CRITICAL FIX: Handle null payload (no token in localStorage)
        if (action.payload === null) {
          state.impersonation = {
            isImpersonating: false,
            originalUser: null,
            impersonatedUser: null,
            sessionId: null,
            startedAt: null,
            expiresAt: null,
          };
          return; // Exit early, don't clear localStorage token
        }
        
        if (action.payload && action.payload.valid && action.payload.session) {
          const session = action.payload.session;
          
          // Convert impersonated_user to User format
          const impersonatedUser = {
            id: session.impersonated_user.id,
            email: session.impersonated_user.email,
            name: session.impersonated_user.full_name || '',
            roles: session.impersonated_user.roles || [],
            permissions: session.impersonated_user.permissions || [],
            status: session.impersonated_user.status,
            email_verified: true,
            account: state.user?.account || { id: '', name: '', status: '' }
          };

          // Convert impersonator to User format
          const impersonator = {
            id: session.impersonator.id,
            email: session.impersonator.email,
            name: session.impersonator.full_name || '',
            roles: session.impersonator.roles || [],
            permissions: session.impersonator.permissions || [],
            status: session.impersonator.status,
            email_verified: true,
            account: state.user?.account || { id: '', name: '', status: '' }
          };
          
          // CRITICAL FIX: Don't re-read from localStorage, use the token from the async thunk
          const impersonationToken = localStorage.getItem('impersonationToken');
          
          state.user = impersonatedUser;
          state.impersonation = {
            isImpersonating: true,
            originalUser: impersonator,
            impersonatedUser: impersonatedUser,
            sessionId: impersonationToken, // Use the token that should be in localStorage
            startedAt: session.started_at,
            expiresAt: action.payload.expires_at || null,
          };
        } else {
          // Clear invalid impersonation state
          state.impersonation = {
            isImpersonating: false,
            originalUser: null,
            impersonatedUser: null,
            sessionId: null,
            startedAt: null,
            expiresAt: null,
          };
          localStorage.removeItem('impersonationToken');
        }
      })
      .addCase(checkImpersonationStatus.rejected, (state, _action) => {
        // Clear invalid impersonation state on error
        state.impersonation = {
          isImpersonating: false,
          originalUser: null,
          impersonatedUser: null,
          sessionId: null,
          startedAt: null,
          expiresAt: null,
        };
        localStorage.removeItem('impersonationToken');
      })
      
      // 2FA verification
      .addCase(verify2FA.pending, (state) => {
        state.isLoading = true;
        state.error = null;
      })
      .addCase(verify2FA.fulfilled, (state, action) => {
        state.isLoading = false;
        state.isAuthenticated = true;
        state.user = action.payload.user || null;
        state.access_token = action.payload.access_token || null;
        state.refresh_token = action.payload.refresh_token || null;
        
        if (action.payload.access_token) {
          localStorage.setItem('access_token', action.payload.access_token);
        }
        if (action.payload.refresh_token) {
          localStorage.setItem('refresh_token', action.payload.refresh_token);
        }
        
        // Track the domain where authentication was established
        setAuthDomain();
      })
      .addCase(verify2FA.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.payload as string || '2FA verification failed';
      });
  },
});

export const { clearError, clearAuth, forceTokenClear, clearResendVerificationSuccess, decrementResendCooldown } = authSlice.actions;
export default authSlice.reducer;