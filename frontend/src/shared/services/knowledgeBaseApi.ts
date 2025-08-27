import api from '@/shared/services/api';

// Types
export interface KbCategory {
  id: string;
  name: string;
  slug: string;
  description?: string;
  full_path?: string;
  parent_id?: string;
  parent_name?: string;
  article_count: number;
  total_article_count?: number;
  children?: KbCategory[];
  sort_order: number;
  is_public: boolean;
  created_at: string;
  updated_at: string;
  metadata?: Record<string, any>;
}

export interface KbArticle {
  id: string;
  title: string;
  slug: string;
  content?: string;
  excerpt?: string;
  author_name: string;
  category: {
    id: string;
    name: string;
    slug?: string;
  };
  status?: string;
  is_public: boolean;
  is_featured: boolean;
  published_at?: string;
  reading_time: number;
  views_count: number;
  likes_count: number;
  comments_count?: number;
  sort_order?: number;
  tags: string[];
  attachments?: KbAttachment[];
  can_edit?: boolean;
  metadata?: Record<string, any>;
  created_at?: string;
  updated_at?: string;
}

export interface KbTag {
  id: string;
  name: string;
  slug: string;
  description?: string;
  color: string;
  usage_count: number;
}

export interface KbComment {
  id: string;
  content: string;
  user_name: string;
  created_at: string;
  likes_count: number;
  replies_count: number;
  is_reply: boolean;
  status?: string;
  replies?: KbComment[];
}

export interface KbAttachment {
  id: string;
  filename: string;
  content_type: string;
  file_size: string;
  download_count: number;
}

export interface KbSearchParams {
  q?: string;
  category_id?: string;
  tags?: string;
  featured?: boolean;
  sort?: 'recent' | 'popular' | 'title';
  page?: number;
  per_page?: number;
}

export interface KbPagination {
  current_page: number;
  total_pages: number;
  total_count: number;
  per_page: number;
}

export interface KbArticleCreateParams {
  title: string;
  content: string;
  excerpt?: string;
  category_id: string;
  status?: 'draft' | 'review' | 'published';
  is_public?: boolean;
  is_featured?: boolean;
  sort_order?: number;
  tag_names?: string[];
  metadata?: Record<string, any>;
}

export interface KbCategoryCreateParams {
  name: string;
  description?: string;
  parent_id?: string;
  sort_order?: number;
  is_public?: boolean;
  metadata?: Record<string, any>;
}

export interface KbCommentCreateParams {
  content: string;
  parent_id?: string;
}

// Public Knowledge Base API
export const knowledgeBaseApi = {
  // Categories
  getCategories: () =>
    api.get<{ data: KbCategory[]; message: string }>('/kb/categories'),

  getCategory: (id: string) =>
    api.get<{ data: { category: KbCategory; articles: KbArticle[] }; message: string }>(
      `/kb/categories/${id}`
    ),

  // Articles
  getArticles: (params?: KbSearchParams) => {
    const searchParams = new URLSearchParams();
    if (params?.q) searchParams.append('q', params.q);
    if (params?.category_id) searchParams.append('category_id', params.category_id);
    if (params?.tags) searchParams.append('tags', params.tags);
    if (params?.featured) searchParams.append('featured', 'true');
    if (params?.sort) searchParams.append('sort', params.sort);
    if (params?.page) searchParams.append('page', params.page.toString());
    if (params?.per_page) searchParams.append('per_page', params.per_page.toString());

    const queryString = searchParams.toString();
    const url = queryString ? `/kb/articles?${queryString}` : '/kb/articles';

    return api.get<{ data: { articles: KbArticle[]; pagination: KbPagination }; message: string }>(url);
  },

  getArticle: (id: string) =>
    api.get<{ data: { article: KbArticle; related_articles: KbArticle[] }; message: string }>(
      `/kb/articles/${id}`
    ),

  searchArticles: (params: KbSearchParams) => {
    const searchParams = new URLSearchParams();
    if (params.q) searchParams.append('q', params.q);
    if (params.category_id) searchParams.append('category_id', params.category_id);
    if (params.tags) searchParams.append('tags', params.tags);
    if (params.featured) searchParams.append('featured', 'true');
    if (params.sort) searchParams.append('sort', params.sort);
    if (params.page) searchParams.append('page', params.page.toString());
    if (params.per_page) searchParams.append('per_page', params.per_page.toString());

    return api.get<{ data: { query: string; articles: KbArticle[]; pagination: KbPagination }; message: string }>(
      `/kb/articles/search?${searchParams.toString()}`
    );
  },

  // Tags
  getTags: () =>
    api.get<{ data: KbTag[]; message: string }>('/kb/tags'),

  getTagArticles: (tagId: string, params?: { page?: number; per_page?: number }) => {
    const searchParams = new URLSearchParams();
    if (params?.page) searchParams.append('page', params.page.toString());
    if (params?.per_page) searchParams.append('per_page', params.per_page.toString());

    const queryString = searchParams.toString();
    const url = queryString ? `/kb/tags/${tagId}/articles?${queryString}` : `/kb/tags/${tagId}/articles`;

    return api.get<{ data: { tag: KbTag; articles: KbArticle[]; pagination: KbPagination }; message: string }>(url);
  },

  // Comments
  getArticleComments: (articleId: string, params?: { page?: number; per_page?: number }) => {
    const searchParams = new URLSearchParams();
    if (params?.page) searchParams.append('page', params.page.toString());
    if (params?.per_page) searchParams.append('per_page', params.per_page.toString());

    const queryString = searchParams.toString();
    const url = queryString 
      ? `/kb/articles/${articleId}/comments?${queryString}` 
      : `/kb/articles/${articleId}/comments`;

    return api.get<{ data: { comments: KbComment[]; pagination: KbPagination }; message: string }>(url);
  },

  createComment: (articleId: string, params: KbCommentCreateParams) =>
    api.post<{ data: KbComment; message: string }>(
      `/kb/articles/${articleId}/comments`,
      { comment: params }
    ),

  getComment: (id: string) =>
    api.get<{ data: KbComment; message: string }>(`/kb/comments/${id}`)
};

// Admin Knowledge Base API
export const knowledgeBaseAdminApi = {
  // Categories
  getCategories: (params?: { search?: string; page?: number; per_page?: number }) => {
    const searchParams = new URLSearchParams();
    if (params?.search) searchParams.append('search', params.search);
    if (params?.page) searchParams.append('page', params.page.toString());
    if (params?.per_page) searchParams.append('per_page', params.per_page.toString());

    const queryString = searchParams.toString();
    const url = queryString ? `/admin/kb/categories?${queryString}` : '/admin/kb/categories';

    return api.get<{ data: { categories: KbCategory[]; pagination: KbPagination }; message: string }>(url);
  },

  getCategory: (id: string) =>
    api.get<{ data: KbCategory; message: string }>(`/admin/kb/categories/${id}`),

  createCategory: (params: KbCategoryCreateParams) =>
    api.post<{ data: KbCategory; message: string }>('/admin/kb/categories', { category: params }),

  updateCategory: (id: string, params: Partial<KbCategoryCreateParams>) =>
    api.patch<{ data: KbCategory; message: string }>(`/admin/kb/categories/${id}`, { category: params }),

  deleteCategory: (id: string) =>
    api.delete<{ message: string }>(`/admin/kb/categories/${id}`),

  getCategoryTree: () =>
    api.get<{ data: KbCategory[]; message: string }>('/admin/kb/categories/tree'),

  // Articles
  getArticles: (params?: { 
    search?: string; 
    status?: string; 
    category_id?: string; 
    author_id?: string; 
    is_public?: boolean;
    is_featured?: boolean;
    sort?: string;
    page?: number; 
    per_page?: number;
  }) => {
    const searchParams = new URLSearchParams();
    if (params?.search) searchParams.append('search', params.search);
    if (params?.status) searchParams.append('status', params.status);
    if (params?.category_id) searchParams.append('category_id', params.category_id);
    if (params?.author_id) searchParams.append('author_id', params.author_id);
    if (params?.is_public !== undefined) searchParams.append('is_public', params.is_public.toString());
    if (params?.is_featured !== undefined) searchParams.append('is_featured', params.is_featured.toString());
    if (params?.sort) searchParams.append('sort', params.sort);
    if (params?.page) searchParams.append('page', params.page.toString());
    if (params?.per_page) searchParams.append('per_page', params.per_page.toString());

    const queryString = searchParams.toString();
    const url = queryString ? `/admin/kb/articles?${queryString}` : '/admin/kb/articles';

    return api.get<{ 
      data: { 
        articles: KbArticle[]; 
        pagination: KbPagination;
        stats: {
          total: number;
          published: number;
          draft: number;
          review: number;
          archived: number;
        };
      }; 
      message: string;
    }>(url);
  },

  getArticle: (id: string) =>
    api.get<{ data: KbArticle; message: string }>(`/admin/kb/articles/${id}`),

  createArticle: (params: KbArticleCreateParams) =>
    api.post<{ data: KbArticle; message: string }>('/admin/kb/articles', { article: params }),

  updateArticle: (id: string, params: Partial<KbArticleCreateParams>) =>
    api.patch<{ data: KbArticle; message: string }>(`/admin/kb/articles/${id}`, { article: params }),

  deleteArticle: (id: string) =>
    api.delete<{ message: string }>(`/admin/kb/articles/${id}`),

  publishArticle: (id: string) =>
    api.post<{ data: KbArticle; message: string }>(`/admin/kb/articles/${id}/publish`),

  unpublishArticle: (id: string) =>
    api.post<{ data: KbArticle; message: string }>(`/admin/kb/articles/${id}/unpublish`),

  getAnalytics: (period?: number) => {
    const searchParams = new URLSearchParams();
    if (period) searchParams.append('period', period.toString());

    const queryString = searchParams.toString();
    const url = queryString 
      ? `/admin/kb/articles/analytics?${queryString}` 
      : '/admin/kb/articles/analytics';

    return api.get<{ 
      data: {
        total_articles: number;
        published_articles: number;
        draft_articles: number;
        total_views: number;
        top_articles: Record<string, number>;
        views_by_day: Record<string, number>;
      }; 
      message: string;
    }>(url);
  },

  // Comments
  getComments: (params?: { 
    status?: string; 
    article_id?: string; 
    user_id?: string;
    search?: string;
    sort?: string;
    page?: number; 
    per_page?: number;
  }) => {
    const searchParams = new URLSearchParams();
    if (params?.status) searchParams.append('status', params.status);
    if (params?.article_id) searchParams.append('article_id', params.article_id);
    if (params?.user_id) searchParams.append('user_id', params.user_id);
    if (params?.search) searchParams.append('search', params.search);
    if (params?.sort) searchParams.append('sort', params.sort);
    if (params?.page) searchParams.append('page', params.page.toString());
    if (params?.per_page) searchParams.append('per_page', params.per_page.toString());

    const queryString = searchParams.toString();
    const url = queryString ? `/admin/kb/comments?${queryString}` : '/admin/kb/comments';

    return api.get<{ 
      data: { 
        comments: KbComment[]; 
        pagination: KbPagination;
        stats: {
          total: number;
          pending: number;
          approved: number;
          rejected: number;
          spam: number;
        };
      }; 
      message: string;
    }>(url);
  },

  getComment: (id: string) =>
    api.get<{ data: KbComment; message: string }>(`/admin/kb/comments/${id}`),

  approveComment: (id: string) =>
    api.post<{ data: KbComment; message: string }>(`/admin/kb/comments/${id}/approve`),

  rejectComment: (id: string) =>
    api.post<{ data: KbComment; message: string }>(`/admin/kb/comments/${id}/reject`),

  markCommentAsSpam: (id: string) =>
    api.post<{ data: KbComment; message: string }>(`/admin/kb/comments/${id}/spam`),

  deleteComment: (id: string) =>
    api.delete<{ message: string }>(`/admin/kb/comments/${id}`)
};