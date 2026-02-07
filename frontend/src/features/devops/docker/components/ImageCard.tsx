import React from 'react';
import { Card } from '@/shared/components/ui/Card';
import type { DockerImageSummary } from '../types';

interface ImageCardProps {
  image: DockerImageSummary;
  onClick?: (id: string) => void;
}

export const ImageCard: React.FC<ImageCardProps> = ({ image, onClick }) => {
  const formatSize = (mb?: number) => {
    if (!mb) return 'Unknown';
    if (mb < 1) return `${(mb * 1024).toFixed(0)} KB`;
    if (mb >= 1024) return `${(mb / 1024).toFixed(1)} GB`;
    return `${mb.toFixed(1)} MB`;
  };

  return (
    <Card variant="default" padding="md" hoverable clickable={!!onClick} onClick={() => onClick?.(image.id)}>
      <div className="space-y-3">
        <div className="min-w-0">
          <h3 className="text-sm font-semibold text-theme-primary truncate">{image.primary_tag || '<none>'}</h3>
          <p className="text-xs text-theme-tertiary mt-0.5 truncate font-mono">
            {image.docker_image_id.substring(0, 12)}
          </p>
        </div>

        {image.repo_tags.length > 1 && (
          <div className="flex flex-wrap gap-1">
            {image.repo_tags.slice(0, 5).map((tag) => (
              <span
                key={tag}
                className="inline-flex items-center px-1.5 py-0.5 rounded text-xs bg-theme-surface text-theme-secondary"
              >
                {tag}
              </span>
            ))}
            {image.repo_tags.length > 5 && (
              <span className="text-xs text-theme-tertiary">
                +{image.repo_tags.length - 5} more
              </span>
            )}
          </div>
        )}

        <div className="grid grid-cols-3 gap-3 pt-2 border-t border-theme">
          <div>
            <p className="text-xs text-theme-tertiary">Size</p>
            <p className="text-sm font-medium text-theme-primary">{formatSize(image.size_mb)}</p>
          </div>
          <div>
            <p className="text-xs text-theme-tertiary">Containers</p>
            <p className="text-sm font-medium text-theme-primary">{image.container_count}</p>
          </div>
          <div>
            <p className="text-xs text-theme-tertiary">Created</p>
            <p className="text-sm font-medium text-theme-primary">
              {image.docker_created_at
                ? new Date(image.docker_created_at).toLocaleDateString()
                : 'N/A'}
            </p>
          </div>
        </div>
      </div>
    </Card>
  );
};
