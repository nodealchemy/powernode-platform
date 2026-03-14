import React from 'react';
import { CheckCircle, XCircle, AlertCircle } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';

interface ComplianceStatusCardProps {
  compliance: {
    ntia_minimum_compliant: boolean;
    ntia_fields: Record<string, boolean>;
    completeness_score: number;
    missing_fields: string[];
  };
}

const fieldLabels: Record<string, string> = {
  supplier_name: 'Supplier Name',
  component_name: 'Component Name',
  component_version: 'Component Version',
  unique_identifier: 'Unique Identifier',
  dependency_relationship: 'Dependency Relationship',
  author: 'Author',
  timestamp: 'Timestamp',
};

export const ComplianceStatusCard: React.FC<ComplianceStatusCardProps> = ({ compliance }) => {
  const scoreColor =
    compliance.completeness_score >= 80 ? 'text-theme-success' :
    compliance.completeness_score >= 60 ? 'text-theme-warning' :
    'text-theme-error';

  return (
    <div className="space-y-6">
      <Card className="p-6">
        <div className="flex items-center justify-between mb-6">
          <h3 className="text-lg font-semibold text-theme-primary">NTIA Minimum Elements</h3>
          <Badge
            variant={compliance.ntia_minimum_compliant ? 'success' : 'danger'}
            size="lg"
          >
            {compliance.ntia_minimum_compliant ? 'Compliant' : 'Non-Compliant'}
          </Badge>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {Object.entries(compliance.ntia_fields).map(([field, present]) => (
            <div
              key={field}
              className={`flex items-center gap-3 p-3 rounded-lg ${
                present ? 'bg-theme-success/10' : 'bg-theme-error/10'
              }`}
            >
              {present ? (
                <CheckCircle className="w-5 h-5 text-theme-success flex-shrink-0" />
              ) : (
                <XCircle className="w-5 h-5 text-theme-error flex-shrink-0" />
              )}
              <span className={`text-sm ${present ? 'text-theme-success' : 'text-theme-error'}`}>
                {fieldLabels[field] || field}
              </span>
            </div>
          ))}
        </div>
      </Card>

      <Card className="p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-theme-primary">Completeness Score</h3>
          <span className={`text-3xl font-bold ${scoreColor}`}>
            {compliance.completeness_score}%
          </span>
        </div>

        <div className="w-full bg-theme-muted rounded-full h-3 mb-4">
          <div
            className={`h-3 rounded-full transition-all ${
              compliance.completeness_score >= 80 ? 'bg-theme-success' :
              compliance.completeness_score >= 60 ? 'bg-theme-warning' :
              'bg-theme-error'
            }`}
            style={{ width: `${compliance.completeness_score}%` }}
          />
        </div>

        {compliance.missing_fields.length > 0 && (
          <div className="mt-4">
            <div className="flex items-center gap-2 mb-2">
              <AlertCircle className="w-4 h-4 text-theme-warning" />
              <span className="text-sm font-medium text-theme-secondary">Missing Fields</span>
            </div>
            <div className="flex flex-wrap gap-2">
              {compliance.missing_fields.map((field) => (
                <Badge key={field} variant="warning" size="sm">
                  {fieldLabels[field] || field}
                </Badge>
              ))}
            </div>
          </div>
        )}
      </Card>
    </div>
  );
};
