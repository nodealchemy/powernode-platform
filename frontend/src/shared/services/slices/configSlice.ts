import { createSlice, createAsyncThunk } from '@reduxjs/toolkit';
import { api } from '@/shared/services/api';

interface ConfigState {
  loadedExtensions: string[];
  coreMode: boolean;
  registrationEnabled: boolean;
  isLoaded: boolean;
}

const initialState: ConfigState = {
  loadedExtensions: [],
  coreMode: true,
  registrationEnabled: false,
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
        state.coreMode = features.core_mode ?? true;
        state.registrationEnabled = features.registration_enabled ?? false;
        state.loadedExtensions = (features.loaded_extensions || []).map(
          (ext: { slug: string }) => ext.slug
        );
      }
      state.isLoaded = true;
    });
    builder.addCase(fetchPlatformConfig.rejected, (state) => {
      state.isLoaded = true;
    });
  },
});

export default configSlice.reducer;
