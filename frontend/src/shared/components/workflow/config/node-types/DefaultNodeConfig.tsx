import React from 'react';
import { Settings } from 'lucide-react';
import type { NodeTypeConfigProps } from '@/shared/components/workflow/config/node-types/types';

export const DefaultNodeConfig: React.FC<NodeTypeConfigProps> = ({
  handlePositionsConfig
}) => {
  return (
    <div>
      {handlePositionsConfig}
      <div className="text-center py-8 text-theme-muted">
        <Settings className="h-8 w-8 mx-auto mb-2 opacity-50" />
        <p>No specific configuration available for this node type.</p>
        <p className="text-xs mt-2">Connection orientation can be configured above.</p>
      </div>
    </div>
  );
};
