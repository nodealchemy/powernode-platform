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

// Container image vulnerability hooks
export function useContainerVulnerabilities(imageId: string | null, options: {
  page?: number;
  perPage?: number;
} = {}) {
  const [vulnerabilities, setVulnerabilities] = useState<Array<{
    id: string;
    vulnerability_id: string;
    severity: 'critical' | 'high' | 'medium' | 'low';
    cvss_score: number;
    package_name: string;
    package_version: string;
    fixed_version?: string;
    description?: string;
  }>>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchVulnerabilities = useCallback(async () => {
    if (!imageId) return;
    try {
      setLoading(true);
      setError(null);
      const result = await containerImagesApi.getVulnerabilities(imageId, {
        page: options.page,
        per_page: options.perPage,
      });
      setVulnerabilities(result.vulnerabilities);
      setPagination(result.pagination);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch vulnerabilities');
    } finally {
      setLoading(false);
    }
  }, [imageId, options.page, options.perPage]);

  useEffect(() => {
    fetchVulnerabilities();
  }, [fetchVulnerabilities]);

  return { vulnerabilities, pagination, loading, error, refresh: fetchVulnerabilities };
}

// Container SBOM hook
export function useContainerSbom(imageId: string | null) {
  const [sbom, setSbom] = useState<{
    id: string;
    format: string;
    component_count: number;
    components: Array<{
      name: string;
      version: string;
      type: string;
      licenses: string[];
    }>;
    generated_at: string;
  } | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchSbom = useCallback(async () => {
    if (!imageId) return;
    try {
      setLoading(true);
      setError(null);
      const result = await containerImagesApi.getSbom(imageId);
      setSbom(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch SBOM');
    } finally {
      setLoading(false);
    }
  }, [imageId]);

  useEffect(() => {
    fetchSbom();
  }, [fetchSbom]);

  return { sbom, loading, error, refresh: fetchSbom };
}

// Policy evaluation hook
export function useEvaluatePolicies() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mutateAsync = useCallback(async (imageId: string) => {
    try {
      setLoading(true);
      setError(null);
      const result = await containerImagesApi.evaluatePolicies(imageId);
      return result;
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : 'Failed to evaluate policies';
      setError(errorMsg);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { mutateAsync, isLoading: loading, error };
}
