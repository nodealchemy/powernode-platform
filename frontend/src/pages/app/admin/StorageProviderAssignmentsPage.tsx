import React, { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { useDispatch } from 'react-redux';
import { ArrowLeft } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { useAuth } from '@/shared/hooks/useAuth';
import { addNotification } from '@/shared/services/slices/uiSlice';
import type { AppDispatch } from '@/shared/services';
import { storageApi } from '@/features/admin/storage/services/storageApi';
import type { StorageProvider } from '@/shared/types/storage';
import { StorageProviderAssignmentsTab } from '@/features/system/storage/components/StorageProviderAssignmentsTab';

const StorageProviderAssignmentsPage: React.FC = () => {
  const { storageId } = useParams<{ storageId: string }>();
  const dispatch = useDispatch<AppDispatch>();
  const { currentUser } = useAuth();
  const [provider, setProvider] = useState<StorageProvider | null>(null);
  const [loading, setLoading] = useState(true);

  const canRead = currentUser?.permissions?.includes('system.storage.assignments.read');

  useEffect(() => {
    if (!storageId || !canRead) {
      setLoading(false);
      return;
    }
    storageApi
      .getProvider(storageId)
      .then(setProvider)
      .catch(() => {
        dispatch(addNotification({ type: 'error', message: 'Failed to load storage provider' }));
      })
      .finally(() => setLoading(false));
  }, [storageId, canRead, dispatch]);

  if (!canRead) {
    return (
      <PageContainer title="Forbidden">
        <p className="text-theme-secondary">You don't have permission to view storage assignments.</p>
      </PageContainer>
    );
  }

  if (loading) {
    return (
      <PageContainer title="Loading…">
        <p className="text-theme-secondary">Loading storage provider…</p>
      </PageContainer>
    );
  }

  if (!storageId || !provider) {
    return (
      <PageContainer title="Storage not found">
        <Link to="/admin/storage" className="text-theme-interactive-primary inline-flex items-center">
          <ArrowLeft size={16} className="mr-1" />
          Back to storage providers
        </Link>
      </PageContainer>
    );
  }

  return (
    <PageContainer title={`${provider.name} — Assignments`}>
      <div className="mb-4">
        <Link
          to="/admin/storage"
          className="text-theme-interactive-primary inline-flex items-center text-sm"
        >
          <ArrowLeft size={16} className="mr-1" />
          Back to storage providers
        </Link>
        <p className="text-theme-secondary text-xs mt-1">
          {provider.provider_type.toUpperCase()} storage assigned to node instances
        </p>
      </div>
      <StorageProviderAssignmentsTab storageId={storageId} providerType={provider.provider_type} />
    </PageContainer>
  );
};

export default StorageProviderAssignmentsPage;
