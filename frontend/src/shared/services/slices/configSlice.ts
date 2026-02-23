import { createSlice, createAsyncThunk } from '@reduxjs/toolkit';
import { api } from '@/shared/services/api';

interface ConfigState {
  enterpriseEnabled: boolean;
  billingEnabled: boolean;
  coreMode: boolean;
  isLoaded: boolean;
}

const initialState: ConfigState = {
  enterpriseEnabled: false,
  billingEnabled: false,
  coreMode: true,
  isLoaded: false,
};

export const fetchPlatformConfig = createAsyncThunk(
  'config/fetchPlatformConfig',
  async () => {
    const response = await api.get('/config');
    return response.data.data;
  }
);

const configSlice = createSlice({
  name: 'config',
  initialState,
  reducers: {},
  extraReducers: (builder) => {
    builder.addCase(fetchPlatformConfig.fulfilled, (state, action) => {
      const features = action.payload?.features;
      if (features) {
        state.enterpriseEnabled = features.enterprise_enabled ?? false;
        state.billingEnabled = features.billing_enabled ?? false;
        state.coreMode = features.core_mode ?? true;
      }
      state.isLoaded = true;
    });
    builder.addCase(fetchPlatformConfig.rejected, (state) => {
      state.isLoaded = true;
    });
  },
});

export default configSlice.reducer;
