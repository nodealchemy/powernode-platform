import api from '@/shared/services/api';

export interface FileObject {
  id: string;
  filename: string;
  storage_key: string;
  content_type: string;
  file_size: number;
  file_type: string;
  category: string;
  visibility: string;
  version: number;
  processing_status: string;
  uploaded_by?: {
    id: string;
    name: string;
    email: string;
  };
  created_at: string;
  updated_at: string;
  urls?: {
    view: string;
    download: string;
    signed: string;
  };
  tags?: FileTag[];
}

export interface FileTag {
  id: string;
  name: string;
  color: string;
  description?: string;
}

export interface FileShare {
  id: string;
  file_id: string;
  share_type: string;
  access_level: string;
  expires_at?: string;
  max_downloads?: number;
  download_count: number;
  created_at: string;
  updated_at: string;
}

export interface FileUploadProgress {
  loaded: number;
  total: number;
  percentage: number;
}

export interface UploadOptions {
  onProgress?: (progress: FileUploadProgress) => void;
  category?: string;
  visibility?: string;
  description?: string;
  metadata?: Record<string, unknown>;
  tags?: string[];
}

export interface PaginationInfo {
  current_page: number;
  per_page: number;
  total_pages: number;
  total_count: number;
}

export const filesApi = {
  // List files with filtering and pagination
  async getFiles(params?: {
    category?: string;
    visibility?: string;
    storage_id?: string;
    tags?: string;
    search?: string;
    include_deleted?: boolean;
    page?: number;
    per_page?: number;
  }): Promise<{ files: FileObject[]; pagination: PaginationInfo }> {
    const response = await api.get('/files', { params });
    return response.data.data;
  },

  // Get single file details
  async getFile(id: string): Promise<FileObject> {
    const response = await api.get(`/files/${id}`);
    return response.data.data.file;
  },

  // Upload file with progress tracking
  async uploadFile(file: File, options: UploadOptions = {}): Promise<FileObject> {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('filename', file.name);

    if (options.category) formData.append('category', options.category);
    if (options.visibility) formData.append('visibility', options.visibility);
    if (options.description) formData.append('description', options.description);
    if (options.metadata) formData.append('metadata', JSON.stringify(options.metadata));
    if (options.tags) formData.append('tags', options.tags.join(','));

    const response = await api.post('/files/upload', formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
      onUploadProgress: (progressEvent) => {
        if (options.onProgress && progressEvent.total) {
          const percentage = Math.round((progressEvent.loaded * 100) / progressEvent.total);
          options.onProgress({
            loaded: progressEvent.loaded,
            total: progressEvent.total,
            percentage
          });
        }
      }
    });

    return response.data.data.file;
  },

  // Download file
  async downloadFile(id: string, filename?: string): Promise<void> {
    const response = await api.get(`/files/${id}/download`, {
      responseType: 'blob'
    });

    // Create download link
    const url = window.URL.createObjectURL(new Blob([response.data]));
    const link = document.createElement('a');
    link.href = url;
    link.setAttribute('download', filename || 'download');
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.URL.revokeObjectURL(url);
  },

  // Update file metadata
  async updateFile(id: string, data: {
    filename?: string;
    description?: string;
    visibility?: string;
    category?: string;
    metadata?: Record<string, unknown>;
  }): Promise<FileObject> {
    const response = await api.patch(`/files/${id}`, data);
    return response.data.data.file;
  },

  // Delete file (soft delete by default)
  async deleteFile(id: string, permanent: boolean = false): Promise<void> {
    await api.delete(`/files/${id}`, {
      params: { permanent }
    });
  },

  // Restore deleted file
  async restoreFile(id: string): Promise<FileObject> {
    const response = await api.post(`/files/${id}/restore`);
    return response.data.data.file;
  },

  // Create file share
  async createShare(id: string, options: {
    expires_at?: string;
    max_downloads?: number;
    password?: string;
    share_type?: string;
    access_level?: string;
  }): Promise<{ share: FileShare; url: string }> {
    const response = await api.post(`/files/${id}/share`, options);
    return response.data.data;
  },

  // Add tags to file
  async addTags(id: string, tags: string[]): Promise<FileTag[]> {
    const response = await api.post(`/files/${id}/tags`, { tags });
    return response.data.data.tags;
  },

  // Remove tags from file
  async removeTags(id: string, tagIds: string[]): Promise<void> {
    await api.delete(`/files/${id}/tags`, {
      data: { tag_ids: tagIds }
    });
  },

  // Get file statistics
  async getStats(): Promise<{
    total_files: number;
    total_size: number;
    by_category: Record<string, number>;
    by_type: Record<string, number>;
  }> {
    const response = await api.get('/files/stats');
    return response.data.data;
  }
};
