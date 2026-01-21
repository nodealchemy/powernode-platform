import React, { useState, useEffect } from 'react';
import { X, Edit } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';

type VendorType = 'saas' | 'api' | 'library' | 'infrastructure' | 'hardware' | 'consulting';

interface Vendor {
  id: string;
  name: string;
  vendor_type: VendorType;
  contact_name?: string;
  contact_email?: string;
  website?: string;
  handles_pii: boolean;
  handles_phi: boolean;
  handles_pci: boolean;
  certifications: string[];
}

interface EditVendorModalProps {
  vendor: Vendor;
  onClose: () => void;
  onSave: (data: Partial<Vendor>) => Promise<void>;
}

const vendorTypes: { value: VendorType; label: string }[] = [
  { value: 'saas', label: 'SaaS' },
  { value: 'api', label: 'API' },
  { value: 'library', label: 'Library' },
  { value: 'infrastructure', label: 'Infrastructure' },
  { value: 'hardware', label: 'Hardware' },
  { value: 'consulting', label: 'Consulting' },
];

export const EditVendorModal: React.FC<EditVendorModalProps> = ({ vendor, onClose, onSave }) => {
  const [name, setName] = useState(vendor.name);
  const [vendorType, setVendorType] = useState<VendorType>(vendor.vendor_type);
  const [contactName, setContactName] = useState(vendor.contact_name || '');
  const [contactEmail, setContactEmail] = useState(vendor.contact_email || '');
  const [website, setWebsite] = useState(vendor.website || '');
  const [handlesPii, setHandlesPii] = useState(vendor.handles_pii);
  const [handlesPhi, setHandlesPhi] = useState(vendor.handles_phi);
  const [handlesPci, setHandlesPci] = useState(vendor.handles_pci);
  const [certifications, setCertifications] = useState(vendor.certifications.join(', '));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setName(vendor.name);
    setVendorType(vendor.vendor_type);
    setContactName(vendor.contact_name || '');
    setContactEmail(vendor.contact_email || '');
    setWebsite(vendor.website || '');
    setHandlesPii(vendor.handles_pii);
    setHandlesPhi(vendor.handles_phi);
    setHandlesPci(vendor.handles_pci);
    setCertifications(vendor.certifications.join(', '));
  }, [vendor]);

  const handleSubmit = async () => {
    if (!name.trim()) {
      setError('Vendor name is required');
      return;
    }

    try {
      setSaving(true);
      setError(null);
      await onSave({
        name: name.trim(),
        vendor_type: vendorType,
        contact_name: contactName.trim() || undefined,
        contact_email: contactEmail.trim() || undefined,
        website: website.trim() || undefined,
        handles_pii: handlesPii,
        handles_phi: handlesPhi,
        handles_pci: handlesPci,
        certifications: certifications.trim()
          ? certifications.split(',').map((c) => c.trim())
          : [],
      });
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to update vendor');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div className="fixed inset-0 bg-black/50" onClick={onClose} />

      <div className="relative z-10 w-full max-w-lg max-h-[90vh] overflow-y-auto bg-theme-surface rounded-lg shadow-xl mx-4">
        <div className="sticky top-0 bg-theme-surface border-b border-theme px-6 py-4 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Edit className="w-5 h-5 text-theme-interactive-primary" />
            <h2 className="text-lg font-semibold text-theme-primary">Edit Vendor</h2>
          </div>
          <button onClick={onClose} className="p-1 rounded hover:bg-theme-surface-hover">
            <X className="w-5 h-5 text-theme-secondary" />
          </button>
        </div>

        <div className="p-6 space-y-4">
          {error && (
            <div className="p-3 bg-theme-error/10 border border-theme-error/30 rounded-lg text-sm text-theme-error">
              {error}
            </div>
          )}

          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Vendor Name *
            </label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Vendor Type *
            </label>
            <select
              value={vendorType}
              onChange={(e) => setVendorType(e.target.value as VendorType)}
              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
            >
              {vendorTypes.map((type) => (
                <option key={type.value} value={type.value}>
                  {type.label}
                </option>
              ))}
            </select>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-1">
                Contact Name
              </label>
              <input
                type="text"
                value={contactName}
                onChange={(e) => setContactName(e.target.value)}
                className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-1">
                Contact Email
              </label>
              <input
                type="email"
                value={contactEmail}
                onChange={(e) => setContactEmail(e.target.value)}
                className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
              />
            </div>
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Website
            </label>
            <input
              type="url"
              value={website}
              onChange={(e) => setWebsite(e.target.value)}
              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-2">
              Data Handling
            </label>
            <div className="space-y-2">
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={handlesPii}
                  onChange={(e) => setHandlesPii(e.target.checked)}
                  className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
                />
                <span className="text-sm text-theme-primary">Handles PII</span>
              </label>
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={handlesPhi}
                  onChange={(e) => setHandlesPhi(e.target.checked)}
                  className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
                />
                <span className="text-sm text-theme-primary">Handles PHI</span>
              </label>
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={handlesPci}
                  onChange={(e) => setHandlesPci(e.target.checked)}
                  className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
                />
                <span className="text-sm text-theme-primary">Handles PCI Data</span>
              </label>
            </div>
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Certifications
            </label>
            <input
              type="text"
              value={certifications}
              onChange={(e) => setCertifications(e.target.value)}
              placeholder="SOC2, ISO27001, HIPAA (comma-separated)"
              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
            />
          </div>
        </div>

        <div className="sticky bottom-0 bg-theme-surface border-t border-theme px-6 py-4 flex justify-end gap-3">
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" onClick={handleSubmit} disabled={saving}>
            {saving ? 'Saving...' : 'Save Changes'}
          </Button>
        </div>
      </div>
    </div>
  );
};
