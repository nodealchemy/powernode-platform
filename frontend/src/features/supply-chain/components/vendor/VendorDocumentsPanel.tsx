import React, { useState, useCallback, useRef } from 'react';
import { Upload, Download, Trash2, FileText, Shield, Award, File, AlertCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { supplyChainFilesApi } from '../../services/supplyChainFilesApi';
import { FileObject } from '@/features/content/files/services/filesApi';
import { formatDistanceToNow } from 'date-fns';

interface VendorDocumentsPanelProps {
  vendorId: string;
  vendorName: string;
}

type VendorDocumentCategory = 'vendor_compliance' | 'vendor_assessment' | 'vendor_certificate';

const CATEGORY_CONFIG: Record<VendorDocumentCategory, {
  label: string;
  icon: React.ElementType;
  color: 'info' | 'warning' | 'success';
  description: string;
}> = {
  vendor_compliance: {
    label: 'Compliance',
    icon: Shield,
    color: 'info',
    description: 'SOC 2, compliance docs'
  },
  vendor_assessment: {
    label: 'Assessment',
    icon: FileText,
    color: 'warning',
    description: 'Risk assessments'
  },
  vendor_certificate: {
    label: 'Certificate',
    icon: Award,
    color: 'success',
    description: 'ISO 27001, SOC2 certs'
  }
};

export const VendorDocumentsPanel: React.FC<VendorDocumentsPanelProps> = ({
  vendorId,
  vendorName
}) => {
  const [files, setFiles] = useState<FileObject[]>([]);
  const [loading, setLoading] = useState(true);
  const [uploading, setUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);
  const [selectedCategory, setSelectedCategory] = useState<VendorDocumentCategory | 'all'>('all');
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const { showNotification } = useNotifications();

  const fetchDocuments = useCallback(async () => {
    try {
      setLoading(true);
      const category = selectedCategory === 'all' ? undefined : selectedCategory;
      const response = await supplyChainFilesApi.getVendorDocuments(vendorId, category);
      setFiles(response.files || []);
    } catch (_error) {
      showNotification('Failed to load documents', 'error');
    } finally {
      setLoading(false);
    }
  }, [vendorId, selectedCategory, showNotification]);

  React.useEffect(() => {
    fetchDocuments();
  }, [fetchDocuments]);

  const handleUploadClick = (category: VendorDocumentCategory) => {
    if (fileInputRef.current) {
      fileInputRef.current.dataset.category = category;
      fileInputRef.current.click();
    }
  };

  const handleFileSelect = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    const category = event.target.dataset.category as VendorDocumentCategory;

    if (!file || !category) return;

    try {
      setUploading(true);
      setUploadProgress(0);

      await supplyChainFilesApi.uploadVendorDocument(vendorId, file, category, {
        onProgress: (progress) => setUploadProgress(progress.percentage),
        description: `${CATEGORY_CONFIG[category].label} document for ${vendorName}`
      });

      showNotification('Document uploaded successfully', 'success');
      fetchDocuments();
    } catch (_error) {
      showNotification('Failed to upload document', 'error');
    } finally {
      setUploading(false);
      setUploadProgress(0);
      if (fileInputRef.current) {
        fileInputRef.current.value = '';
      }
    }
  };

  const handleDownload = async (file: FileObject) => {
    try {
      await supplyChainFilesApi.downloadFile(file.id, file.filename);
    } catch (_error) {
      showNotification('Failed to download file', 'error');
    }
  };

  const handleDelete = async (fileId: string) => {
    try {
      setDeletingId(fileId);
      await supplyChainFilesApi.deleteFile(fileId);
      showNotification('Document deleted successfully', 'success');
      fetchDocuments();
    } catch (_error) {
      showNotification('Failed to delete document', 'error');
    } finally {
      setDeletingId(null);
    }
  };

  const getCategoryForFile = (file: FileObject): VendorDocumentCategory | null => {
    const category = file.category as string;
    if (category in CATEGORY_CONFIG) {
      return category as VendorDocumentCategory;
    }
    return null;
  };

  const getFileIcon = (file: FileObject) => {
    const category = getCategoryForFile(file);
    if (category) {
      const IconComponent = CATEGORY_CONFIG[category].icon;
      return <IconComponent className="w-5 h-5" />;
    }
    return <File className="w-5 h-5" />;
  };

  const formatFileSize = (bytes: number) => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  return (
    <div className="space-y-6">
      {/* Category Filter & Upload Buttons */}
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div className="flex items-center gap-2">
          <span className="text-sm text-theme-secondary">Filter:</span>
          <button
            onClick={() => setSelectedCategory('all')}
            className={`px-3 py-1.5 text-sm rounded-lg transition-colors ${
              selectedCategory === 'all'
                ? 'bg-theme-interactive-primary text-white'
                : 'bg-theme-surface text-theme-secondary hover:text-theme-primary border border-theme'
            }`}
          >
            All
          </button>
          {(Object.entries(CATEGORY_CONFIG) as [VendorDocumentCategory, typeof CATEGORY_CONFIG[VendorDocumentCategory]][]).map(([key, config]) => (
            <button
              key={key}
              onClick={() => setSelectedCategory(key)}
              className={`px-3 py-1.5 text-sm rounded-lg transition-colors flex items-center gap-1.5 ${
                selectedCategory === key
                  ? 'bg-theme-interactive-primary text-white'
                  : 'bg-theme-surface text-theme-secondary hover:text-theme-primary border border-theme'
              }`}
            >
              <config.icon className="w-3.5 h-3.5" />
              {config.label}
            </button>
          ))}
        </div>

        <div className="flex items-center gap-2">
          {(Object.entries(CATEGORY_CONFIG) as [VendorDocumentCategory, typeof CATEGORY_CONFIG[VendorDocumentCategory]][]).map(([key, config]) => (
            <Button
              key={key}
              variant="secondary"
              size="sm"
              onClick={() => handleUploadClick(key)}
              disabled={uploading}
              title={`Upload ${config.label}`}
            >
              <Upload className="w-4 h-4 mr-1" />
              {config.label}
            </Button>
          ))}
        </div>
      </div>

      {/* Upload Progress */}
      {uploading && (
        <div className="bg-theme-surface rounded-lg p-4 border border-theme">
          <div className="flex items-center gap-3">
            <LoadingSpinner size="sm" />
            <div className="flex-1">
              <div className="text-sm text-theme-primary mb-1">Uploading document...</div>
              <div className="w-full bg-theme-bg rounded-full h-2">
                <div
                  className="bg-theme-interactive-primary h-2 rounded-full transition-all duration-300"
                  style={{ width: `${uploadProgress}%` }}
                />
              </div>
            </div>
            <span className="text-sm text-theme-secondary">{uploadProgress}%</span>
          </div>
        </div>
      )}

      {/* Hidden File Input */}
      <input
        ref={fileInputRef}
        type="file"
        className="hidden"
        onChange={handleFileSelect}
        accept=".pdf,.doc,.docx,.xls,.xlsx,.txt,.json,.xml"
      />

      {/* Loading State */}
      {loading && (
        <div className="flex justify-center items-center py-12">
          <LoadingSpinner size="lg" />
        </div>
      )}

      {/* Empty State */}
      {!loading && files.length === 0 && (
        <div className="text-center py-12 bg-theme-surface rounded-lg border border-theme">
          <FileText className="w-12 h-12 mx-auto text-theme-muted mb-4" />
          <h3 className="text-lg font-medium text-theme-primary mb-2">No documents uploaded</h3>
          <p className="text-theme-secondary mb-4">
            Upload compliance documents, risk assessments, or certificates for this vendor.
          </p>
          <div className="flex justify-center gap-2">
            {(Object.entries(CATEGORY_CONFIG) as [VendorDocumentCategory, typeof CATEGORY_CONFIG[VendorDocumentCategory]][]).map(([key, config]) => (
              <Button
                key={key}
                variant="secondary"
                size="sm"
                onClick={() => handleUploadClick(key)}
              >
                <Upload className="w-4 h-4 mr-1" />
                {config.label}
              </Button>
            ))}
          </div>
        </div>
      )}

      {/* Document List */}
      {!loading && files.length > 0 && (
        <div className="space-y-3">
          {files.map((file) => {
            const category = getCategoryForFile(file);
            const categoryConfig = category ? CATEGORY_CONFIG[category] : null;

            return (
              <div
                key={file.id}
                className="bg-theme-surface rounded-lg p-4 border border-theme flex items-center gap-4"
              >
                <div className={`p-2 rounded-lg ${
                  categoryConfig
                    ? `bg-theme-${categoryConfig.color} bg-opacity-10 text-theme-${categoryConfig.color}`
                    : 'bg-theme-bg text-theme-secondary'
                }`}>
                  {getFileIcon(file)}
                </div>

                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <span className="font-medium text-theme-primary truncate">
                      {file.filename}
                    </span>
                    {categoryConfig && (
                      <Badge variant={categoryConfig.color} size="xs">
                        {categoryConfig.label}
                      </Badge>
                    )}
                  </div>
                  <div className="flex items-center gap-3 text-sm text-theme-secondary">
                    <span>{formatFileSize(file.file_size)}</span>
                    <span>•</span>
                    <span>
                      {formatDistanceToNow(new Date(file.created_at), { addSuffix: true })}
                    </span>
                    {file.uploaded_by && (
                      <>
                        <span>•</span>
                        <span>by {file.uploaded_by.name}</span>
                      </>
                    )}
                  </div>
                </div>

                <div className="flex items-center gap-2">
                  <button
                    onClick={() => handleDownload(file)}
                    className="p-2 text-theme-secondary hover:text-theme-primary hover:bg-theme-bg rounded-lg transition-colors"
                    title="Download"
                  >
                    <Download className="w-4 h-4" />
                  </button>
                  <button
                    onClick={() => handleDelete(file.id)}
                    disabled={deletingId === file.id}
                    className="p-2 text-theme-secondary hover:text-theme-error hover:bg-theme-error hover:bg-opacity-10 rounded-lg transition-colors disabled:opacity-50"
                    title="Delete"
                  >
                    {deletingId === file.id ? (
                      <LoadingSpinner size="sm" />
                    ) : (
                      <Trash2 className="w-4 h-4" />
                    )}
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Info Box */}
      <div className="bg-theme-info bg-opacity-10 rounded-lg p-4 flex items-start gap-3">
        <AlertCircle className="w-5 h-5 text-theme-info flex-shrink-0 mt-0.5" />
        <div className="text-sm text-theme-secondary">
          <p className="font-medium text-theme-primary mb-1">Document Types</p>
          <ul className="space-y-1">
            <li><strong>Compliance:</strong> SOC 2 reports, GDPR documentation, privacy policies</li>
            <li><strong>Assessment:</strong> Risk assessments, security questionnaire responses</li>
            <li><strong>Certificate:</strong> ISO 27001, SOC 2 Type II, HIPAA certifications</li>
          </ul>
        </div>
      </div>
    </div>
  );
};
