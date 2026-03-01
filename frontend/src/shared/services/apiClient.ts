// API Client - Wrapper around the main API service
import { api } from '@/shared/services/api';

// Export the existing API client instance
export const apiClient = api;

// Export the API client as default for backward compatibility
export default apiClient;