import React, { memo } from 'react';
import { Handle, Position } from '@xyflow/react';
import type { NodeProps } from '@xyflow/react';
import { ShieldCheck } from 'lucide-react';

interface ApprovalGateNodeData {
  task_key: string;
  label: string;
  status: 'pending' | 'approved' | 'rejected';
}

const GATE_COLORS: Record<string, string> = {
  pending: 'bg-theme-warning/10 text-theme-warning border-theme-warning',
  approved: 'bg-theme-success/10 text-theme-success border-theme-success',
  rejected: 'bg-theme-error/10 text-theme-error border-theme-error',
};

const ApprovalGateNode: React.FC<NodeProps> = ({ data }) => {
  const nodeData = data as unknown as ApprovalGateNodeData;
  const colorClass = GATE_COLORS[nodeData.status] || GATE_COLORS.pending;

  return (
    <div className={`px-3 py-2 rounded-lg border-2 border-dashed min-w-[160px] text-center ${colorClass}`}>
      <Handle type="target" position={Position.Top} className="!bg-theme-border" />
      <ShieldCheck className="w-5 h-5 mx-auto mb-1" />
      <span className="text-xs font-medium">{nodeData.label || nodeData.task_key}</span>
      <Handle type="source" position={Position.Bottom} className="!bg-theme-border" />
    </div>
  );
};

export default memo(ApprovalGateNode);
