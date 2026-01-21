import React, { useState, useEffect } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Save, X, Plus, AlertTriangle, Info } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import ErrorAlert from '@/shared/components/ui/ErrorAlert';
import { useNotifications } from '@/shared/hooks/useNotifications';
import {
  useLicensePolicy,
  useCreateLicensePolicy,
  useUpdateLicensePolicy,
} from '../hooks/useLicenseCompliance';
import type { LicensePolicyType, EnforcementLevel, CreateLicensePolicyData } from '../services/licenseComplianceApi';

// Common SPDX license identifiers for quick selection
const COMMON_LICENSES = [
  { id: 'MIT', name: 'MIT License', category: 'permissive' },
  { id: 'Apache-2.0', name: 'Apache License 2.0', category: 'permissive' },
  { id: 'BSD-2-Clause', name: 'BSD 2-Clause', category: 'permissive' },
  { id: 'BSD-3-Clause', name: 'BSD 3-Clause', category: 'permissive' },
  { id: 'ISC', name: 'ISC License', category: 'permissive' },
  { id: 'GPL-2.0-only', name: 'GPL 2.0', category: 'copyleft' },
  { id: 'GPL-3.0-only', name: 'GPL 3.0', category: 'copyleft' },
  { id: 'LGPL-2.1-only', name: 'LGPL 2.1', category: 'weak-copyleft' },
  { id: 'LGPL-3.0-only', name: 'LGPL 3.0', category: 'weak-copyleft' },
  { id: 'MPL-2.0', name: 'Mozilla Public License 2.0', category: 'weak-copyleft' },
  { id: 'AGPL-3.0-only', name: 'AGPL 3.0', category: 'network-copyleft' },
  { id: 'Unlicense', name: 'Unlicense', category: 'public-domain' },
  { id: 'CC0-1.0', name: 'CC0 1.0', category: 'public-domain' },
  { id: 'WTFPL', name: 'WTFPL', category: 'public-domain' },
];

const POLICY_TYPES: { value: LicensePolicyType; label: string; description: string }[] = [
  { value: 'allowlist', label: 'Allowlist', description: 'Only explicitly allowed licenses are permitted' },
  { value: 'denylist', label: 'Denylist', description: 'All licenses are allowed except those explicitly denied' },
  { value: 'hybrid', label: 'Hybrid', description: 'Combines allowlist and denylist rules' },
];

const ENFORCEMENT_LEVELS: { value: EnforcementLevel; label: string; description: string; color: string }[] = [
  { value: 'log', label: 'Log Only', description: 'Log violations without blocking', color: 'text-theme-info' },
  { value: 'warn', label: 'Warn', description: 'Show warnings but allow builds to proceed', color: 'text-theme-warning' },
  { value: 'block', label: 'Block', description: 'Block builds with license violations', color: 'text-theme-error' },
];

interface FormData {
  name: string;
  description: string;
  policy_type: LicensePolicyType;
  enforcement_level: EnforcementLevel;
  is_active: boolean;
  block_copyleft: boolean;
  block_strong_copyleft: boolean;
  block_network_copyleft: boolean;
  block_unknown: boolean;
  require_osi_approved: boolean;
  require_attribution: boolean;
  allowed_licenses: string[];
  denied_licenses: string[];
}

const initialFormData: FormData = {
  name: '',
  description: '',
  policy_type: 'denylist',
  enforcement_level: 'warn',
  is_active: true,
  block_copyleft: false,
  block_strong_copyleft: false,
  block_network_copyleft: false,
  block_unknown: false,
  require_osi_approved: false,
  require_attribution: false,
  allowed_licenses: [],
  denied_licenses: [],
};

export const LicensePolicyFormPage: React.FC = () => {
  const navigate = useNavigate();
  const { id } = useParams<{ id: string }>();
  const isEditing = !!id;
  const { showNotification } = useNotifications();

  const [formData, setFormData] = useState<FormData>(initialFormData);
  const [newAllowedLicense, setNewAllowedLicense] = useState('');
  const [newDeniedLicense, setNewDeniedLicense] = useState('');
  const [errors, setErrors] = useState<Record<string, string>>({});

  const { data: existingPolicy, isLoading: loadingPolicy, error: loadError } = useLicensePolicy(id || '');
  const createMutation = useCreateLicensePolicy();
  const updateMutation = useUpdateLicensePolicy();

  useEffect(() => {
    if (existingPolicy) {
      setFormData({
        name: existingPolicy.name,
        description: existingPolicy.description || '',
        policy_type: existingPolicy.policy_type,
        enforcement_level: existingPolicy.enforcement_level,
        is_active: existingPolicy.is_active,
        block_copyleft: existingPolicy.block_copyleft || false,
        block_strong_copyleft: existingPolicy.block_strong_copyleft || false,
        block_network_copyleft: existingPolicy.block_network_copyleft || false,
        block_unknown: existingPolicy.block_unknown || false,
        require_osi_approved: existingPolicy.require_osi_approved || false,
        require_attribution: existingPolicy.require_attribution || false,
        allowed_licenses: existingPolicy.allowed_licenses || [],
        denied_licenses: existingPolicy.denied_licenses || [],
      });
    }
  }, [existingPolicy]);

  const validateForm = (): boolean => {
    const newErrors: Record<string, string> = {};

    if (!formData.name.trim()) {
      newErrors.name = 'Policy name is required';
    }

    if (formData.policy_type === 'allowlist' && formData.allowed_licenses.length === 0) {
      newErrors.allowed_licenses = 'Allowlist policy requires at least one allowed license';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!validateForm()) return;

    const submitData: CreateLicensePolicyData = {
      name: formData.name.trim(),
      description: formData.description.trim() || undefined,
      policy_type: formData.policy_type,
      enforcement_level: formData.enforcement_level,
      is_active: formData.is_active,
      block_copyleft: formData.block_copyleft,
      block_strong_copyleft: formData.block_strong_copyleft,
      block_network_copyleft: formData.block_network_copyleft,
      block_unknown: formData.block_unknown,
      require_osi_approved: formData.require_osi_approved,
      require_attribution: formData.require_attribution,
      allowed_licenses: formData.allowed_licenses.length > 0 ? formData.allowed_licenses : undefined,
      denied_licenses: formData.denied_licenses.length > 0 ? formData.denied_licenses : undefined,
    };

    try {
      if (isEditing) {
        await updateMutation.mutateAsync({ id, data: submitData });
        showNotification('License policy updated successfully', 'success');
      } else {
        await createMutation.mutateAsync(submitData);
        showNotification('License policy created successfully', 'success');
      }
      navigate('/app/supply-chain/licenses/policies');
    } catch (err) {
      showNotification(
        err instanceof Error ? err.message : 'Failed to save policy',
        'error'
      );
    }
  };

  const handleAddLicense = (type: 'allowed' | 'denied') => {
    const license = type === 'allowed' ? newAllowedLicense.trim() : newDeniedLicense.trim();
    if (!license) return;

    const field = type === 'allowed' ? 'allowed_licenses' : 'denied_licenses';
    if (!formData[field].includes(license)) {
      setFormData(prev => ({
        ...prev,
        [field]: [...prev[field], license],
      }));
    }

    if (type === 'allowed') {
      setNewAllowedLicense('');
    } else {
      setNewDeniedLicense('');
    }
  };

  const handleRemoveLicense = (type: 'allowed' | 'denied', license: string) => {
    const field = type === 'allowed' ? 'allowed_licenses' : 'denied_licenses';
    setFormData(prev => ({
      ...prev,
      [field]: prev[field].filter(l => l !== license),
    }));
  };

  const handleQuickAddLicense = (type: 'allowed' | 'denied', licenseId: string) => {
    const field = type === 'allowed' ? 'allowed_licenses' : 'denied_licenses';
    if (!formData[field].includes(licenseId)) {
      setFormData(prev => ({
        ...prev,
        [field]: [...prev[field], licenseId],
      }));
    }
  };

  if (isEditing && loadingPolicy) {
    return (
      <div className="flex justify-center items-center min-h-screen">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  if (isEditing && loadError) {
    return (
      <PageContainer
        title="License Policy"
        breadcrumbs={[
          { label: 'Dashboard', href: '/app' },
          { label: 'Supply Chain', href: '/app/supply-chain' },
          { label: 'License Policies', href: '/app/supply-chain/licenses/policies' },
          { label: 'Edit' },
        ]}
      >
        <ErrorAlert message="Failed to load policy" />
      </PageContainer>
    );
  }

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Supply Chain', href: '/app/supply-chain' },
    { label: 'License Policies', href: '/app/supply-chain/licenses/policies' },
    { label: isEditing ? 'Edit Policy' : 'New Policy' },
  ];

  const isSubmitting = createMutation.isLoading || updateMutation.isLoading;

  return (
    <PageContainer
      title={isEditing ? 'Edit License Policy' : 'Create License Policy'}
      description={isEditing ? 'Update license compliance policy settings' : 'Define a new license compliance policy'}
      breadcrumbs={breadcrumbs}
    >
      <form onSubmit={handleSubmit} className="space-y-6 max-w-4xl">
        {/* Basic Information */}
        <Card className="p-6">
          <h2 className="text-lg font-semibold text-theme-primary mb-4">Basic Information</h2>
          <div className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-1">
                Policy Name <span className="text-theme-error">*</span>
              </label>
              <input
                type="text"
                value={formData.name}
                onChange={(e) => setFormData(prev => ({ ...prev, name: e.target.value }))}
                className={`w-full px-3 py-2 border rounded-lg bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary ${
                  errors.name ? 'border-theme-error' : 'border-theme'
                }`}
                placeholder="e.g., Production Strict Policy"
              />
              {errors.name && <p className="text-sm text-theme-error mt-1">{errors.name}</p>}
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-1">Description</label>
              <textarea
                value={formData.description}
                onChange={(e) => setFormData(prev => ({ ...prev, description: e.target.value }))}
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                rows={3}
                placeholder="Describe the purpose and scope of this policy..."
              />
            </div>

            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                id="is_active"
                checked={formData.is_active}
                onChange={(e) => setFormData(prev => ({ ...prev, is_active: e.target.checked }))}
                className="rounded border-theme"
              />
              <label htmlFor="is_active" className="text-sm text-theme-primary">
                Policy is active
              </label>
            </div>
          </div>
        </Card>

        {/* Policy Type & Enforcement */}
        <Card className="p-6">
          <h2 className="text-lg font-semibold text-theme-primary mb-4">Policy Type & Enforcement</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-2">Policy Type</label>
              <div className="space-y-2">
                {POLICY_TYPES.map((type) => (
                  <label
                    key={type.value}
                    className={`flex items-start gap-3 p-3 rounded-lg border cursor-pointer transition-colors ${
                      formData.policy_type === type.value
                        ? 'border-theme-primary bg-theme-primary/5'
                        : 'border-theme hover:border-theme-primary/50'
                    }`}
                  >
                    <input
                      type="radio"
                      name="policy_type"
                      value={type.value}
                      checked={formData.policy_type === type.value}
                      onChange={(e) => setFormData(prev => ({ ...prev, policy_type: e.target.value as LicensePolicyType }))}
                      className="mt-1"
                    />
                    <div>
                      <div className="font-medium text-theme-primary">{type.label}</div>
                      <div className="text-sm text-theme-secondary">{type.description}</div>
                    </div>
                  </label>
                ))}
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-2">Enforcement Level</label>
              <div className="space-y-2">
                {ENFORCEMENT_LEVELS.map((level) => (
                  <label
                    key={level.value}
                    className={`flex items-start gap-3 p-3 rounded-lg border cursor-pointer transition-colors ${
                      formData.enforcement_level === level.value
                        ? 'border-theme-primary bg-theme-primary/5'
                        : 'border-theme hover:border-theme-primary/50'
                    }`}
                  >
                    <input
                      type="radio"
                      name="enforcement_level"
                      value={level.value}
                      checked={formData.enforcement_level === level.value}
                      onChange={(e) => setFormData(prev => ({ ...prev, enforcement_level: e.target.value as EnforcementLevel }))}
                      className="mt-1"
                    />
                    <div>
                      <div className={`font-medium ${level.color}`}>{level.label}</div>
                      <div className="text-sm text-theme-secondary">{level.description}</div>
                    </div>
                  </label>
                ))}
              </div>
            </div>
          </div>
        </Card>

        {/* License Restrictions */}
        <Card className="p-6">
          <h2 className="text-lg font-semibold text-theme-primary mb-4">License Restrictions</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                id="block_copyleft"
                checked={formData.block_copyleft}
                onChange={(e) => setFormData(prev => ({ ...prev, block_copyleft: e.target.checked }))}
                className="rounded border-theme"
              />
              <label htmlFor="block_copyleft" className="text-sm text-theme-primary">
                Block all copyleft licenses
              </label>
            </div>

            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                id="block_strong_copyleft"
                checked={formData.block_strong_copyleft}
                onChange={(e) => setFormData(prev => ({ ...prev, block_strong_copyleft: e.target.checked }))}
                className="rounded border-theme"
              />
              <label htmlFor="block_strong_copyleft" className="text-sm text-theme-primary">
                Block strong copyleft (GPL, etc.)
              </label>
            </div>

            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                id="block_network_copyleft"
                checked={formData.block_network_copyleft}
                onChange={(e) => setFormData(prev => ({ ...prev, block_network_copyleft: e.target.checked }))}
                className="rounded border-theme"
              />
              <label htmlFor="block_network_copyleft" className="text-sm text-theme-primary">
                Block network copyleft (AGPL, etc.)
              </label>
            </div>

            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                id="block_unknown"
                checked={formData.block_unknown}
                onChange={(e) => setFormData(prev => ({ ...prev, block_unknown: e.target.checked }))}
                className="rounded border-theme"
              />
              <label htmlFor="block_unknown" className="text-sm text-theme-primary">
                Block unknown licenses
              </label>
            </div>

            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                id="require_osi_approved"
                checked={formData.require_osi_approved}
                onChange={(e) => setFormData(prev => ({ ...prev, require_osi_approved: e.target.checked }))}
                className="rounded border-theme"
              />
              <label htmlFor="require_osi_approved" className="text-sm text-theme-primary">
                Require OSI-approved licenses
              </label>
            </div>

            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                id="require_attribution"
                checked={formData.require_attribution}
                onChange={(e) => setFormData(prev => ({ ...prev, require_attribution: e.target.checked }))}
                className="rounded border-theme"
              />
              <label htmlFor="require_attribution" className="text-sm text-theme-primary">
                Require attribution notices
              </label>
            </div>
          </div>
        </Card>

        {/* Allowed Licenses */}
        {(formData.policy_type === 'allowlist' || formData.policy_type === 'hybrid') && (
          <Card className="p-6">
            <h2 className="text-lg font-semibold text-theme-primary mb-2">Allowed Licenses</h2>
            <p className="text-sm text-theme-secondary mb-4">
              {formData.policy_type === 'allowlist'
                ? 'Only these licenses will be permitted.'
                : 'These licenses are explicitly allowed in hybrid mode.'}
            </p>

            {errors.allowed_licenses && (
              <div className="flex items-center gap-2 text-theme-error mb-4">
                <AlertTriangle className="w-4 h-4" />
                <span className="text-sm">{errors.allowed_licenses}</span>
              </div>
            )}

            <div className="flex gap-2 mb-4">
              <input
                type="text"
                value={newAllowedLicense}
                onChange={(e) => setNewAllowedLicense(e.target.value)}
                className="flex-1 px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                placeholder="Enter SPDX license identifier (e.g., MIT, Apache-2.0)"
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    e.preventDefault();
                    handleAddLicense('allowed');
                  }
                }}
              />
              <Button type="button" variant="outline" onClick={() => handleAddLicense('allowed')}>
                <Plus className="w-4 h-4" />
              </Button>
            </div>

            <div className="mb-4">
              <p className="text-xs text-theme-tertiary mb-2">Quick add common licenses:</p>
              <div className="flex flex-wrap gap-1">
                {COMMON_LICENSES.filter(l => l.category === 'permissive').map((license) => (
                  <button
                    key={license.id}
                    type="button"
                    onClick={() => handleQuickAddLicense('allowed', license.id)}
                    disabled={formData.allowed_licenses.includes(license.id)}
                    className="px-2 py-1 text-xs rounded bg-theme-success/10 text-theme-success hover:bg-theme-success/20 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    {license.id}
                  </button>
                ))}
              </div>
            </div>

            {formData.allowed_licenses.length > 0 ? (
              <div className="flex flex-wrap gap-2">
                {formData.allowed_licenses.map((license) => (
                  <span
                    key={license}
                    className="inline-flex items-center gap-1 px-2 py-1 rounded bg-theme-success/10 text-theme-success text-sm"
                  >
                    {license}
                    <button
                      type="button"
                      onClick={() => handleRemoveLicense('allowed', license)}
                      className="hover:text-theme-error"
                    >
                      <X className="w-3 h-3" />
                    </button>
                  </span>
                ))}
              </div>
            ) : (
              <p className="text-sm text-theme-tertiary italic">No allowed licenses added yet.</p>
            )}
          </Card>
        )}

        {/* Denied Licenses */}
        {(formData.policy_type === 'denylist' || formData.policy_type === 'hybrid') && (
          <Card className="p-6">
            <h2 className="text-lg font-semibold text-theme-primary mb-2">Denied Licenses</h2>
            <p className="text-sm text-theme-secondary mb-4">
              These licenses will be explicitly blocked.
            </p>

            <div className="flex gap-2 mb-4">
              <input
                type="text"
                value={newDeniedLicense}
                onChange={(e) => setNewDeniedLicense(e.target.value)}
                className="flex-1 px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary"
                placeholder="Enter SPDX license identifier (e.g., GPL-3.0-only)"
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    e.preventDefault();
                    handleAddLicense('denied');
                  }
                }}
              />
              <Button type="button" variant="outline" onClick={() => handleAddLicense('denied')}>
                <Plus className="w-4 h-4" />
              </Button>
            </div>

            <div className="mb-4">
              <p className="text-xs text-theme-tertiary mb-2">Quick add copyleft licenses:</p>
              <div className="flex flex-wrap gap-1">
                {COMMON_LICENSES.filter(l => ['copyleft', 'network-copyleft'].includes(l.category)).map((license) => (
                  <button
                    key={license.id}
                    type="button"
                    onClick={() => handleQuickAddLicense('denied', license.id)}
                    disabled={formData.denied_licenses.includes(license.id)}
                    className="px-2 py-1 text-xs rounded bg-theme-error/10 text-theme-error hover:bg-theme-error/20 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    {license.id}
                  </button>
                ))}
              </div>
            </div>

            {formData.denied_licenses.length > 0 ? (
              <div className="flex flex-wrap gap-2">
                {formData.denied_licenses.map((license) => (
                  <span
                    key={license}
                    className="inline-flex items-center gap-1 px-2 py-1 rounded bg-theme-error/10 text-theme-error text-sm"
                  >
                    {license}
                    <button
                      type="button"
                      onClick={() => handleRemoveLicense('denied', license)}
                      className="hover:text-theme-primary"
                    >
                      <X className="w-3 h-3" />
                    </button>
                  </span>
                ))}
              </div>
            ) : (
              <p className="text-sm text-theme-tertiary italic">No denied licenses added yet.</p>
            )}
          </Card>
        )}

        {/* Info Box */}
        <div className="flex items-start gap-3 p-4 rounded-lg bg-theme-info/10 border border-theme-info/30">
          <Info className="w-5 h-5 text-theme-info flex-shrink-0 mt-0.5" />
          <div className="text-sm text-theme-secondary">
            <p className="font-medium text-theme-primary mb-1">About License Policies</p>
            <p>
              License policies are evaluated against SBOMs to detect compliance violations.
              Policies can be applied to specific repositories or used as default policies for your organization.
            </p>
          </div>
        </div>

        {/* Form Actions */}
        <div className="flex items-center justify-end gap-3 pt-4 border-t border-theme">
          <Button
            type="button"
            variant="outline"
            onClick={() => navigate('/app/supply-chain/licenses/policies')}
            disabled={isSubmitting}
          >
            Cancel
          </Button>
          <Button type="submit" variant="primary" loading={isSubmitting}>
            <Save className="w-4 h-4 mr-2" />
            {isEditing ? 'Update Policy' : 'Create Policy'}
          </Button>
        </div>
      </form>
    </PageContainer>
  );
};

export default LicensePolicyFormPage;
