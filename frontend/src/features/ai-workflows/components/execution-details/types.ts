import type { AiWorkflowRun, AiWorkflowNodeExecution, AiWorkflowNode } from '@/shared/types/workflow';

// Extended node execution with merged workflow node data
export interface MergedNodeExecution extends Omit<AiWorkflowNodeExecution, 'node'> {
  node?: AiWorkflowNode;
  isFromDefinition?: boolean;
  error_message?: string;
}

// Props for execution summary card
export interface ExecutionSummaryProps {
  run: AiWorkflowRun;
  currentRun: AiWorkflowRun;
  runStatus: string;
  formatDuration: (ms: number | undefined) => string;
}

// Props for node execution timeline
export interface NodeExecutionTimelineProps {
  mergedNodes: MergedNodeExecution[];
  expandedNodes: Set<string>;
  expandedInputs: Set<string>;
  expandedOutputs: Set<string>;
  expandedMetadata: Set<string>;
  liveNodeDurations: Record<string, number>;
  toggleNodeExpansion: (executionId: string) => void;
  toggleInputExpansion: (executionId: string) => void;
  toggleOutputExpansion: (executionId: string) => void;
  toggleMetadataExpansion: (executionId: string) => void;
  formatDuration: (ms: number | undefined) => string;
  renderStatusIcon: (status: string) => React.ReactNode;
  renderOutput: (output: unknown, status?: string) => React.ReactNode;
  renderCopyButton: (text: string, format?: string, showLabel?: boolean) => React.ReactNode;
  renderExpandableContent: (content: string, label?: string) => React.ReactNode;
}

// Props for node execution card
export interface NodeExecutionCardProps {
  node: MergedNodeExecution;
  index: number;
  isLast: boolean;
  isExpanded: boolean;
  isInputExpanded: boolean;
  isOutputExpanded: boolean;
  isMetadataExpanded: boolean;
  liveDuration?: number;
  onToggleExpansion: () => void;
  onToggleInput: () => void;
  onToggleOutput: () => void;
  onToggleMetadata: () => void;
  formatDuration: (ms: number | undefined) => string;
  renderStatusIcon: (status: string) => React.ReactNode;
  renderOutput: (output: unknown, status?: string) => React.ReactNode;
  renderCopyButton: (text: string, format?: string, showLabel?: boolean) => React.ReactNode;
  renderExpandableContent: (content: string, label?: string) => React.ReactNode;
}

// Props for download menu
export interface DownloadMenuProps {
  showMenu: boolean;
  onToggle: () => void;
  onDownload: (format: string) => void;
}

// Props for preview modal
export interface PreviewModalProps {
  isOpen: boolean;
  onClose: () => void;
  format: 'json' | 'markdown' | 'text';
  onFormatChange: (format: 'json' | 'markdown' | 'text') => void;
  nodeExecutions: AiWorkflowNodeExecution[];
  run: AiWorkflowRun;
}

// Props for delete confirmation modal
export interface DeleteConfirmationModalProps {
  isOpen: boolean;
  onClose: () => void;
  onConfirm: () => void;
  isDeleting: boolean;
  runId: string;
}
