import { authApi } from './authAPI';
import { createMockAxiosResponse } from '@/shared/utils/test-utils';
import { api } from '@/shared/services/api';

// Mock the API client
jest.mock('@/shared/services/api', () => ({
  api: {
    post: jest.fn(),
    get: jest.fn(),
    put: jest.fn(),
    delete: jest.fn()
  }
}));

const mockApi = jest.mocked(api);

describe('authApi', () => {
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
          name: 'Test User',
          roles: ['account.member'],
          permissions: ['users.read'],
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
      const result = await authApi.login(credentials);

      expect(mockApi.post).toHaveBeenCalledWith('/auth/login', credentials);
      expect(result.data).toEqual(mockResponse);
    });
  });

  describe('logout', () => {
    it('should call POST /auth/logout', async () => {
      const mockResponse = { success: true };

      mockApi.post.mockResolvedValue(createMockAxiosResponse(mockResponse));

      const result = await authApi.logout();

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

      const result = await authApi.refreshToken('refresh_token123');

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
          name: 'Test User',
          roles: ['account.member'],
          permissions: ['users.read'],
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

      const result = await authApi.getCurrentUser();

      expect(mockApi.get).toHaveBeenCalledWith('/auth/me', { silentAuth: false });
      expect(result.data).toEqual(mockResponse);
    });
  });
});