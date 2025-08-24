import { api } from '@/shared/services/api';

export interface Permission {
  id: string;
  name: string;
  resource: string;
  action: string;
  description: string;
}

export interface Role {
  id: string;
  name: string;
  description: string;
  system_role: boolean;
  permissions: Permission[];
  users_count: number;
  created_at: string;
  updated_at: string;
}

export interface RoleFormData {
  name: string;
  description: string;
  permission_ids: string[];
}

export interface UserWithRoles {
  id: string;
  email: string;
  first_name: string;
  last_name: string;
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

  async assignRoleToUser(roleId: string, userId: string): Promise<{ success: boolean; data: UserWithRoles; message: string }> {
    const response = await api.post(`/roles/${roleId}/assign_to_user/${userId}`);
    return response.data;
  },

  async removeRoleFromUser(roleId: string, userId: string): Promise<{ success: boolean; data: UserWithRoles; message: string }> {
    const response = await api.delete(`/roles/${roleId}/remove_from_user/${userId}`);
    return response.data;
  }
};