import { api } from '@/shared/services/api';

export interface BlogPostSummary {
  slug: string;
  title: string;
  excerpt: string | null;
  published_at: string | null;
  estimated_read_time: number | null;
}

export interface BlogPostDetail extends BlogPostSummary {
  content: string;
  rendered_content: string | null;
  meta: {
    description: string | null;
    keywords: string | null;
  };
}

class BlogApi {
  async listPosts(): Promise<{ posts: BlogPostSummary[] }> {
    const response = await api.get('/marketing/public/blog/posts');
    return response.data.data;
  }

  async getPost(slug: string): Promise<{ post: BlogPostDetail }> {
    const response = await api.get(`/marketing/public/blog/posts/${slug}`);
    return response.data.data;
  }
}

export const blogApi = new BlogApi();
