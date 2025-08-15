import { createSlice, createAsyncThunk, PayloadAction } from '@reduxjs/toolkit';
import { subscriptionService, Subscription, Plan, CreateSubscriptionRequest, UpdateSubscriptionRequest } from '../../services/subscriptionService';

interface SubscriptionState {
  subscriptions: Subscription[];
  currentSubscription: Subscription | null;
  availablePlans: Plan[];
  loading: boolean;
  error: string | null;
}

const initialState: SubscriptionState = {
  subscriptions: [],
  currentSubscription: null,
  availablePlans: [],
  loading: false,
  error: null,
};

// Async thunks
export const fetchSubscriptions = createAsyncThunk(
  'subscription/fetchSubscriptions',
  async (_, { rejectWithValue }) => {
    const response = await subscriptionService.getSubscriptions();
    if (!response.success) {
      return rejectWithValue(response.error || 'Failed to fetch subscriptions');
    }
    return response.data as Subscription[];
  }
);

export const fetchSubscription = createAsyncThunk(
  'subscription/fetchSubscription',
  async (id: string, { rejectWithValue }) => {
    const response = await subscriptionService.getSubscription(id);
    if (!response.success) {
      return rejectWithValue(response.error || 'Failed to fetch subscription');
    }
    return response.data as Subscription;
  }
);

export const createSubscription = createAsyncThunk(
  'subscription/createSubscription',
  async (data: CreateSubscriptionRequest, { rejectWithValue }) => {
    const response = await subscriptionService.createSubscription(data);
    if (!response.success) {
      return rejectWithValue(response.error || 'Failed to create subscription');
    }
    return response.data as Subscription;
  }
);

export const updateSubscription = createAsyncThunk(
  'subscription/updateSubscription',
  async ({ id, data }: { id: string; data: UpdateSubscriptionRequest }, { rejectWithValue }) => {
    const response = await subscriptionService.updateSubscription(id, data);
    if (!response.success) {
      return rejectWithValue(response.error || 'Failed to update subscription');
    }
    return response.data as Subscription;
  }
);

export const cancelSubscription = createAsyncThunk(
  'subscription/cancelSubscription',
  async (id: string, { rejectWithValue }) => {
    const response = await subscriptionService.cancelSubscription(id);
    if (!response.success) {
      return rejectWithValue(response.error || 'Failed to cancel subscription');
    }
    return id;
  }
);

const subscriptionSlice = createSlice({
  name: 'subscription',
  initialState,
  reducers: {
    clearError: (state) => {
      state.error = null;
    },
    setCurrentSubscription: (state, action: PayloadAction<Subscription | null>) => {
      state.currentSubscription = action.payload;
    },
    setAvailablePlans: (state, action: PayloadAction<Plan[]>) => {
      state.availablePlans = action.payload;
    },
  },
  extraReducers: (builder) => {
    builder
      // Fetch subscriptions
      .addCase(fetchSubscriptions.pending, (state) => {
        state.loading = true;
        state.error = null;
      })
      .addCase(fetchSubscriptions.fulfilled, (state, action) => {
        state.loading = false;
        state.subscriptions = action.payload;
        // Set the first active subscription as current if none is set
        if (!state.currentSubscription && action.payload.length > 0) {
          const activeSubscription = action.payload.find(sub => sub.status === 'active');
          state.currentSubscription = activeSubscription || action.payload[0];
        }
      })
      .addCase(fetchSubscriptions.rejected, (state, action) => {
        state.loading = false;
        state.error = action.payload as string;
      })
      // Fetch single subscription
      .addCase(fetchSubscription.pending, (state) => {
        state.loading = true;
        state.error = null;
      })
      .addCase(fetchSubscription.fulfilled, (state, action) => {
        state.loading = false;
        state.currentSubscription = action.payload;
        // Update subscription in the list if it exists
        const index = state.subscriptions.findIndex(sub => sub.id === action.payload.id);
        if (index >= 0 && index < state.subscriptions.length) {
          state.subscriptions.splice(index, 1, action.payload);
        } else {
          state.subscriptions.push(action.payload);
        }
      })
      .addCase(fetchSubscription.rejected, (state, action) => {
        state.loading = false;
        state.error = action.payload as string;
      })
      // Create subscription
      .addCase(createSubscription.pending, (state) => {
        state.loading = true;
        state.error = null;
      })
      .addCase(createSubscription.fulfilled, (state, action) => {
        state.loading = false;
        state.subscriptions.push(action.payload);
        state.currentSubscription = action.payload;
      })
      .addCase(createSubscription.rejected, (state, action) => {
        state.loading = false;
        state.error = action.payload as string;
      })
      // Update subscription
      .addCase(updateSubscription.pending, (state) => {
        state.loading = true;
        state.error = null;
      })
      .addCase(updateSubscription.fulfilled, (state, action) => {
        state.loading = false;
        const index = state.subscriptions.findIndex(sub => sub.id === action.payload.id);
        if (index >= 0 && index < state.subscriptions.length) {
          state.subscriptions.splice(index, 1, action.payload);
        }
        if (state.currentSubscription?.id === action.payload.id) {
          state.currentSubscription = action.payload;
        }
      })
      .addCase(updateSubscription.rejected, (state, action) => {
        state.loading = false;
        state.error = action.payload as string;
      })
      // Cancel subscription
      .addCase(cancelSubscription.pending, (state) => {
        state.loading = true;
        state.error = null;
      })
      .addCase(cancelSubscription.fulfilled, (state, action) => {
        state.loading = false;
        const subscriptionId = action.payload;
        // Update subscription status to cancelled
        const targetSubscription = state.subscriptions.find(sub => sub.id === subscriptionId);
        if (targetSubscription) {
          targetSubscription.status = 'cancelled';
          targetSubscription.canceledAt = new Date().toISOString();
        }
        if (state.currentSubscription?.id === subscriptionId) {
          state.currentSubscription.status = 'cancelled';
          state.currentSubscription.canceledAt = new Date().toISOString();
        }
      })
      .addCase(cancelSubscription.rejected, (state, action) => {
        state.loading = false;
        state.error = action.payload as string;
      });
  },
});

export const { clearError, setCurrentSubscription, setAvailablePlans } = subscriptionSlice.actions;
export default subscriptionSlice.reducer;