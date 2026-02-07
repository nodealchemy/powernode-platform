import { useState, useEffect, useCallback } from 'react';
import { dockerApi } from '../services/dockerApi';
import type { DockerImageSummary, ImageFilters } from '../types';

export function useDockerImages(hostId: string | null, filters?: ImageFilters) {
  const [images, setImages] = useState<DockerImageSummary[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetch = useCallback(async () => {
    if (!hostId) return;
    setIsLoading(true);
    setError(null);
    const response = await dockerApi.getImages(hostId, filters);
    if (response.success && response.data) {
      setImages(response.data.items ?? []);
    } else {
      setError(response.error || 'Failed to fetch images');
    }
    setIsLoading(false);
  }, [hostId, filters?.dangling, filters?.q]);

  useEffect(() => { fetch(); }, [fetch]);

  return { images, isLoading, error, refresh: fetch };
}
