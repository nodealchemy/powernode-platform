import { createSlice } from '@reduxjs/toolkit';

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

const configSlice = createSlice({
  name: 'config',
  initialState,
  reducers: {},
});

export default configSlice.reducer;
