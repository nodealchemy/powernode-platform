import { supplyChainFilesApi } from '../supplyChainFilesApi';
import api from '@/shared/services/api';

jest.mock('@/shared/services/api', () => ({
  __esModule: true,
  default: {
    get: jest.fn(),
    post: jest.fn(),
    delete: jest.fn(),
  },
}));

const mockApi = api as jest.Mocked<typeof api>;

describe('supplyChainFilesApi', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('getEntityFiles', () => {
    const mockFiles = [
      {
        id: 'file-1',
        filename: 'compliance-doc.pdf',
        file_size: 1024,
        category: 'vendor_compliance',
        created_at: '2024-01-15T10:00:00Z',
      },
      {
        id: 'file-2',
        filename: 'certificate.pdf',
        file_size: 2048,
        category: 'vendor_certificate',
        created_at: '2024-01-16T10:00:00Z',
      },
    ];

    it('fetches files for a vendor', async () => {
      mockApi.get.mockResolvedValue({
        data: { data: { files: mockFiles } },
      });

      const result = await supplyChainFilesApi.getEntityFiles(
        'SupplyChain::Vendor',
        'vendor-123'
      );

      expect(mockApi.get).toHaveBeenCalledWith('/files', {
        params: {
          attachable_type: 'SupplyChain::Vendor',
          attachable_id: 'vendor-123',
        },
      });
      expect(result.files).toEqual(mockFiles);
    });

    it('fetches files with category filter', async () => {
      mockApi.get.mockResolvedValue({
        data: { data: { files: [mockFiles[0]] } },
      });

      const result = await supplyChainFilesApi.getEntityFiles(
        'SupplyChain::Vendor',
        'vendor-123',
        'vendor_compliance'
      );

      expect(mockApi.get).toHaveBeenCalledWith('/files', {
        params: {
          attachable_type: 'SupplyChain::Vendor',
          attachable_id: 'vendor-123',
          category: 'vendor_compliance',
        },
      });
      expect(result.files).toHaveLength(1);
    });

    it('fetches files for SBOM', async () => {
      mockApi.get.mockResolvedValue({
        data: { data: { files: [] } },
      });

      await supplyChainFilesApi.getEntityFiles(
        'SupplyChain::Sbom',
        'sbom-123'
      );

      expect(mockApi.get).toHaveBeenCalledWith('/files', {
        params: {
          attachable_type: 'SupplyChain::Sbom',
          attachable_id: 'sbom-123',
        },
      });
    });

    it('fetches files for Attestation', async () => {
      mockApi.get.mockResolvedValue({
        data: { data: { files: [] } },
      });

      await supplyChainFilesApi.getEntityFiles(
        'SupplyChain::Attestation',
        'attestation-123'
      );

      expect(mockApi.get).toHaveBeenCalledWith('/files', {
        params: {
          attachable_type: 'SupplyChain::Attestation',
          attachable_id: 'attestation-123',
        },
      });
    });

    it('fetches files for ContainerImage', async () => {
      mockApi.get.mockResolvedValue({
        data: { data: { files: [] } },
      });

      await supplyChainFilesApi.getEntityFiles(
        'SupplyChain::ContainerImage',
        'image-123'
      );

      expect(mockApi.get).toHaveBeenCalledWith('/files', {
        params: {
          attachable_type: 'SupplyChain::ContainerImage',
          attachable_id: 'image-123',
        },
      });
    });

    it('throws error on API failure', async () => {
      const error = new Error('Network error');
      mockApi.get.mockRejectedValue(error);

      await expect(
        supplyChainFilesApi.getEntityFiles('SupplyChain::Vendor', 'vendor-123')
      ).rejects.toThrow('Network error');
    });
  });

  describe('uploadFile', () => {
    const mockFile = new File(['test content'], 'test.pdf', { type: 'application/pdf' });
    const mockUploadedFile = {
      id: 'file-new',
      filename: 'test.pdf',
      file_size: 12,
      category: 'vendor_compliance',
    };

    it('uploads file to vendor', async () => {
      mockApi.post.mockResolvedValue({
        data: { data: { file: mockUploadedFile } },
      });

      const result = await supplyChainFilesApi.uploadFile(
        'SupplyChain::Vendor',
        'vendor-123',
        mockFile,
        { category: 'vendor_compliance' }
      );

      expect(mockApi.post).toHaveBeenCalledWith(
        '/files/upload',
        expect.any(FormData),
        expect.objectContaining({
          headers: { 'Content-Type': 'multipart/form-data' },
        })
      );

      const formData = mockApi.post.mock.calls[0][1] as FormData;
      expect(formData.get('attachable_type')).toBe('SupplyChain::Vendor');
      expect(formData.get('attachable_id')).toBe('vendor-123');
      expect(formData.get('category')).toBe('vendor_compliance');
      expect(formData.get('filename')).toBe('test.pdf');

      expect(result).toEqual(mockUploadedFile);
    });

    it('includes optional fields when provided', async () => {
      mockApi.post.mockResolvedValue({
        data: { data: { file: mockUploadedFile } },
      });

      await supplyChainFilesApi.uploadFile(
        'SupplyChain::Vendor',
        'vendor-123',
        mockFile,
        {
          category: 'vendor_compliance',
          visibility: 'private',
          description: 'Test description',
          metadata: { key: 'value' },
          tags: ['tag1', 'tag2'],
        }
      );

      const formData = mockApi.post.mock.calls[0][1] as FormData;
      expect(formData.get('visibility')).toBe('private');
      expect(formData.get('description')).toBe('Test description');
      expect(formData.get('metadata')).toBe('{"key":"value"}');
      expect(formData.get('tags')).toBe('tag1,tag2');
    });

    it('calls onProgress callback during upload', async () => {
      const mockOnProgress = jest.fn();
      mockApi.post.mockImplementation((_url, _data, config) => {
        // Simulate progress event
        if (config?.onUploadProgress) {
          config.onUploadProgress({ loaded: 50, total: 100 });
          config.onUploadProgress({ loaded: 100, total: 100 });
        }
        return Promise.resolve({
          data: { data: { file: mockUploadedFile } },
        });
      });

      await supplyChainFilesApi.uploadFile(
        'SupplyChain::Vendor',
        'vendor-123',
        mockFile,
        { category: 'vendor_compliance', onProgress: mockOnProgress }
      );

      expect(mockOnProgress).toHaveBeenCalledWith({
        loaded: 50,
        total: 100,
        percentage: 50,
      });
      expect(mockOnProgress).toHaveBeenCalledWith({
        loaded: 100,
        total: 100,
        percentage: 100,
      });
    });

    it('uploads to SBOM with sbom_export category', async () => {
      mockApi.post.mockResolvedValue({
        data: { data: { file: { ...mockUploadedFile, category: 'sbom_export' } } },
      });

      await supplyChainFilesApi.uploadFile(
        'SupplyChain::Sbom',
        'sbom-123',
        mockFile,
        { category: 'sbom_export' }
      );

      const formData = mockApi.post.mock.calls[0][1] as FormData;
      expect(formData.get('attachable_type')).toBe('SupplyChain::Sbom');
      expect(formData.get('category')).toBe('sbom_export');
    });

    it('throws error on upload failure', async () => {
      const error = new Error('Upload failed');
      mockApi.post.mockRejectedValue(error);

      await expect(
        supplyChainFilesApi.uploadFile(
          'SupplyChain::Vendor',
          'vendor-123',
          mockFile,
          { category: 'vendor_compliance' }
        )
      ).rejects.toThrow('Upload failed');
    });
  });

  describe('deleteFile', () => {
    it('deletes file with soft delete by default', async () => {
      mockApi.delete.mockResolvedValue({ data: { success: true } });

      await supplyChainFilesApi.deleteFile('file-123');

      expect(mockApi.delete).toHaveBeenCalledWith('/files/file-123', {
        params: { permanent: false },
      });
    });

    it('permanently deletes file when specified', async () => {
      mockApi.delete.mockResolvedValue({ data: { success: true } });

      await supplyChainFilesApi.deleteFile('file-123', true);

      expect(mockApi.delete).toHaveBeenCalledWith('/files/file-123', {
        params: { permanent: true },
      });
    });

    it('throws error on delete failure', async () => {
      const error = new Error('Delete failed');
      mockApi.delete.mockRejectedValue(error);

      await expect(supplyChainFilesApi.deleteFile('file-123')).rejects.toThrow(
        'Delete failed'
      );
    });
  });

  describe('downloadFile', () => {
    beforeEach(() => {
      // Mock DOM APIs
      global.URL.createObjectURL = jest.fn(() => 'blob:test-url');
      global.URL.revokeObjectURL = jest.fn();
      document.body.appendChild = jest.fn();
    });

    it('downloads file with given filename', async () => {
      const mockBlob = new Blob(['test content']);
      mockApi.get.mockResolvedValue({ data: mockBlob });

      const mockLink = {
        href: '',
        setAttribute: jest.fn(),
        click: jest.fn(),
        remove: jest.fn(),
      };
      jest.spyOn(document, 'createElement').mockReturnValue(mockLink as unknown as HTMLAnchorElement);

      await supplyChainFilesApi.downloadFile('file-123', 'test.pdf');

      expect(mockApi.get).toHaveBeenCalledWith('/files/file-123/download', {
        responseType: 'blob',
      });
      expect(mockLink.setAttribute).toHaveBeenCalledWith('download', 'test.pdf');
      expect(mockLink.click).toHaveBeenCalled();
      expect(mockLink.remove).toHaveBeenCalled();
      expect(URL.revokeObjectURL).toHaveBeenCalled();
    });

    it('uses default filename when not provided', async () => {
      const mockBlob = new Blob(['test content']);
      mockApi.get.mockResolvedValue({ data: mockBlob });

      const mockLink = {
        href: '',
        setAttribute: jest.fn(),
        click: jest.fn(),
        remove: jest.fn(),
      };
      jest.spyOn(document, 'createElement').mockReturnValue(mockLink as unknown as HTMLAnchorElement);

      await supplyChainFilesApi.downloadFile('file-123');

      expect(mockLink.setAttribute).toHaveBeenCalledWith('download', 'download');
    });
  });

  describe('getDownloadUrl', () => {
    it('returns download URL from file details', async () => {
      mockApi.get.mockResolvedValue({
        data: {
          data: {
            file: {
              id: 'file-123',
              urls: {
                download: 'https://storage.example.com/file-123/download',
              },
            },
          },
        },
      });

      const result = await supplyChainFilesApi.getDownloadUrl('file-123');

      expect(mockApi.get).toHaveBeenCalledWith('/files/file-123');
      expect(result).toBe('https://storage.example.com/file-123/download');
    });

    it('returns empty string when no download URL', async () => {
      mockApi.get.mockResolvedValue({
        data: {
          data: {
            file: {
              id: 'file-123',
              urls: {},
            },
          },
        },
      });

      const result = await supplyChainFilesApi.getDownloadUrl('file-123');

      expect(result).toBe('');
    });
  });

  describe('vendor-specific helpers', () => {
    it('getVendorDocuments calls getEntityFiles with vendor type', async () => {
      mockApi.get.mockResolvedValue({
        data: { data: { files: [] } },
      });

      await supplyChainFilesApi.getVendorDocuments('vendor-123');

      expect(mockApi.get).toHaveBeenCalledWith('/files', {
        params: {
          attachable_type: 'SupplyChain::Vendor',
          attachable_id: 'vendor-123',
        },
      });
    });

    it('getVendorDocuments with category filter', async () => {
      mockApi.get.mockResolvedValue({
        data: { data: { files: [] } },
      });

      await supplyChainFilesApi.getVendorDocuments('vendor-123', 'vendor_compliance');

      expect(mockApi.get).toHaveBeenCalledWith('/files', {
        params: {
          attachable_type: 'SupplyChain::Vendor',
          attachable_id: 'vendor-123',
          category: 'vendor_compliance',
        },
      });
    });

    it('uploadVendorDocument uploads with correct params', async () => {
      const mockFile = new File(['test'], 'test.pdf', { type: 'application/pdf' });
      mockApi.post.mockResolvedValue({
        data: { data: { file: { id: 'file-new' } } },
      });

      await supplyChainFilesApi.uploadVendorDocument(
        'vendor-123',
        mockFile,
        'vendor_compliance',
        { description: 'Test doc' }
      );

      const formData = mockApi.post.mock.calls[0][1] as FormData;
      expect(formData.get('attachable_type')).toBe('SupplyChain::Vendor');
      expect(formData.get('attachable_id')).toBe('vendor-123');
      expect(formData.get('category')).toBe('vendor_compliance');
      expect(formData.get('description')).toBe('Test doc');
    });
  });

  describe('SBOM-specific helpers', () => {
    it('getSbomFiles calls getEntityFiles with sbom type and category', async () => {
      mockApi.get.mockResolvedValue({
        data: { data: { files: [] } },
      });

      await supplyChainFilesApi.getSbomFiles('sbom-123');

      expect(mockApi.get).toHaveBeenCalledWith('/files', {
        params: {
          attachable_type: 'SupplyChain::Sbom',
          attachable_id: 'sbom-123',
          category: 'sbom_export',
        },
      });
    });

    it('uploadSbomExport uploads with sbom_export category', async () => {
      const mockFile = new File(['test'], 'sbom.json', { type: 'application/json' });
      mockApi.post.mockResolvedValue({
        data: { data: { file: { id: 'file-new' } } },
      });

      await supplyChainFilesApi.uploadSbomExport('sbom-123', mockFile);

      const formData = mockApi.post.mock.calls[0][1] as FormData;
      expect(formData.get('attachable_type')).toBe('SupplyChain::Sbom');
      expect(formData.get('category')).toBe('sbom_export');
    });
  });

  describe('Attestation-specific helpers', () => {
    it('getAttestationFiles calls getEntityFiles with attestation type and category', async () => {
      mockApi.get.mockResolvedValue({
        data: { data: { files: [] } },
      });

      await supplyChainFilesApi.getAttestationFiles('attestation-123');

      expect(mockApi.get).toHaveBeenCalledWith('/files', {
        params: {
          attachable_type: 'SupplyChain::Attestation',
          attachable_id: 'attestation-123',
          category: 'attestation_proof',
        },
      });
    });

    it('uploadAttestationProof uploads with attestation_proof category', async () => {
      const mockFile = new File(['test'], 'attestation.sig', { type: 'application/octet-stream' });
      mockApi.post.mockResolvedValue({
        data: { data: { file: { id: 'file-new' } } },
      });

      await supplyChainFilesApi.uploadAttestationProof('attestation-123', mockFile);

      const formData = mockApi.post.mock.calls[0][1] as FormData;
      expect(formData.get('attachable_type')).toBe('SupplyChain::Attestation');
      expect(formData.get('category')).toBe('attestation_proof');
    });
  });

  describe('ContainerImage-specific helpers', () => {
    it('getContainerImageFiles calls getEntityFiles with image type and category', async () => {
      mockApi.get.mockResolvedValue({
        data: { data: { files: [] } },
      });

      await supplyChainFilesApi.getContainerImageFiles('image-123');

      expect(mockApi.get).toHaveBeenCalledWith('/files', {
        params: {
          attachable_type: 'SupplyChain::ContainerImage',
          attachable_id: 'image-123',
          category: 'supply_chain_scan_report',
        },
      });
    });

    it('uploadScanReport uploads with supply_chain_scan_report category', async () => {
      const mockFile = new File(['test'], 'scan.json', { type: 'application/json' });
      mockApi.post.mockResolvedValue({
        data: { data: { file: { id: 'file-new' } } },
      });

      await supplyChainFilesApi.uploadScanReport('image-123', mockFile);

      const formData = mockApi.post.mock.calls[0][1] as FormData;
      expect(formData.get('attachable_type')).toBe('SupplyChain::ContainerImage');
      expect(formData.get('category')).toBe('supply_chain_scan_report');
    });
  });
});
