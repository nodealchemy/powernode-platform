import React from 'react';
import { DynamicNodeHandles } from '@/shared/components/workflow/nodes/DynamicNodeHandles';
import { NodeActionsMenu } from '@/shared/components/workflow/NodeActionsMenu';
import { useWorkflowContext } from '@/shared/components/workflow/WorkflowContext';
import { NodeStatusBadge } from '@/shared/components/workflow/ExecutionOverlay';
import { HandlePositions, NodeExecutionStatus, WorkflowNodeType } from '@/shared/types/workflow';

/**
 * Props for the BaseNode component
 * This component provides a consistent structure for all workflow nodes
 */
export interface BaseNodeProps {
  /** Unique node identifier */
  id: string;
  /** Node type for handle positioning and actions menu */
  nodeType: WorkflowNodeType;
  /** Whether this node is currently selected */
  selected?: boolean;
  /** Header background color class (e.g., 'bg-node-ai-agent') */
  headerColor: string;
  /** Icon component to display in header */
  headerIcon: React.ReactNode;
  /** Label text for the header (e.g., 'AI AGENT') */
  headerLabel: string;
  /** Node display name */
  name?: string;
  /** Node description */
  description?: string;
  /** Handle positions for edge connections */
  handlePositions?: HandlePositions;
  /** Whether this is an end node (no outgoing connections) */
  isEndNode?: boolean;
  /** Whether this is a start node (no incoming connections) */
  isStartNode?: boolean;
  /** Execution status for the node */
  executionStatus?: NodeExecutionStatus;
  /** Execution duration in milliseconds */
  executionDuration?: number;
  /** Execution error message if failed */
  executionError?: string;
  /** Whether to show the actions menu (default: true) */
  showActionsMenu?: boolean;
  /** Whether the node has validation errors */
  hasErrors?: boolean;
  /** Additional content to render in the body */
  children?: React.ReactNode;
  /** Additional CSS classes for the container */
  className?: string;
  /** Whether to use the 'group' class for hover interactions */
  useGroupHover?: boolean;
}

/**
 * BaseNode component providing consistent structure for all workflow nodes.
 *
 * This component handles:
 * - Container styling with selected/hover states
 * - Header with colored background, icon, and label
 * - Name and description display
 * - Execution status badge
 * - Node actions menu
 * - Dynamic edge handles
 *
 * @example
 * ```tsx
 * <BaseNode
 *   id={id}
 *   nodeType="ai_agent"
 *   selected={selected}
 *   headerColor="bg-node-ai-agent"
 *   headerIcon={<Bot className="h-4 w-4" />}
 *   headerLabel="AI AGENT"
 *   name={data.name}
 *   description={data.description}
 *   handlePositions={data.handlePositions}
 *   executionStatus={data.executionStatus}
 * >
 *   {/* Custom content for the node body *\/}
 *   <div className="text-xs">
 *     <span className="text-theme-muted">Model:</span>
 *     <span className="ml-1 text-theme-secondary">{model}</span>
 *   </div>
 * </BaseNode>
 * ```
 */
export const BaseNode: React.FC<BaseNodeProps> = ({
  id,
  nodeType,
  selected = false,
  headerColor,
  headerIcon,
  headerLabel,
  name,
  description,
  handlePositions,
  isEndNode = false,
  isStartNode = false,
  executionStatus,
  executionDuration,
  executionError,
  showActionsMenu = true,
  hasErrors = false,
  children,
  className = '',
  useGroupHover = true,
}) => {
  const { onOpenChat } = useWorkflowContext();

  return (
    <div
      className={`
        ${useGroupHover ? 'group' : ''} relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
        ${selected
          ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20'
          : 'border-theme hover:border-theme-interactive-primary/50'
        }
        hover:shadow-xl transition-all duration-200
        ${className}
      `}
    >
      {/* Header */}
      <div className={`px-4 py-3 rounded-t-lg ${headerColor}`}>
        <div className="flex items-center gap-2 text-white">
          {headerIcon}
          <span className="font-medium text-sm">{headerLabel}</span>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        {/* Name & Description */}
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {name || headerLabel}
          </h3>
          {description && (
            <p className="text-xs text-theme-secondary mt-1 line-clamp-2">
              {description}
            </p>
          )}
        </div>

        {/* Custom content */}
        {children}
      </div>

      {/* End Node Indicator */}
      {isEndNode && (
        <div className="absolute -bottom-1 left-1/2 -translate-x-1/2 w-3 h-3 rounded-full bg-theme-danger" />
      )}

      {/* Execution Status Badge */}
      {executionStatus && (
        <NodeStatusBadge
          status={executionStatus}
          duration={executionDuration}
          error={executionError}
        />
      )}

      {/* Node Actions Menu */}
      {showActionsMenu && (
        <NodeActionsMenu
          nodeId={id}
          nodeType={nodeType}
          nodeName={name}
          isSelected={selected}
          hasErrors={hasErrors}
          onOpenChat={onOpenChat}
        />
      )}

      {/* Auto-positioning Handles */}
      <DynamicNodeHandles
        nodeType={nodeType}
        isEndNode={isEndNode}
        isStartNode={isStartNode}
        handlePositions={handlePositions}
      />
    </div>
  );
};

/**
 * Helper component for displaying key-value info rows in node bodies
 */
export const NodeInfoRow: React.FC<{
  label: string;
  value?: string | number | null;
  valueClassName?: string;
  mono?: boolean;
}> = ({ label, value, valueClassName = '', mono = false }) => {
  if (!value) return null;

  return (
    <div className="text-xs">
      <span className="text-theme-muted">{label}:</span>
      <span className={`ml-1 text-theme-secondary ${mono ? 'font-mono' : ''} ${valueClassName}`}>
        {value}
      </span>
    </div>
  );
};

/**
 * Helper component for displaying badges/tags in node bodies
 */
export const NodeBadge: React.FC<{
  children: React.ReactNode;
  variant?: 'default' | 'success' | 'warning' | 'danger' | 'info';
  className?: string;
}> = ({ children, variant = 'default', className = '' }) => {
  const variantClasses = {
    default: 'text-theme-interactive-primary bg-theme-interactive-primary/20',
    success: 'text-theme-success bg-theme-success/20',
    warning: 'text-theme-warning bg-theme-warning/20',
    danger: 'text-theme-danger bg-theme-danger/20',
    info: 'text-theme-info bg-theme-info/20',
  };

  return (
    <span
      className={`
        inline-block text-xs font-medium px-2 py-0.5 rounded-full
        ${variantClasses[variant]}
        ${className}
      `}
    >
      {children}
    </span>
  );
};

export default BaseNode;
