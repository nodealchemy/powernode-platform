import React, { useState } from 'react';
import { Download, ChevronDown } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';

type ExportFormat = 'json' | 'xml' | 'pdf' | 'cyclonedx' | 'spdx';

interface ExportFormatDropdownProps {
  onExport: (format: ExportFormat) => Promise<void>;
  disabled?: boolean;
}

const formatLabels: Record<ExportFormat, { label: string; description: string }> = {
  json: { label: 'JSON', description: 'Standard JSON format' },
  xml: { label: 'XML', description: 'Standard XML format' },
  pdf: { label: 'PDF', description: 'Human-readable report' },
  cyclonedx: { label: 'CycloneDX', description: 'CycloneDX 1.4 format' },
  spdx: { label: 'SPDX', description: 'SPDX 2.3 format' },
};

export const ExportFormatDropdown: React.FC<ExportFormatDropdownProps> = ({
  onExport,
  disabled = false,
}) => {
  const [isOpen, setIsOpen] = useState(false);
  const [exporting, setExporting] = useState(false);

  const handleExport = async (format: ExportFormat) => {
    try {
      setExporting(true);
      setIsOpen(false);
      await onExport(format);
    } finally {
      setExporting(false);
    }
  };

  return (
    <div className="relative">
      <Button
        variant="secondary"
        onClick={() => setIsOpen(!isOpen)}
        disabled={disabled || exporting}
        className="flex items-center gap-2"
      >
        <Download className="w-4 h-4" />
        {exporting ? 'Exporting...' : 'Export'}
        <ChevronDown className={`w-4 h-4 transition-transform ${isOpen ? 'rotate-180' : ''}`} />
      </Button>

      {isOpen && (
        <>
          <div className="fixed inset-0 z-10" onClick={() => setIsOpen(false)} />
          <div className="absolute right-0 top-full mt-1 z-20 w-56 bg-theme-surface border border-theme rounded-lg shadow-lg py-1">
            {(Object.entries(formatLabels) as [ExportFormat, { label: string; description: string }][]).map(
              ([format, { label, description }]) => (
                <button
                  key={format}
                  onClick={() => handleExport(format)}
                  className="w-full px-4 py-2 text-left hover:bg-theme-surface-hover"
                >
                  <p className="font-medium text-theme-primary">{label}</p>
                  <p className="text-xs text-theme-secondary">{description}</p>
                </button>
              )
            )}
          </div>
        </>
      )}
    </div>
  );
};
