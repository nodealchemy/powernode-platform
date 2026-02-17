import React, { useState } from 'react';
import type { ReviewState, EvidenceManifest } from '../types/codeFactory';

interface Props {
  reviewStates: ReviewState[];
}

const statusBadge: Record<string, string> = {
  pending: 'bg-theme-secondary-bg text-theme-secondary',
  captured: 'bg-theme-info-bg text-theme-info',
  verified: 'bg-theme-success-bg text-theme-success',
  failed: 'bg-theme-error-bg text-theme-error',
};

interface ManifestWithContext extends EvidenceManifest {
  pr_number: number;
  head_sha: string;
}

export const EvidenceViewer: React.FC<Props> = ({ reviewStates }) => {
  const [selectedManifest, setSelectedManifest] = useState<ManifestWithContext | null>(null);

  const allManifests: ManifestWithContext[] = reviewStates.flatMap((rs) =>
    (rs.evidence_manifests || []).map((m) => ({ ...m, pr_number: rs.pr_number, head_sha: rs.head_sha }))
  );

  if (allManifests.length === 0) {
    return (
      <div className="text-center py-12 text-theme-secondary text-sm">
        No evidence manifests captured yet.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Evidence Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {allManifests.map((manifest) => (
          <div
            key={manifest.id}
            className="card-theme p-4 cursor-pointer hover:ring-2 hover:ring-theme-accent/30 transition-all"
            onClick={() => setSelectedManifest(manifest)}
          >
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm font-medium text-theme-primary capitalize">
                {manifest.manifest_type.replace(/_/g, ' ')}
              </span>
              <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${statusBadge[manifest.status] || ''}`}>
                {manifest.status}
              </span>
            </div>
            <div className="text-xs text-theme-secondary space-y-1">
              <div>PR #{manifest.pr_number}</div>
              <div>{manifest.assertions.length} assertions</div>
              <div>{manifest.artifacts.length} artifacts</div>
              {manifest.captured_at && (
                <div>{new Date(manifest.captured_at).toLocaleString()}</div>
              )}
            </div>
            {manifest.assertions.length > 0 && (
              <div className="mt-2 flex gap-1">
                {manifest.assertions.map((a, idx) => (
                  <span
                    key={idx}
                    className={`w-2 h-2 rounded-full ${
                      a.passed === true ? 'bg-theme-success' : a.passed === false ? 'bg-theme-error' : 'bg-theme-secondary'
                    }`}
                    title={`${a.type}: ${a.passed === true ? 'passed' : a.passed === false ? 'failed' : 'pending'}`}
                  />
                ))}
              </div>
            )}
          </div>
        ))}
      </div>

      {/* Detail Panel */}
      {selectedManifest && (
        <div className="card-theme p-4 space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="text-sm font-semibold text-theme-primary capitalize">
              {selectedManifest.manifest_type.replace(/_/g, ' ')} Details
            </h3>
            <button
              onClick={() => setSelectedManifest(null)}
              className="text-xs text-theme-secondary hover:text-theme-primary"
            >
              Close
            </button>
          </div>

          {/* Assertions */}
          {selectedManifest.assertions.length > 0 && (
            <div>
              <h4 className="text-xs font-medium text-theme-secondary mb-2">Assertions</h4>
              <div className="space-y-1">
                {selectedManifest.assertions.map((assertion, idx) => (
                  <div key={idx} className="flex items-center gap-2 text-xs">
                    <span className={assertion.passed ? 'text-theme-success' : assertion.passed === false ? 'text-theme-error' : 'text-theme-secondary'}>
                      {assertion.passed ? '\u2713' : assertion.passed === false ? '\u2717' : '\u25CB'}
                    </span>
                    <span className="text-theme-primary">{assertion.type}</span>
                    <span className="text-theme-secondary font-mono">{assertion.selector}</span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Artifacts */}
          {selectedManifest.artifacts.length > 0 && (
            <div>
              <h4 className="text-xs font-medium text-theme-secondary mb-2">Artifacts</h4>
              <div className="space-y-1">
                {selectedManifest.artifacts.map((artifact, idx) => (
                  <div key={idx} className="flex items-center justify-between text-xs card-theme p-2">
                    <div className="flex items-center gap-2">
                      <span className="text-theme-primary capitalize">{artifact.type}</span>
                      <span className="text-theme-secondary font-mono">{artifact.sha256.substring(0, 12)}...</span>
                    </div>
                    <span className="text-theme-secondary">
                      {(artifact.size_bytes / 1024).toFixed(1)} KB
                    </span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Verification */}
          {Object.keys(selectedManifest.verification_result).length > 0 && (
            <div>
              <h4 className="text-xs font-medium text-theme-secondary mb-2">Verification Result</h4>
              <pre className="text-xs text-theme-secondary bg-theme-secondary-bg p-2 rounded overflow-x-auto">
                {JSON.stringify(selectedManifest.verification_result, null, 2)}
              </pre>
            </div>
          )}
        </div>
      )}
    </div>
  );
};
