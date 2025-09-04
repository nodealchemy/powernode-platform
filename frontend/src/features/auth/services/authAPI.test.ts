import { authAPI } from './authAPI';
import { createMockAxiosResponse } from '@/shared/utils/test-utils';

// Mock the API client
jest.mock('@/shared/services/api', () => ({
  api: {
    post: jest.fn(),
    get: jest.fn(),
    put: jest.fn(),
    delete: jest.fn()
  }
}));

const mockApi = require('@/shared/services/api').api;

describe('authAPI', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('login', () => {
    it('should call POST /auth/login with email and password', async () => {
      const mockResponse = {
        success: true,
        user: { 
          id: '1', 
          email: 'test@example.com', 
          first_name: 'Test',
          last_name: 'User',
          roles: ['account.member'],
          status: 'active',
          email_verified: true,
          account: {
            id: 'acc_1',
            name: 'Test Account',
            status: 'active'
          }
        },
        access_token: 'token123',
        refresh_token: 'refresh123'
      };

      mockApi.post.mockResolvedValue(createMockAxiosResponse(mockResponse));

      const credentials = { email: 'test@example.com', password: 'password' };
      const result = await authAPI.login(credentials);

      expect(mockApi.post).toHaveBeenCalledWith('/auth/login', credentials);
      expect(result.data).toEqual(mockResponse);
    });
  });

  describe('logout', () => {
    it('should call POST /auth/logout', async () => {
      const mockResponse = { success: true };

      mockApi.post.mockResolvedValue(createMockAxiosResponse(mockResponse));

      const result = await authAPI.logout();

      expect(mockApi.post).toHaveBeenCalledWith('/auth/logout');
      expect(result.data).toEqual(mockResponse);
    });
  });

  describe('refreshToken', () => {
    it('should call POST /auth/refresh with refresh token', async () => {
      const mockResponse = {
        access_token: 'new_token123',
        refresh_token: 'new_refresh123'
      };

      mockApi.post.mockResolvedValue(createMockAxiosResponse(mockResponse));

      const result = await authAPI.refreshToken('refresh_token123');

      expect(mockApi.post).toHaveBeenCalledWith('/auth/refresh', {
        refresh_token: 'refresh_token123'
      });
      expect(result.data).toEqual(mockResponse);
    });
  });

  describe('getCurrentUser', () => {
    it('should call GET /auth/me', async () => {
      const mockResponse = {
        success: true,
        user: { 
          id: '1', 
          email: 'test@example.com',
          first_name: 'Test',
          last_name: 'User',
          roles: ['account.member'],
          status: 'active',
          email_verified: true,
          account: {
            id: 'acc_1',
            name: 'Test Account',
            status: 'active'
          }
        }
      };

      mockApi.get.mockResolvedValue(createMockAxiosResponse(mockResponse));

      const result = await authAPI.getCurrentUser();

      expect(mockApi.get).toHaveBeenCalledWith('/auth/me');
      expect(result.data).toEqual(mockResponse);
    });
  });
});