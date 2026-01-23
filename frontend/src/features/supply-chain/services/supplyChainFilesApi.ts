import api from '@/shared/services/api';
import { FileObject, FileUploadProgress } from '@/features/content/files/services/filesApi';

export type SupplyChainFileCategory =
  | 'sbom_export'
  | 'attestation_proof'
  | 'supply_chain_scan_report'
  | 'vendor_compliance'
  | 'vendor_assessment'
  | 'vendor_certificate';

export type SupplyChainAttachableType =
  | 'SupplyChain::Sbom'
  | 'SupplyChain::Attestation'
  | 'SupplyChain::ContainerImage'
  | 'SupplyChain::Vendor';

export interface SupplyChainFileUploadOptions {
  category: SupplyChainFileCategory;
  onProgress?: (progress: FileUploadProgress) => void;
  visibility?: string;
  description?: string;
  metadata?: Record<string, unknown>;
  tags?: string[];
}

export const supplyChainFilesApi = {
  /**
   * Get files attached to a supply chain entity
   */
  async getEntityFiles(
    attachableType: SupplyChainAttachableType,
    attachableId: string,
    category?: SupplyChainFileCategory
  ): Promise<{ files: FileObject[] }> {
    const response = await api.get('/files', {
      params: {
        attachable_type: attachableType,
        attachable_id: attachableId,
        ...(category && { category })
      }
    });
    return response.data.data;
  },

  /**
   * Upload a file and attach it to a supply chain entity
   */
  async uploadFile(
    attachableType: SupplyChainAttachableType,
    attachableId: string,
    file: File,
    options: SupplyChainFileUploadOptions
  ): Promise<FileObject> {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('filename', file.name);
    formData.append('attachable_type', attachableType);
    formData.append('attachable_id', attachableId);
    formData.append('category', options.category);

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

  /**
   * Delete a file
   */
  async deleteFile(fileId: string, permanent: boolean = false): Promise<void> {
    await api.delete(`/files/${fileId}`, {
      params: { permanent }
    });
  },

  /**
   * Download a file
   */
  async downloadFile(fileId: string, filename?: string): Promise<void> {
    const response = await api.get(`/files/${fileId}/download`, {
      responseType: 'blob'
    });

    const url = window.URL.createObjectURL(new Blob([response.data]));
    const link = document.createElement('a');
    link.href = url;
    link.setAttribute('download', filename || 'download');
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.URL.revokeObjectURL(url);
  },

  /**
   * Get download URL for a file
   */
  async getDownloadUrl(fileId: string): Promise<string> {
    const response = await api.get(`/files/${fileId}`);
    return response.data.data.file.urls?.download || '';
  },

  // Vendor-specific helpers
  async getVendorDocuments(vendorId: string, category?: SupplyChainFileCategory) {
    return this.getEntityFiles('SupplyChain::Vendor', vendorId, category);
  },

  async uploadVendorDocument(
    vendorId: string,
    file: File,
    category: 'vendor_compliance' | 'vendor_assessment' | 'vendor_certificate',
    options?: Omit<SupplyChainFileUploadOptions, 'category'>
  ) {
    return this.uploadFile('SupplyChain::Vendor', vendorId, file, {
      ...options,
      category
    });
  },

  // SBOM-specific helpers
  async getSbomFiles(sbomId: string) {
    return this.getEntityFiles('SupplyChain::Sbom', sbomId, 'sbom_export');
  },

  async uploadSbomExport(
    sbomId: string,
    file: File,
    options?: Omit<SupplyChainFileUploadOptions, 'category'>
  ) {
    return this.uploadFile('SupplyChain::Sbom', sbomId, file, {
      ...options,
      category: 'sbom_export'
    });
  },

  // Attestation-specific helpers
  async getAttestationFiles(attestationId: string) {
    return this.getEntityFiles('SupplyChain::Attestation', attestationId, 'attestation_proof');
  },

  async uploadAttestationProof(
    attestationId: string,
    file: File,
    options?: Omit<SupplyChainFileUploadOptions, 'category'>
  ) {
    return this.uploadFile('SupplyChain::Attestation', attestationId, file, {
      ...options,
      category: 'attestation_proof'
    });
  },

  // Container Image-specific helpers
  async getContainerImageFiles(imageId: string) {
    return this.getEntityFiles('SupplyChain::ContainerImage', imageId, 'supply_chain_scan_report');
  },

  async uploadScanReport(
    imageId: string,
    file: File,
    options?: Omit<SupplyChainFileUploadOptions, 'category'>
  ) {
    return this.uploadFile('SupplyChain::ContainerImage', imageId, file, {
      ...options,
      category: 'supply_chain_scan_report'
    });
  }
};
