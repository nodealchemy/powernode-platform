import React from 'react';
import { X, Save, Key } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Modal } from '@/shared/components/ui/Modal';
import { CredentialCard, AddCredentialForm, ProviderFormFields } from './edit-provider';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useEditProviderForm } from './useEditProviderForm';

interface EditProviderModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
  providerId: string;
}

export const EditProviderModal: React.FC<EditProviderModalProps> = ({
  isOpen,
  onClose,
  onSuccess,
  providerId
}) => {
  const {
    loading,
    initialLoading,
    credentials,
    formData,
    credentialData,
    credentialLoading,
    editingCredentialId,
    editCredentialData,
    setEditCredentialData,
    handleSubmit,
    handleInputChange,
    handleCredentialChange,
    handleCapabilityChange,
    handleDeleteCredential,
    handleTestCredential,
    handleStartEditCredential,
    handleCancelEditCredential,
    handleSaveEditCredential,
    handleMakeDefault,
    handleClose,
  } = useEditProviderForm(providerId, isOpen, onSuccess, onClose);

  if (initialLoading) {
    return (
      <Modal isOpen={isOpen} onClose={handleClose} size="lg">
        <div className="flex items-center justify-between p-6 border-b border-theme">
          <h2 className="text-xl font-semibold text-theme-primary">Loading Provider...</h2>
          <Button
            variant="ghost"
            size="sm"
            onClick={handleClose}
            className="h-8 w-8 p-0"
          >
            <X className="h-4 w-4" />
          </Button>
        </div>
        <LoadingSpinner className="p-6" />
      </Modal>
    );
  }

  return (
    <Modal isOpen={isOpen} onClose={handleClose} size="lg">
      <div className="flex items-center justify-between p-6 border-b border-theme">
        <h2 className="text-xl font-semibold text-theme-primary">Edit AI Provider</h2>
        <Button
          variant="ghost"
          size="sm"
          onClick={handleClose}
          className="h-8 w-8 p-0"
        >
          <X className="h-4 w-4" />
        </Button>
      </div>

      <form onSubmit={handleSubmit} className="p-6 space-y-6">
        <ProviderFormFields
          data={formData}
          onChange={handleInputChange}
          onCapabilityChange={handleCapabilityChange}
        />

        {/* Credentials Management */}
        <div className="space-y-4">
          <div className="border-t border-theme pt-4">
            <h4 className="text-sm font-semibold text-theme-primary flex items-center gap-2">
              <Key className="h-4 w-4" />
              Credentials Management
            </h4>
            <p className="text-sm text-theme-muted mt-1">
              Manage API credentials for this provider. Existing credentials are listed below, and you can add a new credential using the form.
            </p>
          </div>

          {/* Existing Credentials */}
          {credentials.length > 0 && (
            <div className="space-y-2">
              <h5 className="text-sm font-medium text-theme-secondary">Existing Credentials ({credentials.length})</h5>
              <div className="space-y-2">
                {credentials.map((credential) => (
                  <CredentialCard
                    key={credential.id}
                    credential={credential}
                    isEditing={editingCredentialId === credential.id}
                    editData={editCredentialData}
                    isLoading={credentialLoading}
                    onStartEdit={() => handleStartEditCredential(credential)}
                    onCancelEdit={handleCancelEditCredential}
                    onSaveEdit={handleSaveEditCredential}
                    onEditDataChange={(data) => setEditCredentialData(prev => ({ ...prev, ...data }))}
                    onTest={() => handleTestCredential(credential.id)}
                    onDelete={() => handleDeleteCredential(credential.id)}
                    onMakeDefault={() => handleMakeDefault(credential.id)}
                  />
                ))}
              </div>
            </div>
          )}

          {/* Add New Credential Form */}
          <AddCredentialForm
            data={credentialData}
            onChange={handleCredentialChange}
            disabled={loading}
          />
        </div>

        <div className="flex items-center justify-end space-x-3 pt-4 border-t border-theme">
          <Button
            type="button"
            variant="outline"
            onClick={handleClose}
            disabled={loading}
          >
            Cancel
          </Button>
          <Button
            type="submit"
            disabled={loading || !formData.name}
            className="flex items-center gap-2"
          >
            <Save className="h-4 w-4" />
            {loading ? 'Updating...' : 'Update Provider'}
          </Button>
        </div>
      </form>
    </Modal>
  );
};
