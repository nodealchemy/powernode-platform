import React, { useState } from 'react';
import { X, FileSignature } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import ErrorAlert from '@/shared/components/ui/ErrorAlert';

type AttestationType = 'slsa_provenance' | 'sbom' | 'vulnerability_scan' | 'custom';

interface CreateAttestationModalProps {
  onClose: () => void;
  onCreate: (data: {
    attestation_type: AttestationType;
    subject_name: string;
    subject_digest: string;
    predicate: Record<string, unknown>;
  }) => Promise<void>;
}

const attestationTypes: { value: AttestationType; label: string; description: string }[] = [
  { value: 'slsa_provenance', label: 'SLSA Provenance', description: 'Build provenance attestation' },
  { value: 'sbom', label: 'SBOM', description: 'Software bill of materials attestation' },
  { value: 'vulnerability_scan', label: 'Vulnerability Scan', description: 'Security scan results' },
  { value: 'custom', label: 'Custom', description: 'Custom attestation type' },
];

export const CreateAttestationModal: React.FC<CreateAttestationModalProps> = ({
  onClose,
  onCreate,
}) => {
  const [attestationType, setAttestationType] = useState<AttestationType>('slsa_provenance');
  const [subjectName, setSubjectName] = useState('');
  const [subjectDigest, setSubjectDigest] = useState('');
  const [predicateJson, setPredicateJson] = useState('{}');
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleCreate = async () => {
    if (!subjectName.trim()) {
      setError('Subject name is required');
      return;
    }
    if (!subjectDigest.trim()) {
      setError('Subject digest is required');
      return;
    }

    let predicate: Record<string, unknown>;
    try {
      predicate = JSON.parse(predicateJson);
    } catch (_err) {
      setError('Invalid JSON in predicate');
      return;
    }

    try {
      setCreating(true);
      setError(null);
      await onCreate({
        attestation_type: attestationType,
        subject_name: subjectName.trim(),
        subject_digest: subjectDigest.trim(),
        predicate,
      });
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create attestation');
    } finally {
      setCreating(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div className="fixed inset-0 bg-black/50" onClick={onClose} />

      <div className="relative z-10 w-full max-w-lg max-h-[90vh] overflow-y-auto bg-theme-surface rounded-lg shadow-xl mx-4">
        <div className="sticky top-0 bg-theme-surface border-b border-theme px-6 py-4 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <FileSignature className="w-5 h-5 text-theme-interactive-primary" />
            <h2 className="text-lg font-semibold text-theme-primary">Create Attestation</h2>
          </div>
          <button onClick={onClose} className="p-1 rounded hover:bg-theme-surface-hover">
            <X className="w-5 h-5 text-theme-secondary" />
          </button>
        </div>

        <div className="p-6 space-y-6">
          {error && <ErrorAlert message={error} />}

          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-2">
              Attestation Type
            </label>
            <div className="grid grid-cols-2 gap-2">
              {attestationTypes.map((type) => (
                <button
                  key={type.value}
                  onClick={() => setAttestationType(type.value)}
                  className={`p-3 rounded-lg border text-left transition-colors ${
                    attestationType === type.value
                      ? 'border-theme-interactive-primary bg-theme-interactive-primary/10'
                      : 'border-theme hover:border-theme-border-hover'
                  }`}
                >
                  <p className="font-medium text-theme-primary text-sm">{type.label}</p>
                  <p className="text-xs text-theme-secondary mt-1">{type.description}</p>
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-2">
              Subject Name *
            </label>
            <input
              type="text"
              value={subjectName}
              onChange={(e) => setSubjectName(e.target.value)}
              placeholder="e.g., my-app:v1.0.0"
              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary placeholder-theme-muted focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-2">
              Subject Digest *
            </label>
            <input
              type="text"
              value={subjectDigest}
              onChange={(e) => setSubjectDigest(e.target.value)}
              placeholder="sha256:abc123..."
              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary placeholder-theme-muted focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary font-mono text-sm"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-2">
              Predicate (JSON)
            </label>
            <textarea
              value={predicateJson}
              onChange={(e) => setPredicateJson(e.target.value)}
              placeholder="{}"
              rows={5}
              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary placeholder-theme-muted focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary font-mono text-sm"
            />
            <p className="mt-1 text-xs text-theme-muted">
              Enter the predicate as valid JSON. This contains the attestation-specific data.
            </p>
          </div>
        </div>

        <div className="sticky bottom-0 bg-theme-surface border-t border-theme px-6 py-4 flex justify-end gap-3">
          <Button variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="primary" onClick={handleCreate} disabled={creating}>
            {creating ? 'Creating...' : 'Create Attestation'}
          </Button>
        </div>
      </div>
    </div>
  );
};
