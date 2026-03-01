import React from 'react';
import { Globe } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { FormField } from '@/shared/components/forms/FormField';
import { TextAreaField } from '@/shared/components/forms/TextAreaField';
import { SelectField } from '@/shared/components/forms/SelectField';
import { useForm } from '@/shared/hooks/useForm';
import { communityAgentsApi } from '@/shared/services/ai';
import type { CreateFederationPartnerRequest, TrustLevel } from '@/shared/services/ai';

interface CreateFederationPartnerModalProps {
  isOpen: boolean;
  onClose: () => void;
  onPartnerCreated?: () => void;
}

interface FormData {
  organization_name: string;
  endpoint_url: string;
  contact_email: string;
  federation_key: string;
  trust_level: string;
}

const TRUST_LEVELS = [
  { value: 'basic', label: 'Basic' },
  { value: 'verified', label: 'Verified' },
  { value: 'trusted', label: 'Trusted' },
  { value: 'partner', label: 'Partner' },
];

export const CreateFederationPartnerModal: React.FC<CreateFederationPartnerModalProps> = ({
  isOpen,
  onClose,
  onPartnerCreated,
}) => {
  const form = useForm<FormData>({
    initialValues: {
      organization_name: '',
      endpoint_url: '',
      contact_email: '',
      federation_key: '',
      trust_level: 'basic',
    },
    validationRules: {
      organization_name: { required: true },
      endpoint_url: {
        required: true,
        pattern: /^https?:\/\/.+/,
      },
      contact_email: {
        pattern: /^[^\s@]+@[^\s@]+\.[^\s@]+$/,
      },
    },
    onSubmit: async (values) => {
      const request: CreateFederationPartnerRequest = {
        organization_name: values.organization_name,
        endpoint_url: values.endpoint_url,
        trust_level: values.trust_level as TrustLevel,
      };
      if (values.contact_email) request.contact_email = values.contact_email;
      if (values.federation_key) request.federation_key = values.federation_key;

      await communityAgentsApi.createFederationPartner(request);
      onPartnerCreated?.();
      onClose();
    },
    successMessage: 'Federation partner created successfully',
    resetAfterSubmit: true,
  });

  const handleClose = () => {
    form.reset();
    onClose();
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Add Federation Partner"
      icon={<Globe className="w-6 h-6" />}
    >
      <form onSubmit={form.handleSubmit} className="space-y-4">
        <FormField
          label="Organization Name"
          name="organization_name"
          form={form}
          required
          placeholder="e.g. Acme Corp"
        />

        <FormField
          label="Endpoint URL"
          name="endpoint_url"
          type="url"
          form={form}
          required
          placeholder="https://agents.example.com/a2a"
        />

        <FormField
          label="Contact Email"
          name="contact_email"
          type="email"
          form={form}
          placeholder="admin@example.com"
        />

        <TextAreaField
          label="Federation Key"
          name="federation_key"
          form={form}
          placeholder="Paste the partner's public federation key..."
          rows={3}
        />

        <SelectField
          label="Trust Level"
          name="trust_level"
          form={form}
          options={TRUST_LEVELS}
        />

        <div className="flex justify-end gap-3 pt-4 border-t border-theme">
          <Button variant="secondary" onClick={handleClose} disabled={form.isSubmitting}>
            Cancel
          </Button>
          <Button variant="primary" type="submit" disabled={form.isSubmitting}>
            {form.isSubmitting ? 'Creating...' : 'Add Partner'}
          </Button>
        </div>
      </form>
    </Modal>
  );
};
