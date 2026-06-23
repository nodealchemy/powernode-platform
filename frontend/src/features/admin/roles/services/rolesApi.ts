import { api } from '@/shared/services/api';

export interface Permission {
  // `id` equals `name` (the dotted catalog key, e.g. "users.manage").
  id: string;
  name: string;
  resource: string;
  action: string;
  description: string;
}

export interface Role {
  id: string;
  name: string;
  display_name?: string;
  description: string;
  system_role: boolean;
  // Backend role taxonomy: user (account-assignable) | admin | system.
  role_type: 'user' | 'admin' | 'system';
  // Roles are either GLOBAL (code-defined, read-only) or ACCOUNT-scoped (custom, editable).
  account_id: string | null;
  scope: 'global' | 'account';
  editable: boolean;
  permissions: Permission[];
  users_count: number;
  created_at: string;
  updated_at: string;
}

export interface RoleFormData {
  name: string;
  description: string;
  // Permissions are granted by name (the dotted catalog key), not by id.
  permission_names: string[];
}

export interface UserWithRoles {
  id: string;
  email: string;
  name: string;
  roles: string[];
  permissions: string[];
}

export const rolesApi = {
  async getRoles(): Promise<{ success: boolean; data: Role[] }> {
    const response = await api.get('/roles');
    return response.data;
  },

  async getRole(id: string): Promise<{ success: boolean; data: Role }> {
    const response = await api.get(`/roles/${id}`);
    return response.data;
  },

  async createRole(data: RoleFormData): Promise<{ success: boolean; data: Role; message: string }> {
    const response = await api.post('/roles', { role: data });
    return response.data;
  },

  async updateRole(id: string, data: Partial<RoleFormData>): Promise<{ success: boolean; data: Role; message: string }> {
    const response = await api.put(`/roles/${id}`, { role: data });
    return response.data;
  },

  async deleteRole(id: string): Promise<{ success: boolean; message: string }> {
    const response = await api.delete(`/roles/${id}`);
    return response.data;
  },

  async getPermissions(): Promise<{ success: boolean; data: Permission[] }> {
    const response = await api.get('/permissions');
    return response.data;
  },

  async getPermission(id: string): Promise<{ success: boolean; data: Permission }> {
    const response = await api.get(`/permissions/${id}`);
    return response.data;
  },

  async assignRoleToUser(role_id: string, user_id: string): Promise<{ success: boolean; data: UserWithRoles; message: string }> {
    const response = await api.post(`/roles/${role_id}/assign_to_user/${user_id}`);
    return response.data;
  },

  async removeRoleFromUser(role_id: string, user_id: string): Promise<{ success: boolean; data: UserWithRoles; message: string }> {
    const response = await api.delete(`/roles/${role_id}/remove_from_user/${user_id}`);
    return response.data;
  }
};