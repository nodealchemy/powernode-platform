import React from 'react';
import { Plus, Minus, RefreshCw, AlertTriangle, Package } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';

type Severity = 'critical' | 'high' | 'medium' | 'low';

interface SbomDiffDetail {
  id: string;
  source_sbom_id: string;
  compare_sbom_id: string;
  added_count: number;
  removed_count: number;
  changed_count: number;
  created_at: string;
  added_components: Array<{ name: string; version: string; ecosystem: string }>;
  removed_components: Array<{ name: string; version: string; ecosystem: string }>;
  changed_components: Array<{
    name: string;
    old_version: string;
    new_version: string;
    ecosystem: string;
  }>;
  added_vulnerabilities: Array<{ vulnerability_id: string; severity: Severity }>;
  removed_vulnerabilities: Array<{ vulnerability_id: string; severity: Severity }>;
}

interface SbomDiffViewerProps {
  diff: SbomDiffDetail;
}

const severityStyles: Record<Severity, string> = {
  critical: 'bg-theme-error text-white',
  high: 'bg-theme-error/80 text-white',
  medium: 'bg-theme-warning text-theme-on-warning',
  low: 'bg-theme-info text-white',
};

export const SbomDiffViewer: React.FC<SbomDiffViewerProps> = ({ diff }) => {
  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card className="p-4">
          <div className="flex items-center gap-2 text-theme-success mb-2">
            <Plus className="w-5 h-5" />
            <span className="font-medium">Added</span>
          </div>
          <p className="text-3xl font-bold text-theme-success">{diff.added_count}</p>
          <p className="text-sm text-theme-secondary">components</p>
        </Card>

        <Card className="p-4">
          <div className="flex items-center gap-2 text-theme-error mb-2">
            <Minus className="w-5 h-5" />
            <span className="font-medium">Removed</span>
          </div>
          <p className="text-3xl font-bold text-theme-error">{diff.removed_count}</p>
          <p className="text-sm text-theme-secondary">components</p>
        </Card>

        <Card className="p-4">
          <div className="flex items-center gap-2 text-theme-warning mb-2">
            <RefreshCw className="w-5 h-5" />
            <span className="font-medium">Changed</span>
          </div>
          <p className="text-3xl font-bold text-theme-warning">{diff.changed_count}</p>
          <p className="text-sm text-theme-secondary">components</p>
        </Card>
      </div>

      {diff.added_components.length > 0 && (
        <Card className="p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
            <Plus className="w-5 h-5 text-theme-success" />
            Added Components ({diff.added_components.length})
          </h3>
          <div className="space-y-2">
            {diff.added_components.map((component, index) => (
              <div
                key={index}
                className="flex items-center justify-between p-3 bg-theme-success/10 rounded-lg"
              >
                <div className="flex items-center gap-3">
                  <Package className="w-4 h-4 text-theme-success" />
                  <span className="font-medium text-theme-primary">{component.name}</span>
                  <span className="text-theme-secondary">@{component.version}</span>
                </div>
                <Badge variant="outline" size="sm">{component.ecosystem}</Badge>
              </div>
            ))}
          </div>
        </Card>
      )}

      {diff.removed_components.length > 0 && (
        <Card className="p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
            <Minus className="w-5 h-5 text-theme-error" />
            Removed Components ({diff.removed_components.length})
          </h3>
          <div className="space-y-2">
            {diff.removed_components.map((component, index) => (
              <div
                key={index}
                className="flex items-center justify-between p-3 bg-theme-error/10 rounded-lg"
              >
                <div className="flex items-center gap-3">
                  <Package className="w-4 h-4 text-theme-error" />
                  <span className="font-medium text-theme-primary line-through">{component.name}</span>
                  <span className="text-theme-secondary line-through">@{component.version}</span>
                </div>
                <Badge variant="outline" size="sm">{component.ecosystem}</Badge>
              </div>
            ))}
          </div>
        </Card>
      )}

      {diff.changed_components.length > 0 && (
        <Card className="p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
            <RefreshCw className="w-5 h-5 text-theme-warning" />
            Changed Components ({diff.changed_components.length})
          </h3>
          <div className="space-y-2">
            {diff.changed_components.map((component, index) => (
              <div
                key={index}
                className="flex items-center justify-between p-3 bg-theme-warning/10 rounded-lg"
              >
                <div className="flex items-center gap-3">
                  <Package className="w-4 h-4 text-theme-warning" />
                  <span className="font-medium text-theme-primary">{component.name}</span>
                  <span className="text-theme-error line-through">@{component.old_version}</span>
                  <span className="text-theme-secondary">→</span>
                  <span className="text-theme-success">@{component.new_version}</span>
                </div>
                <Badge variant="outline" size="sm">{component.ecosystem}</Badge>
              </div>
            ))}
          </div>
        </Card>
      )}

      {(diff.added_vulnerabilities.length > 0 || diff.removed_vulnerabilities.length > 0) && (
        <Card className="p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
            <AlertTriangle className="w-5 h-5 text-theme-error" />
            Vulnerability Changes
          </h3>

          {diff.added_vulnerabilities.length > 0 && (
            <div className="mb-4">
              <h4 className="text-sm font-medium text-theme-error mb-2">
                New Vulnerabilities ({diff.added_vulnerabilities.length})
              </h4>
              <div className="flex flex-wrap gap-2">
                {diff.added_vulnerabilities.map((vuln, index) => (
                  <div
                    key={index}
                    className="flex items-center gap-2 p-2 bg-theme-error/10 rounded"
                  >
                    <Badge className={severityStyles[vuln.severity]} size="xs">
                      {vuln.severity}
                    </Badge>
                    <span className="text-sm text-theme-primary">{vuln.vulnerability_id}</span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {diff.removed_vulnerabilities.length > 0 && (
            <div>
              <h4 className="text-sm font-medium text-theme-success mb-2">
                Resolved Vulnerabilities ({diff.removed_vulnerabilities.length})
              </h4>
              <div className="flex flex-wrap gap-2">
                {diff.removed_vulnerabilities.map((vuln, index) => (
                  <div
                    key={index}
                    className="flex items-center gap-2 p-2 bg-theme-success/10 rounded"
                  >
                    <Badge variant="secondary" size="xs">
                      {vuln.severity}
                    </Badge>
                    <span className="text-sm text-theme-primary line-through">{vuln.vulnerability_id}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </Card>
      )}
    </div>
  );
};
