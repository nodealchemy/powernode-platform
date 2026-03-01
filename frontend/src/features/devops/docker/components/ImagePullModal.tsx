import React, { useState, useEffect } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { dockerApi } from '../services/dockerApi';
import { useHostContext } from '../hooks/useHostContext';
import type { ImagePullData, RegistryInfo } from '../types';

interface ImagePullModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (data: ImagePullData) => void;
  isLoading?: boolean;
}

export const ImagePullModal: React.FC<ImagePullModalProps> = ({
  isOpen,
  onClose,
  onSubmit,
  isLoading = false,
}) => {
  const { selectedHostId } = useHostContext();
  const [imageName, setImageName] = useState('');
  const [tag, setTag] = useState('latest');
  const [credentialId, setCredentialId] = useState('');
  const [registries, setRegistries] = useState<RegistryInfo[]>([]);
  const [loadingRegistries, setLoadingRegistries] = useState(false);

  useEffect(() => {
    if (isOpen && selectedHostId) {
      setLoadingRegistries(true);
      dockerApi.getRegistries(selectedHostId).then((response) => {
        if (response.success && response.data) {
          setRegistries(response.data.items ?? []);
        }
        setLoadingRegistries(false);
      });
    }
  }, [isOpen, selectedHostId]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit({
      image: imageName,
      tag: tag || 'latest',
      ...(credentialId && { credential_id: credentialId }),
    });
  };

  const handleClose = () => {
    setImageName('');
    setTag('latest');
    setCredentialId('');
    onClose();
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Pull Image"
      size="lg"
      footer={
        <>
          <button
            onClick={handleClose}
            className="px-4 py-2 text-sm font-medium text-theme-secondary bg-theme-surface border border-theme rounded-lg hover:bg-theme-surface-hover transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={handleSubmit}
            disabled={!imageName || isLoading}
            className="px-4 py-2 text-sm font-medium text-white bg-theme-interactive-primary rounded-lg hover:bg-theme-interactive-primary-hover transition-colors disabled:opacity-50"
          >
            {isLoading ? 'Pulling...' : 'Pull Image'}
          </button>
        </>
      }
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label className="block text-xs font-medium text-theme-secondary mb-1">Image Name *</label>
          <input
            type="text"
            value={imageName}
            onChange={(e) => setImageName(e.target.value)}
            placeholder="nginx"
            className="input-theme w-full text-sm"
            required
          />
        </div>

        <div>
          <label className="block text-xs font-medium text-theme-secondary mb-1">Tag</label>
          <input
            type="text"
            value={tag}
            onChange={(e) => setTag(e.target.value)}
            placeholder="latest"
            className="input-theme w-full text-sm"
          />
        </div>

        <div>
          <label className="block text-xs font-medium text-theme-secondary mb-1">Registry</label>
          {loadingRegistries ? (
            <p className="text-xs text-theme-tertiary animate-pulse">Loading registries...</p>
          ) : (
            <select
              value={credentialId}
              onChange={(e) => setCredentialId(e.target.value)}
              className="input-theme w-full text-sm"
            >
              <option value="">Docker Hub (default)</option>
              {registries.map((reg) => (
                <option key={reg.credential_id} value={reg.credential_id}>
                  {reg.credential_name} ({reg.registry_url})
                </option>
              ))}
            </select>
          )}
        </div>
      </form>
    </Modal>
  );
};
