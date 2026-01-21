import { useState, useEffect, useCallback } from 'react';
import { containerImagesApi, ContainerImage, ContainerImageDetail, ContainerStatus, Pagination } from '../services/containerImagesApi';

export function useContainerImages(options: {
  page?: number;
  perPage?: number;
  status?: ContainerStatus;
} = {}) {
  const [images, setImages] = useState<ContainerImage[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchImages = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const result = await containerImagesApi.list({
        page: options.page,
        per_page: options.perPage,
        status: options.status,
      });
      setImages(result.images);
      setPagination(result.pagination);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch images');
    } finally {
      setLoading(false);
    }
  }, [options.page, options.perPage, options.status]);

  useEffect(() => {
    fetchImages();
  }, [fetchImages]);

  return { images, pagination, loading, error, refresh: fetchImages };
}

export function useContainerImage(id: string | null) {
  const [image, setImage] = useState<ContainerImageDetail | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchImage = useCallback(async () => {
    if (!id) return;
    try {
      setLoading(true);
      setError(null);
      const result = await containerImagesApi.get(id);
      setImage(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch image');
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    fetchImage();
  }, [fetchImage]);

  return { image, loading, error, refresh: fetchImage };
}
