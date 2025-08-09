import { createSlice, createAsyncThunk } from '@reduxjs/toolkit';
import { authAPI } from '../../services/authAPI';

export interface User {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  role: string;
  status: string;
  emailVerified: boolean;
  account: {
    id: string;
    name: string;
    status: string;
  };
}

interface AuthState {
  user: User | null;
  accessToken: string | null;
  refreshToken: string | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  error: string | null;
  resendingVerification: boolean;
  resendVerificationSuccess: boolean;
  resendCooldown: number;
}

const getInitialState = (): AuthState => {
  const accessToken = localStorage.getItem('accessToken');
  const refreshToken = localStorage.getItem('refreshToken');
  
  return {
    user: null,
    accessToken,
    refreshToken,
    isAuthenticated: !!accessToken,
    isLoading: false,
    error: null,
    resendingVerification: false,
    resendVerificationSuccess: false,
    resendCooldown: 0,
  };
};

const initialState: AuthState = getInitialState();

// Async thunks
export const login = createAsyncThunk(
  'auth/login',
  async ({ email, password }: { email: string; password: string }) => {
    const response = await authAPI.login({ email, password });
    return response.data;
  }
);

export const register = createAsyncThunk(
  'auth/register',
  async (userData: {
    email: string;
    password: string;
    firstName: string;
    lastName: string;
    accountName: string;
  }) => {
    const response = await authAPI.register(userData);
    return response.data;
  }
);

export const logout = createAsyncThunk('auth/logout', async () => {
  await authAPI.logout();
});

export const refreshAccessToken = createAsyncThunk(
  'auth/refreshToken',
  async (_, { getState, rejectWithValue }) => {
    try {
      const state = getState() as { auth: AuthState };
      const refreshToken = state.auth.refreshToken;
      
      if (!refreshToken) {
        throw new Error('No refresh token available');
      }
      
      const response = await authAPI.refreshToken(refreshToken);
      return response.data;
    } catch (error: any) {
      const errorMessage = error.response?.data?.error || error.response?.data?.message || 'Token refresh failed';
      
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
  async (_, { rejectWithValue }) => {
    try {
      const response = await authAPI.getCurrentUser();
      return response.data;
    } catch (error: any) {
      const errorMessage = error.response?.data?.error || error.response?.data?.message || 'Failed to get current user';
      
      // Check for token invalidity issues that require immediate token clearance
      if (error.response?.status === 401 && 
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
      const response = await authAPI.resendVerification();
      return response.data;
    } catch (error: any) {
      return rejectWithValue(error.response?.data?.error || 'Failed to resend verification email');
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
      state.accessToken = null;
      state.refreshToken = null;
      state.isAuthenticated = false;
      state.error = null;
      state.resendingVerification = false;
      state.resendVerificationSuccess = false;
      state.resendCooldown = 0;
      localStorage.removeItem('accessToken');
      localStorage.removeItem('refreshToken');
    },
    forceTokenClear: (state) => {
      // Force clear tokens immediately, useful for handling invalid signatures
      state.user = null;
      state.accessToken = null;
      state.refreshToken = null;
      state.isAuthenticated = false;
      state.error = 'Session expired. Please log in again.';
      localStorage.removeItem('accessToken');
      localStorage.removeItem('refreshToken');
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
        state.user = action.payload.user;
        state.accessToken = action.payload.access_token;
        state.refreshToken = action.payload.refresh_token;
        
        localStorage.setItem('accessToken', action.payload.access_token);
        localStorage.setItem('refreshToken', action.payload.refresh_token);
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
        state.user = action.payload.user;
        state.accessToken = action.payload.access_token;
        state.refreshToken = action.payload.refresh_token;
        
        localStorage.setItem('accessToken', action.payload.access_token);
        localStorage.setItem('refreshToken', action.payload.refresh_token);
      })
      .addCase(register.rejected, (state, action) => {
        state.isLoading = false;
        state.error = action.error.message || 'Registration failed';
      })
      
      // Logout
      .addCase(logout.fulfilled, (state) => {
        state.user = null;
        state.accessToken = null;
        state.refreshToken = null;
        state.isAuthenticated = false;
        localStorage.removeItem('accessToken');
        localStorage.removeItem('refreshToken');
      })
      
      // Refresh token
      .addCase(refreshAccessToken.fulfilled, (state, action) => {
        state.accessToken = action.payload.access_token;
        state.refreshToken = action.payload.refresh_token;
        localStorage.setItem('accessToken', action.payload.access_token);
        localStorage.setItem('refreshToken', action.payload.refresh_token);
      })
      .addCase(refreshAccessToken.rejected, (state, action) => {
        const payload = action.payload as { clearTokens: boolean; message: string } | string;
        
        // Always clear tokens on refresh failure, but handle enhanced error info if available
        state.user = null;
        state.accessToken = null;
        state.refreshToken = null;
        state.isAuthenticated = false;
        state.error = typeof payload === 'object' ? payload.message : (payload || 'Token refresh failed');
        localStorage.removeItem('accessToken');
        localStorage.removeItem('refreshToken');
      })
      
      // Get current user
      .addCase(getCurrentUser.fulfilled, (state, action) => {
        state.user = action.payload.user;
        state.isAuthenticated = true;
      })
      .addCase(getCurrentUser.rejected, (state, action) => {
        const payload = action.payload as { clearTokens: boolean; message: string } | string;
        
        // Clear all authentication data when getCurrentUser fails
        state.user = null;
        state.accessToken = null;
        state.refreshToken = null;
        state.isAuthenticated = false;
        state.error = typeof payload === 'object' ? payload.message : (payload || 'Failed to get current user');
        localStorage.removeItem('accessToken');
        localStorage.removeItem('refreshToken');
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
      });
  },
});

export const { clearError, clearAuth, forceTokenClear, clearResendVerificationSuccess, decrementResendCooldown } = authSlice.actions;
export default authSlice.reducer;