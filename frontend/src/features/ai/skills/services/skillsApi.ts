import { api } from '@/shared/services/api';
import type {
  SkillsListResponse,
  SkillResponse,
  CategoriesResponse,
  SkillFormData,
  SkillFilters,
} from '../types';

const handleApiError = (error: unknown, defaultMessage: string): string => {
  if (error && typeof error === 'object' && 'response' in error) {
    return (error as { response?: { data?: { error?: string } } }).response?.data?.error || defaultMessage;
  }
  return defaultMessage;
};

export const skillsApi = {
  async getSkills(
    page = 1,
    perPage = 20,
    filters?: SkillFilters
  ): Promise<SkillsListResponse> {
    try {
      const params = new URLSearchParams({
        page: page.toString(),
        per_page: perPage.toString(),
      });

      if (filters?.category) params.append('category', filters.category);
      if (filters?.status) params.append('status', filters.status);
      if (filters?.enabled) params.append('enabled', filters.enabled);
      if (filters?.search) params.append('search', filters.search);

      const response = await api.get(`/ai/skills?${params}`);
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch skills'),
      };
    }
  },

  async getSkill(id: string): Promise<SkillResponse> {
    try {
      const response = await api.get(`/ai/skills/${id}`);
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch skill'),
      };
    }
  },

  async createSkill(data: SkillFormData): Promise<SkillResponse> {
    try {
      const response = await api.post('/ai/skills', { skill: data });
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to create skill'),
      };
    }
  },

  async updateSkill(id: string, data: Partial<SkillFormData>): Promise<SkillResponse> {
    try {
      const response = await api.patch(`/ai/skills/${id}`, { skill: data });
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to update skill'),
      };
    }
  },

  async deleteSkill(id: string): Promise<{ success: boolean; message?: string; error?: string }> {
    try {
      const response = await api.delete(`/ai/skills/${id}`);
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to delete skill'),
      };
    }
  },

  async activateSkill(id: string): Promise<SkillResponse> {
    try {
      const response = await api.post(`/ai/skills/${id}/activate`);
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to activate skill'),
      };
    }
  },

  async deactivateSkill(id: string): Promise<SkillResponse> {
    try {
      const response = await api.post(`/ai/skills/${id}/deactivate`);
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to deactivate skill'),
      };
    }
  },

  async getSkillAgents(skillId: string): Promise<{ success: boolean; data?: { agents: Array<{ id: string; name: string; agent_type: string; status: string }> }; error?: string }> {
    try {
      const response = await api.get(`/ai/skills/${skillId}/agents`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch skill agents') };
    }
  },

  async getCategories(): Promise<CategoriesResponse> {
    try {
      const response = await api.get('/ai/skills/categories');
      return response.data;
    } catch (error) {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch categories'),
      };
    }
  },

  getCategoryLabel(category: string): string {
    const labels: Record<string, string> = {
      productivity: 'Productivity',
      sales: 'Sales',
      customer_support: 'Customer Support',
      product_management: 'Product Management',
      marketing: 'Marketing',
      legal: 'Legal',
      finance: 'Finance',
      data: 'Data',
      business_search: 'Business Search',
      bio_research: 'Bio Research',
      skill_management: 'Skill Management',
      code_intelligence: 'Code Intelligence',
      testing_qa: 'Testing & QA',
      devops: 'DevOps',
      security: 'Security',
      sre_observability: 'SRE & Observability',
      database_ops: 'Database Ops',
      release_management: 'Release Management',
      research: 'Research',
      documentation: 'Documentation',
    };
    return labels[category] || category;
  },

  getCategoryIcon(category: string): string {
    const icons: Record<string, string> = {
      productivity: '⚡',
      sales: '💼',
      customer_support: '🎧',
      product_management: '📋',
      marketing: '📢',
      legal: '⚖️',
      finance: '💰',
      data: '📊',
      business_search: '🔍',
      bio_research: '🧬',
      skill_management: '🛠️',
      code_intelligence: '🧠',
      testing_qa: '🧪',
      devops: '🔧',
      security: '🔒',
      sre_observability: '📡',
      database_ops: '🗄️',
      release_management: '🚀',
      research: '🔬',
      documentation: '📝',
    };
    return icons[category] || '📦';
  },
};
