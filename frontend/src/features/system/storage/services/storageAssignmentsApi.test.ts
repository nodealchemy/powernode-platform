import { storageAssignmentsApi } from './storageAssignmentsApi';
import type { StorageAssignment, StorageAssignmentCreateInput } from '../types';

// =============================================================================
// Mocks — the API client is the only collaborator; stub each verb.
// =============================================================================

const mockGet = jest.fn();
const mockPost = jest.fn();
const mockPatch = jest.fn();
const mockDelete = jest.fn();

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
    patch: (...args: unknown[]) => mockPatch(...args),
    delete: (...args: unknown[]) => mockDelete(...args),
  },
}));

// Backend wraps payloads in { success, data }. AxiosResponse exposes the body
// as `response.data`, so the wrapped payload is `response.data.data`.
function enveloped<T>(data: T) {
  return { data: { success: true, data } };
}

const ASSIGNMENT: StorageAssignment = {
  id: 'sa-1',
  file_storage_id: 'fs-1',
  node_instance_id: 'inst-1',
  mount_path: '/mnt/data',
  status: 'mounted',
  encryption_mode: 'inherit',
  enabled: true,
  auto_mount: true,
  read_only: false,
};

describe('storageAssignmentsApi', () => {
  beforeEach(() => {
    mockGet.mockReset();
    mockPost.mockReset();
    mockPatch.mockReset();
    mockDelete.mockReset();
  });

  describe('list', () => {
    it('GETs /system/storage_assignments with params and unwraps the envelope', async () => {
      mockGet.mockResolvedValue(enveloped({ assignments: [ASSIGNMENT] }));
      const result = await storageAssignmentsApi.list({ file_storage_id: 'fs-1' });
      expect(mockGet).toHaveBeenCalledWith('/system/storage_assignments', {
        params: { file_storage_id: 'fs-1' },
      });
      expect(result.assignments).toEqual([ASSIGNMENT]);
    });

    it('defaults params to an empty object when none given', async () => {
      mockGet.mockResolvedValue(enveloped({ assignments: [] }));
      await storageAssignmentsApi.list();
      expect(mockGet).toHaveBeenCalledWith('/system/storage_assignments', { params: {} });
    });

    it('passes node_instance_id and status filters through', async () => {
      mockGet.mockResolvedValue(enveloped({ assignments: [] }));
      await storageAssignmentsApi.list({ node_instance_id: 'inst-9', status: 'failed' });
      expect(mockGet).toHaveBeenCalledWith('/system/storage_assignments', {
        params: { node_instance_id: 'inst-9', status: 'failed' },
      });
    });
  });

  describe('get', () => {
    it('GETs the assignment by id and returns the nested assignment', async () => {
      mockGet.mockResolvedValue(enveloped({ assignment: ASSIGNMENT }));
      const result = await storageAssignmentsApi.get('sa-1');
      expect(mockGet).toHaveBeenCalledWith('/system/storage_assignments/sa-1');
      expect(result).toEqual(ASSIGNMENT);
    });
  });

  describe('create', () => {
    it('POSTs { assignment: input } and returns the created assignment', async () => {
      const input: StorageAssignmentCreateInput = {
        file_storage_id: 'fs-1',
        node_instance_id: 'inst-1',
        mount_path: '/mnt/x',
      };
      mockPost.mockResolvedValue(enveloped({ assignment: ASSIGNMENT }));
      const result = await storageAssignmentsApi.create(input);
      expect(mockPost).toHaveBeenCalledWith('/system/storage_assignments', { assignment: input });
      expect(result).toEqual(ASSIGNMENT);
    });
  });

  describe('bulkCreate', () => {
    it('POSTs { assignments } and returns created + errors', async () => {
      const inputs: StorageAssignmentCreateInput[] = [
        { file_storage_id: 'fs-1', node_instance_id: 'inst-1', mount_path: '/mnt/1' },
        { file_storage_id: 'fs-1', node_instance_id: 'inst-2', mount_path: '/mnt/2' },
      ];
      mockPost.mockResolvedValue(
        enveloped({ created: [ASSIGNMENT], errors: [{ index: 1, errors: ['bad'] }] }),
      );
      const result = await storageAssignmentsApi.bulkCreate(inputs);
      expect(mockPost).toHaveBeenCalledWith('/system/storage_assignments', { assignments: inputs });
      expect(result.created).toEqual([ASSIGNMENT]);
      expect(result.errors).toEqual([{ index: 1, errors: ['bad'] }]);
    });
  });

  describe('update', () => {
    it('PATCHes { assignment: input } at the id and returns the assignment', async () => {
      mockPatch.mockResolvedValue(enveloped({ assignment: { ...ASSIGNMENT, read_only: true } }));
      const result = await storageAssignmentsApi.update('sa-1', { read_only: true });
      expect(mockPatch).toHaveBeenCalledWith('/system/storage_assignments/sa-1', {
        assignment: { read_only: true },
      });
      expect(result.read_only).toBe(true);
    });
  });

  describe('destroy', () => {
    it('DELETEs the assignment by id', async () => {
      mockDelete.mockResolvedValue({ data: { success: true } });
      await storageAssignmentsApi.destroy('sa-1');
      expect(mockDelete).toHaveBeenCalledWith('/system/storage_assignments/sa-1');
    });
  });

  describe('reconcile', () => {
    it('POSTs to the reconcile sub-action and returns the assignment', async () => {
      mockPost.mockResolvedValue(enveloped({ assignment: ASSIGNMENT }));
      const result = await storageAssignmentsApi.reconcile('sa-1');
      expect(mockPost).toHaveBeenCalledWith('/system/storage_assignments/sa-1/reconcile', {});
      expect(result).toEqual(ASSIGNMENT);
    });
  });

  describe('rotateCredential', () => {
    it('POSTs to rotate_credential and returns the credential payload', async () => {
      mockPost.mockResolvedValue(enveloped({ credential_id: 'cred-9', message: 'rotated' }));
      const result = await storageAssignmentsApi.rotateCredential('sa-1');
      expect(mockPost).toHaveBeenCalledWith(
        '/system/storage_assignments/sa-1/rotate_credential',
        {},
      );
      expect(result).toEqual({ credential_id: 'cred-9', message: 'rotated' });
    });
  });

  describe('unwrap envelope behavior', () => {
    it('unwraps the inner data when the envelope has a data field', async () => {
      mockGet.mockResolvedValue({ data: { success: true, data: { assignments: [] } } });
      const result = await storageAssignmentsApi.list();
      expect(result.assignments).toEqual([]);
    });

    it('returns the raw body when it is not wrapped in a data envelope', async () => {
      // Bare payload — no `data` key — so unwrap returns it as-is.
      mockGet.mockResolvedValue({ data: { assignments: [ASSIGNMENT] } });
      const result = await storageAssignmentsApi.list();
      expect(result.assignments).toEqual([ASSIGNMENT]);
    });
  });
});
