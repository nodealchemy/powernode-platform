import { api } from '@/shared/services/api';

export interface Page {
  id: string;
  title: string;
  slug: string;
  content: string;
  rendered_content?: string;
  meta_description?: string;
  meta_keywords?: string;
  status: 'draft' | 'published' | '' | undefined;
  published_at?: string;
  word_count?: number;
  estimated_read_time?: number;
  excerpt?: string;
  seo?: {
    title: string;
    description: string;
    keywords: string[];
  };
  author?: {
    id: string;
    name: string;
    email: string;
  };
  created_at: string;
  updated_at: string;
}

export interface PageFormData {
  title: string;
  content: string;
  meta_description?: string;
  meta_keywords?: string;
  status: 'draft' | 'published';
}

export interface PagesResponse {
  data: Page[];
  meta: {
    current_page: number;
    per_page: number;
    total_count: number;
    total_pages: number;
  };
}

export interface PageResponse {
  data: Page;
}

class PagesApi {
  // Public API endpoints (no authentication required)
  async getPublicPages(page = 1, perPage = 20): Promise<PagesResponse> {
    const response = await api.get(`/pages?page=${page}&per_page=${perPage}`);
    return response.data;
  }

  async getPublicPage(slug: string): Promise<PageResponse> {
    const response = await api.get(`/pages/${slug}`);
    return response.data;
  }

  // Admin API endpoints (require authentication)
  async getPages(filters?: {
    page?: number;
    per_page?: number;
    status?: 'draft' | 'published';
    search?: string;
    author?: string;
  }): Promise<PagesResponse> {
    const params = new URLSearchParams();
    if (filters?.page) params.append('page', filters.page.toString());
    if (filters?.per_page) params.append('per_page', filters.per_page.toString());
    if (filters?.status) params.append('status', filters.status);
    if (filters?.search) params.append('search', filters.search);
    if (filters?.author) params.append('author', filters.author);

    const response = await api.get(`/admin/pages?${params.toString()}`);
    return response.data;
  }

  async getPage(id: string): Promise<PageResponse> {
    const response = await api.get(`/admin/pages/${id}`);
    return response.data;
  }

  async createPage(pageData: PageFormData): Promise<PageResponse> {
    const response = await api.post('/admin/pages', { page: pageData });
    return response.data;
  }

  async updatePage(id: string, pageData: Partial<PageFormData>): Promise<PageResponse> {
    const response = await api.put(`/admin/pages/${id}`, { page: pageData });
    return response.data;
  }

  async deletePage(id: string): Promise<void> {
    await api.delete(`/admin/pages/${id}`);
  }

  async publishPage(id: string): Promise<PageResponse> {
    const response = await api.post(`/admin/pages/${id}/publish`);
    return response.data;
  }

  async unpublishPage(id: string): Promise<PageResponse> {
    const response = await api.post(`/admin/pages/${id}/unpublish`);
    return response.data;
  }

  async duplicatePage(id: string): Promise<PageResponse> {
    const response = await api.post(`/admin/pages/${id}/duplicate`);
    return response.data;
  }

  // Helper methods
  formatStatus(status: string | undefined | null): string {
    if (!status) return 'Draft';
    return status.charAt(0).toUpperCase() + status.slice(1);
  }

  getStatusColor(status: string | undefined | null): 'green' | 'yellow' | 'gray' {
    if (!status) return 'yellow';
    switch (status) {
      case 'published':
        return 'green';
      case 'draft':
        return 'yellow';
      default:
        return 'gray';
    }
  }

  formatPublishedDate(publishedAt?: string): string {
    if (!publishedAt) return 'Not published';
    return new Date(publishedAt).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric'
    });
  }

  generateSlug(title: string): string {
    return title
      .toLowerCase()
      .replace(/[^a-z0-9\s-]/g, '') // Remove special characters
      .replace(/\s+/g, '-') // Replace spaces with dashes
      .replace(/-+/g, '-') // Replace multiple dashes with single dash
      .replace(/^-|-$/g, ''); // Remove leading/trailing dashes
  }
}

export const pagesApi = new PagesApi();