import { createSlice, createAsyncThunk } from '@reduxjs/toolkit';
import { api } from '@/shared/services/api';

interface ConfigState {
  registrationEnabled: boolean;
}

const initialState: ConfigState = {
  registrationEnabled: false,
};

// GET /api/v1/config is unauthenticated: the public pages (login, welcome)
// need it before anyone signs in.
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
      state.registrationEnabled = action.payload?.features?.registration_enabled === true;
    });
  },
});

export default configSlice.reducer;
