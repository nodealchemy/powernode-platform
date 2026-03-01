import React from 'react';
import { FileText, Image, Film, Music, Archive, X, Download, File } from 'lucide-react';

export interface AttachmentData {
  id?: string;
  name: string;
  type: string;
  size: number;
  url?: string;
  preview_url?: string;
}

interface AttachmentPreviewProps {
  attachments: AttachmentData[];
  onRemove?: (index: number) => void;
  compact?: boolean;
}

function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function getFileIcon(type: string) {
  if (type.startsWith('image/')) return Image;
  if (type.startsWith('video/')) return Film;
  if (type.startsWith('audio/')) return Music;
  if (type.includes('pdf')) return FileText;
  if (type.includes('zip') || type.includes('tar') || type.includes('gz')) return Archive;
  return File;
}

function isImageType(type: string): boolean {
  return type.startsWith('image/');
}

const AttachmentItem: React.FC<{
  attachment: AttachmentData;
  index: number;
  onRemove?: (index: number) => void;
  compact?: boolean;
}> = ({ attachment, index, onRemove, compact = false }) => {
  const Icon = getFileIcon(attachment.type);
  const isImage = isImageType(attachment.type);
  const previewUrl = attachment.preview_url || attachment.url;

  if (isImage && previewUrl && !compact) {
    return (
      <div className="relative group inline-block">
        <img
          src={previewUrl}
          alt={attachment.name}
          className="max-w-[200px] max-h-[150px] rounded-md border border-theme object-cover"
        />
        <div className="absolute bottom-0 left-0 right-0 bg-black/50 text-white text-[10px] px-1.5 py-0.5 rounded-b-md truncate">
          {attachment.name}
        </div>
        {onRemove && (
          <button
            onClick={() => onRemove(index)}
            className="absolute -top-1.5 -right-1.5 h-5 w-5 bg-theme-error text-white rounded-full flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity"
          >
            <X className="h-3 w-3" />
          </button>
        )}
        {!onRemove && attachment.url && (
          <a
            href={attachment.url}
            download={attachment.name}
            className="absolute top-1 right-1 h-6 w-6 bg-black/50 text-white rounded-full flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity"
          >
            <Download className="h-3 w-3" />
          </a>
        )}
      </div>
    );
  }

  return (
    <div className="relative group flex items-center gap-2 px-2 py-1.5 bg-theme-surface-secondary rounded-md border border-theme max-w-[200px]">
      <Icon className="h-4 w-4 flex-shrink-0 text-theme-text-tertiary" />
      <div className="flex-1 min-w-0">
        <p className="text-xs text-theme-primary truncate">{attachment.name}</p>
        <p className="text-[10px] text-theme-text-tertiary">{formatFileSize(attachment.size)}</p>
      </div>
      {onRemove && (
        <button
          onClick={() => onRemove(index)}
          className="flex-shrink-0 p-0.5 rounded hover:bg-theme-error-background text-theme-text-tertiary hover:text-theme-error transition-colors"
        >
          <X className="h-3 w-3" />
        </button>
      )}
      {!onRemove && attachment.url && (
        <a
          href={attachment.url}
          download={attachment.name}
          className="flex-shrink-0 p-0.5 rounded hover:bg-theme-surface-hover text-theme-text-tertiary transition-colors"
        >
          <Download className="h-3 w-3" />
        </a>
      )}
    </div>
  );
};

export const AttachmentPreview: React.FC<AttachmentPreviewProps> = ({
  attachments,
  onRemove,
  compact = false,
}) => {
  if (!attachments.length) return null;

  return (
    <div className="flex flex-wrap gap-2">
      {attachments.map((attachment, index) => (
        <AttachmentItem
          key={attachment.id || `${attachment.name}-${index}`}
          attachment={attachment}
          index={index}
          onRemove={onRemove}
          compact={compact}
        />
      ))}
    </div>
  );
};
