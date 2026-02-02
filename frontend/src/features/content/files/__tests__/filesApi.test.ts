import { filesApi } from '../services/filesApi';
import api from '@/shared/services/api';
import { AxiosHeaders } from 'axios';

// Mock the api module
jest.mock('@/shared/services/api');

const mockApi = jest.mocked(api);

// Helper to create a full AxiosResponse mock
 
const createMockResponse = (data: any) => ({
  data,
  status: 200,
  statusText: 'OK',
  headers: {},
  config: { headers: new AxiosHeaders() },
});

describe('filesApi', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('uploadPageImage', () => {
    it('uploads file with page_content category and public visibility', async () => {
      const mockFile = new File(['test'], 'test.png', { type: 'image/png' });
      const mockResponseData = {
        data: {
          file: {
            id: 'file-123',
            filename: 'test.png',
            category: 'page_content',
            visibility: 'public',
          },
        },
      };

      mockApi.post.mockResolvedValue(createMockResponse(mockResponseData));

      const result = await filesApi.uploadPageImage(mockFile, 'page-123');

      expect(mockApi.post).toHaveBeenCalledWith(
        '/files/upload',
        expect.any(FormData),
        expect.objectContaining({
          headers: { 'Content-Type': 'multipart/form-data' },
        })
      );

      // Verify FormData contents
      const formDataCall = mockApi.post.mock.calls[0][1] as FormData;
      expect(formDataCall.get('category')).toBe('page_content');
      expect(formDataCall.get('visibility')).toBe('public');
      expect(formDataCall.get('attachable_type')).toBe('Page');
      expect(formDataCall.get('attachable_id')).toBe('page-123');

      expect(result).toEqual(mockResponseData.data.file);
    });

    it('uploads file without attachable when pageId is null', async () => {
      const mockFile = new File(['test'], 'test.png', { type: 'image/png' });
      const mockResponseData = {
        data: {
          file: {
            id: 'file-123',
            filename: 'test.png',
            category: 'page_content',
            visibility: 'public',
          },
        },
      };

      mockApi.post.mockResolvedValue(createMockResponse(mockResponseData));

      await filesApi.uploadPageImage(mockFile, null);

      const formDataCall = mockApi.post.mock.calls[0][1] as FormData;
      expect(formDataCall.get('category')).toBe('page_content');
      expect(formDataCall.get('attachable_type')).toBeNull();
      expect(formDataCall.get('attachable_id')).toBeNull();
    });

    it('allows overriding visibility option', async () => {
      const mockFile = new File(['test'], 'test.png', { type: 'image/png' });
      const mockResponseData = {
        data: {
          file: {
            id: 'file-123',
            filename: 'test.png',
          },
        },
      };

      mockApi.post.mockResolvedValue(createMockResponse(mockResponseData));

      await filesApi.uploadPageImage(mockFile, 'page-123', { visibility: 'private' });

      const formDataCall = mockApi.post.mock.calls[0][1] as FormData;
      expect(formDataCall.get('visibility')).toBe('private');
    });
  });

  describe('getAvailableImages', () => {
    it('fetches images with file_type=image parameter', async () => {
      const mockResponseData = {
        data: {
          files: [
            { id: 'img-1', filename: 'image1.png', file_type: 'image' },
            { id: 'img-2', filename: 'image2.jpg', file_type: 'image' },
          ],
          pagination: {
            current_page: 1,
            per_page: 25,
            total_pages: 1,
            total_count: 2,
          },
        },
      };

      mockApi.get.mockResolvedValue(createMockResponse(mockResponseData));

      const result = await filesApi.getAvailableImages();

      expect(mockApi.get).toHaveBeenCalledWith('/files', {
        params: {
          file_type: 'image',
        },
      });

      expect(result.files).toHaveLength(2);
      expect(result.pagination.total_count).toBe(2);
    });

    it('passes search parameter to API', async () => {
      const mockResponseData = {
        data: {
          files: [],
          pagination: { current_page: 1, per_page: 25, total_pages: 0, total_count: 0 },
        },
      };

      mockApi.get.mockResolvedValue(createMockResponse(mockResponseData));

      await filesApi.getAvailableImages({ search: 'hero' });

      expect(mockApi.get).toHaveBeenCalledWith('/files', {
        params: {
          search: 'hero',
          file_type: 'image',
        },
      });
    });

    it('passes pagination parameters', async () => {
      const mockResponseData = {
        data: {
          files: [],
          pagination: { current_page: 2, per_page: 50, total_pages: 3, total_count: 125 },
        },
      };

      mockApi.get.mockResolvedValue(createMockResponse(mockResponseData));

      await filesApi.getAvailableImages({ page: 2, per_page: 50 });

      expect(mockApi.get).toHaveBeenCalledWith('/files', {
        params: {
          page: 2,
          per_page: 50,
          file_type: 'image',
        },
      });
    });

    it('passes category filter parameter', async () => {
      const mockResponseData = {
        data: {
          files: [],
          pagination: { current_page: 1, per_page: 25, total_pages: 0, total_count: 0 },
        },
      };

      mockApi.get.mockResolvedValue(createMockResponse(mockResponseData));

      await filesApi.getAvailableImages({ category: 'page_content' });

      expect(mockApi.get).toHaveBeenCalledWith('/files', {
        params: {
          category: 'page_content',
          file_type: 'image',
        },
      });
    });
  });

  describe('getPageImages', () => {
    it('fetches images attached to a specific page', async () => {
      const mockResponseData = {
        data: {
          files: [{ id: 'img-1', filename: 'page-image.png', file_type: 'image' }],
          pagination: { current_page: 1, per_page: 25, total_pages: 1, total_count: 1 },
        },
      };

      mockApi.get.mockResolvedValue(createMockResponse(mockResponseData));

      const result = await filesApi.getPageImages('page-123');

      expect(mockApi.get).toHaveBeenCalledWith('/files', {
        params: {
          attachable_type: 'Page',
          attachable_id: 'page-123',
          file_type: 'image',
        },
      });

      expect(result.files).toHaveLength(1);
    });
  });

  describe('getFile', () => {
    it('fetches single file details', async () => {
      const mockResponseData = {
        data: {
          file: {
            id: 'file-123',
            filename: 'test.png',
            urls: {
              view: '/api/v1/files/file-123/view',
              download: '/api/v1/files/file-123/download',
              signed: '/api/v1/files/file-123/signed?token=xyz',
            },
          },
        },
      };

      mockApi.get.mockResolvedValue(createMockResponse(mockResponseData));

      const result = await filesApi.getFile('file-123');

      expect(mockApi.get).toHaveBeenCalledWith('/files/file-123');
      expect(result.id).toBe('file-123');
      expect(result.urls?.view).toBe('/api/v1/files/file-123/view');
    });
  });

  describe('uploadFile with attachable options', () => {
    it('includes attachable_type and attachable_id in FormData when provided', async () => {
      const mockFile = new File(['test'], 'doc.pdf', { type: 'application/pdf' });
      const mockResponseData = {
        data: {
          file: { id: 'file-123', filename: 'doc.pdf' },
        },
      };

      mockApi.post.mockResolvedValue(createMockResponse(mockResponseData));

      await filesApi.uploadFile(mockFile, {
        attachableType: 'Page',
        attachableId: 'page-456',
        category: 'page_content',
      });

      const formDataCall = mockApi.post.mock.calls[0][1] as FormData;
      expect(formDataCall.get('attachable_type')).toBe('Page');
      expect(formDataCall.get('attachable_id')).toBe('page-456');
      expect(formDataCall.get('category')).toBe('page_content');
    });

    it('does not include attachable fields when not provided', async () => {
      const mockFile = new File(['test'], 'doc.pdf', { type: 'application/pdf' });
      const mockResponseData = {
        data: {
          file: { id: 'file-123', filename: 'doc.pdf' },
        },
      };

      mockApi.post.mockResolvedValue(createMockResponse(mockResponseData));

      await filesApi.uploadFile(mockFile, { category: 'user_upload' });

      const formDataCall = mockApi.post.mock.calls[0][1] as FormData;
      expect(formDataCall.get('attachable_type')).toBeNull();
      expect(formDataCall.get('attachable_id')).toBeNull();
    });
  });
});
