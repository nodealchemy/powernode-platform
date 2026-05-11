import { apiClient } from '@/shared/services/apiClient';
import {
  StorageAssignment,
  StorageAssignmentCreateInput,
  StorageAssignmentsListResponse,
} from '../types';

interface Envelope<T> {
  success: boolean;
  data?: T;
  error?: string;
}

function unwrap<T>(response: { data: Envelope<T> | T }): T {
  const body = response.data as Envelope<T>;
  if (body && typeof body === 'object' && 'data' in body && body.data !== undefined) {
    return body.data;
  }
  return response.data as T;
}

export const storageAssignmentsApi = {
  list: async (params: { file_storage_id?: string; node_instance_id?: string; status?: string } = {}) => {
    const response = await apiClient.get<Envelope<StorageAssignmentsListResponse>>(
      '/system/storage_assignments',
      { params },
    );
    return unwrap<StorageAssignmentsListResponse>(response);
  },

  get: async (id: string) => {
    const response = await apiClient.get<Envelope<{ assignment: StorageAssignment }>>(
      `/system/storage_assignments/${id}`,
    );
    return unwrap<{ assignment: StorageAssignment }>(response).assignment;
  },

  create: async (input: StorageAssignmentCreateInput) => {
    const response = await apiClient.post<Envelope<{ assignment: StorageAssignment }>>(
      '/system/storage_assignments',
      { assignment: input },
    );
    return unwrap<{ assignment: StorageAssignment }>(response).assignment;
  },

  bulkCreate: async (assignments: StorageAssignmentCreateInput[]) => {
    const response = await apiClient.post<
      Envelope<{ created: StorageAssignment[]; errors: Array<{ index: number; errors: unknown }> }>
    >('/system/storage_assignments', { assignments });
    return unwrap<{ created: StorageAssignment[]; errors: Array<{ index: number; errors: unknown }> }>(
      response,
    );
  },

  update: async (id: string, input: Partial<StorageAssignmentCreateInput>) => {
    const response = await apiClient.patch<Envelope<{ assignment: StorageAssignment }>>(
      `/system/storage_assignments/${id}`,
      { assignment: input },
    );
    return unwrap<{ assignment: StorageAssignment }>(response).assignment;
  },

  destroy: async (id: string) => {
    await apiClient.delete(`/system/storage_assignments/${id}`);
  },

  reconcile: async (id: string) => {
    const response = await apiClient.post<Envelope<{ assignment: StorageAssignment }>>(
      `/system/storage_assignments/${id}/reconcile`,
      {},
    );
    return unwrap<{ assignment: StorageAssignment }>(response).assignment;
  },

  rotateCredential: async (id: string) => {
    const response = await apiClient.post<Envelope<{ credential_id: string; message: string }>>(
      `/system/storage_assignments/${id}/rotate_credential`,
      {},
    );
    return unwrap<{ credential_id: string; message: string }>(response);
  },
};
