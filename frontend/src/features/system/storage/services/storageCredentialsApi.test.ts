// Behavioral tests for storageCredentialsApi — request shaping + envelope
// extraction for the storage-credential metadata surface (IMP-b2c32f1e3038).
//
// SECURITY CONTRACT: the backend NEVER serializes credential material —
// only kind/status/rotation metadata. Rotate returns the NEW credential's
// metadata row, not a secret.

import { storageCredentialsApi } from './storageCredentialsApi';
import type { StorageCredential } from '../types';

const mockGet = jest.fn();
const mockPost = jest.fn();

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
  },
}));

const CREDENTIAL: StorageCredential = {
  id: 'cred-1',
  storage_assignment_id: 'sa-1',
  node_instance_id: 'inst-1',
  kind: 'smb_password',
  status: 'active',
  expires_at: '2026-10-01T00:00:00Z',
  last_rotated_at: '2026-07-01T00:00:00Z',
  needs_rotation: false,
  metadata: { username: 'svc-mount' },
};

beforeEach(() => {
  jest.clearAllMocks();
});

describe('storageCredentialsApi.list', () => {
  it('GETs /system/storage_credentials filtered by assignment', async () => {
    mockGet.mockResolvedValue({
      data: { success: true, data: { credentials: [CREDENTIAL] } },
    });

    const result = await storageCredentialsApi.list({ storage_assignment_id: 'sa-1' });

    expect(mockGet).toHaveBeenCalledWith('/system/storage_credentials', {
      params: { storage_assignment_id: 'sa-1' },
    });
    expect(result.credentials).toEqual([CREDENTIAL]);
  });

  it('lists without filters and defaults to an empty array', async () => {
    mockGet.mockResolvedValue({ data: { success: true, data: {} } });

    const result = await storageCredentialsApi.list();

    expect(mockGet).toHaveBeenCalledWith('/system/storage_credentials', { params: {} });
    expect(result.credentials).toEqual([]);
  });
});

describe('storageCredentialsApi.get', () => {
  it('GETs /system/storage_credentials/:id and unwraps data.credential', async () => {
    mockGet.mockResolvedValue({
      data: { success: true, data: { credential: CREDENTIAL } },
    });

    const result = await storageCredentialsApi.get('cred-1');

    expect(mockGet).toHaveBeenCalledWith('/system/storage_credentials/cred-1');
    expect(result).toEqual(CREDENTIAL);
  });
});

describe('storageCredentialsApi.rotate', () => {
  it('POSTs /system/storage_credentials/:id/rotate and returns the NEW credential metadata', async () => {
    const rotated: StorageCredential = {
      ...CREDENTIAL,
      id: 'cred-2',
      last_rotated_at: '2026-07-23T00:00:00Z',
    };
    mockPost.mockResolvedValue({
      data: { success: true, data: { credential: rotated } },
    });

    const result = await storageCredentialsApi.rotate('cred-1');

    expect(mockPost).toHaveBeenCalledWith('/system/storage_credentials/cred-1/rotate', {});
    expect(result.id).toBe('cred-2');
  });
});
