import React, { useState } from 'react';
import { GitBranch, Package } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Button } from '@/shared/components/ui/Button';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { containerExecutionApi } from '@/shared/services/ai';
import type { ContainerTemplateSummary, CreateImageRepoRequest } from '@/shared/services/ai';

interface ImageRepoCreateModalProps {
  isOpen: boolean;
  onClose: () => void;
  baseTemplates: ContainerTemplateSummary[];
  onCreated?: () => void;
}

const variantOptions = [
  { value: 'base', label: 'Base', description: 'Alpine + MCP entrypoint (curl, jq, bash, openssl)' },
  { value: 'code', label: 'Code', description: 'Base + Node.js, Python, Git, build tools' },
  { value: 'data', label: 'Data', description: 'Base + Python, pandas, numpy' },
  { value: 'media', label: 'Media', description: 'Base + ffmpeg, ImageMagick, libvips' },
  { value: 'full', label: 'Full', description: 'All tools combined (for trusted/autonomous agents)' },
  { value: 'custom', label: 'Custom', description: 'Base only — add your own packages' },
];

export const ImageRepoCreateModal: React.FC<ImageRepoCreateModalProps> = ({
  isOpen,
  onClose,
  baseTemplates,
  onCreated,
}) => {
  const { addNotification } = useNotifications();
  const [name, setName] = useState('');
  const [variantType, setVariantType] = useState<CreateImageRepoRequest['variant_type']>('code');
  const [parentTemplateId, setParentTemplateId] = useState('');
  const [isCreating, setIsCreating] = useState(false);

  const handleCreate = async () => {
    if (!name.trim()) return;

    setIsCreating(true);
    try {
      const request: CreateImageRepoRequest = {
        name: name.trim(),
        variant_type: variantType,
      };

      if (parentTemplateId && variantType !== 'base') {
        request.parent_template_id = parentTemplateId;
      }

      const response = await containerExecutionApi.createImageRepo(request);

      addNotification({
        type: 'success',
        title: 'Image Repo Created',
        message: `Repository "${response.repository.full_name}" created with ${response.files_created.length} files`,
      });

      onCreated?.();
      handleClose();
    } catch (err) {
      addNotification({
        type: 'error',
        title: 'Creation Failed',
        message: err instanceof Error ? err.message : 'Failed to create image repository',
      });
    } finally {
      setIsCreating(false);
    }
  };

  const handleClose = () => {
    setName('');
    setVariantType('code');
    setParentTemplateId('');
    onClose();
  };

  const selectedVariant = variantOptions.find((v) => v.value === variantType);

  const footer = (
    <div className="flex items-center justify-end gap-2">
      <Button variant="outline" onClick={handleClose} disabled={isCreating}>
        Cancel
      </Button>
      <Button variant="primary" onClick={handleCreate} disabled={isCreating || !name.trim()}>
        {isCreating ? 'Creating...' : 'Create Repository'}
      </Button>
    </div>
  );

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Create Agent Image Repository"
      subtitle="Scaffold a new Gitea repo with Dockerfile and CI/CD"
      icon={<Package className="w-5 h-5" />}
      footer={footer}
      maxWidth="lg"
    >
      <div className="space-y-5">
        <Input
          label="Image Name"
          placeholder="agent-code"
          value={name}
          onChange={(e) => setName(e.target.value)}
          description="Used as the Gitea repo name and Docker image name"
        />

        <div className="space-y-2">
          <label className="text-sm font-medium text-theme-text-primary">Variant Type</label>
          <Select
            value={variantType}
            onChange={(value) => setVariantType(value as CreateImageRepoRequest['variant_type'])}
          >
            {variantOptions.map((opt) => (
              <option key={opt.value} value={opt.value}>
                {opt.label}
              </option>
            ))}
          </Select>
          {selectedVariant && (
            <p className="text-xs text-theme-text-secondary">{selectedVariant.description}</p>
          )}
        </div>

        {variantType !== 'base' && (
          <div className="space-y-2">
            <label className="text-sm font-medium text-theme-text-primary">
              <GitBranch className="w-4 h-4 inline mr-1" />
              Parent Base Image
            </label>
            <Select
              value={parentTemplateId}
              onChange={(value) => setParentTemplateId(value)}
            >
              <option value="">Auto-detect (agent-base)</option>
              {baseTemplates.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.name}
                </option>
              ))}
            </Select>
            <p className="text-xs text-theme-text-secondary">
              Variant images inherit from the selected base. Rebuilding the base triggers cascade rebuilds.
            </p>
          </div>
        )}
      </div>
    </Modal>
  );
};

export default ImageRepoCreateModal;
