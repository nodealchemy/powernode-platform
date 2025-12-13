
import {
  FileText, Image, Video, Music, Archive, Code, FileType,
  Download, Share2, Trash2, Eye
} from 'lucide-react';
import { FileObject } from '../services/filesApi';

interface FileItemProps {
  file: FileObject;
  onView?: (file: FileObject) => void;
  onDownload?: (file: FileObject) => void;
  onShare?: (file: FileObject) => void;
  onDelete?: (file: FileObject) => void;
  showActions?: boolean;
}

export const FileItem: React.FC<FileItemProps> = ({
  file,
  onView,
  onDownload,
  onShare,
  onDelete,
  showActions = true
}) => {
  const getFileIcon = () => {
    const iconClass = "h-10 w-10";

    switch (file.file_type) {
      case 'image':
        return <Image className={`${iconClass} text-theme-interactive-primary`} />;
      case 'video':
        return <Video className={`${iconClass} text-theme-danger`} />;
      case 'audio':
        return <Music className={`${iconClass} text-theme-success`} />;
      case 'document':
        return <FileText className={`${iconClass} text-theme-info`} />;
      case 'archive':
        return <Archive className={`${iconClass} text-theme-warning`} />;
      case 'code':
        return <Code className={`${iconClass} text-theme-primary`} />;
      default:
        return <FileType className={`${iconClass} text-theme-secondary`} />;
    }
  };

  const formatFileSize = (bytes: number): string => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
  };

  const formatDate = (dateString: string): string => {
    const date = new Date(dateString);
    const now = new Date();
    const diffInSeconds = Math.floor((now.getTime() - date.getTime()) / 1000);

    if (diffInSeconds < 60) return 'Just now';
    if (diffInSeconds < 3600) return `${Math.floor(diffInSeconds / 60)}m ago`;
    if (diffInSeconds < 86400) return `${Math.floor(diffInSeconds / 3600)}h ago`;
    if (diffInSeconds < 604800) return `${Math.floor(diffInSeconds / 86400)}d ago`;

    return date.toLocaleDateString();
  };

  const getCategoryBadgeColor = (category: string): string => {
    switch (category) {
      case 'user_upload':
        return 'bg-theme-info/20 text-theme-info dark:bg-theme-info/30 dark:text-theme-info';
      case 'workflow_output':
        return 'bg-theme-success/20 text-theme-success dark:bg-theme-success/30 dark:text-theme-success';
      case 'ai_generated':
        return 'bg-theme-interactive-primary/20 text-theme-interactive-primary dark:bg-theme-interactive-primary/30 dark:text-theme-interactive-primary';
      case 'temp':
        return 'bg-theme-warning/20 text-theme-warning dark:bg-theme-warning/30 dark:text-theme-warning';
      default:
        return 'bg-theme-surface text-theme-secondary dark:bg-theme-surface dark:text-theme-secondary';
    }
  };

  return (
    <div className="flex items-center gap-4 p-4 bg-theme-surface border border-theme rounded-lg hover:bg-theme-surface dark:hover:bg-theme-surface transition-colors group">
      {/* File Icon */}
      <div className="flex-shrink-0">
        {getFileIcon()}
      </div>

      {/* File Info */}
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <h4
            className="text-sm font-medium text-theme-primary truncate cursor-pointer hover:text-theme-info"
            onClick={() => onView?.(file)}
          >
            {file.filename}
          </h4>

          {/* Category Badge */}
          <span className={`px-2 py-0.5 text-xs font-medium rounded ${getCategoryBadgeColor(file.category)}`}>
            {file.category.replace('_', ' ')}
          </span>

          {/* Tags */}
          {file.tags && file.tags.length > 0 && (
            <div className="flex gap-1">
              {file.tags.slice(0, 2).map(tag => (
                <span
                  key={tag.id}
                  className="px-2 py-0.5 text-xs rounded"
                  style={{
                    backgroundColor: tag.color + '20',
                    color: tag.color
                  }}
                >
                  {tag.name}
                </span>
              ))}
              {file.tags.length > 2 && (
                <span className="px-2 py-0.5 text-xs text-theme-secondary">
                  +{file.tags.length - 2}
                </span>
              )}
            </div>
          )}
        </div>

        <div className="flex items-center gap-4 mt-1 text-xs text-theme-secondary">
          <span>{formatFileSize(file.file_size)}</span>
          <span>•</span>
          <span>{formatDate(file.created_at)}</span>
          {file.uploaded_by && (
            <>
              <span>•</span>
              <span>by {file.uploaded_by.name}</span>
            </>
          )}
        </div>
      </div>

      {/* Actions */}
      {showActions && (
        <div className="flex-shrink-0 flex items-center gap-2 opacity-0 group-hover:opacity-100 transition-opacity">
          <button
            onClick={(e) => {
              e.stopPropagation();
              onView?.(file);
            }}
            className="p-2 text-theme-secondary hover:text-theme-info hover:bg-theme-info/10 dark:hover:bg-theme-info/20 rounded"
            title="View details"
          >
            <Eye className="h-4 w-4" />
          </button>

          <button
            onClick={(e) => {
              e.stopPropagation();
              onDownload?.(file);
            }}
            className="p-2 text-theme-secondary hover:text-theme-success hover:bg-theme-success/10 dark:hover:bg-theme-success/20 rounded"
            title="Download"
          >
            <Download className="h-4 w-4" />
          </button>

          <button
            onClick={(e) => {
              e.stopPropagation();
              onShare?.(file);
            }}
            className="p-2 text-theme-secondary hover:text-theme-interactive-primary hover:bg-theme-interactive-primary/10 dark:hover:bg-theme-interactive-primary/20 rounded"
            title="Share"
          >
            <Share2 className="h-4 w-4" />
          </button>

          <button
            onClick={(e) => {
              e.stopPropagation();
              onDelete?.(file);
            }}
            className="p-2 text-theme-secondary hover:text-theme-danger hover:bg-theme-danger/10 dark:hover:bg-theme-danger/20 rounded"
            title="Delete"
          >
            <Trash2 className="h-4 w-4" />
          </button>
        </div>
      )}
    </div>
  );
};

