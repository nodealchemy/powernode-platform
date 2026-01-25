import React, { useState, useEffect, useCallback, useRef } from 'react';
import { Workflow, Maximize2, X } from 'lucide-react';
import { Node, Edge } from '@xyflow/react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { WorkflowBuilderProvider } from './WorkflowBuilder';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { workflowsApi } from '@/shared/services/ai';
import { AiWorkflow } from '@/shared/types/workflow';

export interface WorkflowBuilderModalProps {
  isOpen: boolean;
  onClose: () => void;
  workflowId: string;
  onSuccess?: (workflow: AiWorkflow) => void;
}

export const WorkflowBuilderModal: React.FC<WorkflowBuilderModalProps> = ({
  isOpen,
  onClose,
  workflowId,
  onSuccess
}) => {
  const { currentUser } = useAuth();
  const { addNotification } = useNotifications();
  
  const [workflow, setWorkflow] = useState<AiWorkflow | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [hasChanges, setHasChanges] = useState(false);
  // Load grid preference from localStorage, default to true if not set
  const [showGrid, setShowGrid] = useState(() => {
    const savedPreference = localStorage.getItem('workflowGridEnabled');
    return savedPreference !== null ? savedPreference === 'true' : true;
  });

  // Load snap-to-grid preference from localStorage
  const [snapToGrid, setSnapToGrid] = useState(() => {
    const savedPreference = localStorage.getItem('workflowSnapToGridEnabled');
    return savedPreference !== null ? savedPreference === 'true' : false;
  });

  // Load layout orientation preference from localStorage
  const [layoutOrientation, setLayoutOrientation] = useState<'horizontal' | 'vertical'>(() => {
    const savedPreference = localStorage.getItem('workflowLayoutOrientation');
    return (savedPreference === 'horizontal' || savedPreference === 'vertical') ? savedPreference : 'vertical';
  });

  const [isPreviewMode, setIsPreviewMode] = useState(false);

  // Handle grid toggle with localStorage persistence
  const handleGridToggle = useCallback((enabled: boolean) => {
    setShowGrid(enabled);
    localStorage.setItem('workflowGridEnabled', enabled.toString());
  }, []);

  // Handle snap-to-grid toggle with localStorage persistence
  const handleSnapToGridToggle = useCallback((enabled: boolean) => {
    setSnapToGrid(enabled);
    localStorage.setItem('workflowSnapToGridEnabled', enabled.toString());
  }, []);

  // Handle layout orientation change with localStorage persistence
  const handleLayoutOrientationChange = useCallback((orientation: 'horizontal' | 'vertical') => {
    setLayoutOrientation(orientation);
    localStorage.setItem('workflowLayoutOrientation', orientation);
  }, []);

  // Confirmation dialog
  const { confirm, ConfirmationDialog } = useConfirmation();

  // Check permissions
  const canUpdateWorkflows = currentUser?.permissions?.includes('ai.workflows.update');

  // Load workflow data
  useEffect(() => {
    if (isOpen && workflowId) {
      loadWorkflow();
    }
  }, [isOpen, workflowId]);

  const loadWorkflow = async () => {
    try {
      setLoading(true);
      const response = await workflowsApi.getWorkflow(workflowId);
      setWorkflow(response);
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load workflow data'
      });
      onClose();
    } finally {
      setLoading(false);
    }
  };


  // Track last save timestamp to prevent duplicate notifications
  const lastSaveRef = useRef<number>(0);
  const [saveCount, setSaveCount] = useState(0);

  // Handle save from toolbar (combines data update + API save)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const handleToolbarSave = async (workflowData: { nodes: any[]; edges: any[]; configuration: Record<string, any> }) => {
    if (!workflow) return;

    try {
      setSaving(true);
      const saveStartTime = Date.now();

      const response = await workflowsApi.updateWorkflow(workflowId, {
        nodes: workflowData.nodes,
        edges: workflowData.edges,
        configuration: workflowData.configuration
      });

      // Update local state with the saved data to ensure UI reflects saved state
      setWorkflow(response);
      setHasChanges(false);
      setSaveCount(prev => prev + 1);
      lastSaveRef.current = saveStartTime;

      // Show single success notification with debouncing to prevent duplicates
      setTimeout(() => {
        // Only show notification if this was the most recent save
        if (lastSaveRef.current === saveStartTime) {
          addNotification({
            type: 'success',
            title: 'Workflow Saved',
            message: `"${workflow.name}" design saved successfully`
          });
        }
      }, 100); // Small delay to prevent duplicate WebSocket notifications

      // Notify parent component of successful save without closing the modal
      onSuccess?.(response);

    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Save Failed',
        message: 'Failed to save workflow design. Please try again.'
      });
    } finally {
      setSaving(false);
    }
  };


  // Handle workflow validation
  const handleValidation = useCallback(async (nodes: Node[], _edges: Edge[]) => {
    try {
      // Use the consolidated API for validation
      if (workflowId) {
        const result = await workflowsApi.validateWorkflow(workflowId);
        type ValidationItem = string | { message: string };
        return {
          valid: result.valid,
          errors: (result.errors || []).map((e: ValidationItem) => typeof e === 'string' ? e : e.message),
          warnings: (result.warnings || []).map((w: ValidationItem) => typeof w === 'string' ? w : w.message)
        };
      }

      // Basic client-side validation if no workflow ID
      const errors: string[] = [];
      const warnings: string[] = [];

      if (nodes.length === 0) {
        errors.push('Workflow must have at least one node');
      }

      const startNodes = nodes.filter(n => n.data?.isStartNode);
      if (startNodes.length === 0) {
        errors.push('Workflow must have at least one start node');
      }

      const endNodes = nodes.filter(n => n.data?.isEndNode);
      if (endNodes.length === 0) {
        warnings.push('Workflow should have at least one end node');
      }

      return {
        valid: errors.length === 0,
        errors,
        warnings
      };
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Validation Error',
        message: 'An error occurred while validating the workflow'
      });
      return {
        valid: false,
        errors: ['An error occurred during validation'],
        warnings: []
      };
    }
  }, [workflowId, addNotification]);

  // Handle close with unsaved changes warning
  const handleClose = () => {
    if (hasChanges) {
      confirm({
        title: 'Unsaved Changes',
        message: 'You have unsaved changes. Are you sure you want to close without saving?',
        confirmLabel: 'Close Without Saving',
        variant: 'warning',
        onConfirm: async () => {
          onClose();
        }
      });
      return;
    }
    onClose();
  };

  // Footer with cancel button and save guidance
  const footer = (
    <div className="flex items-center justify-between w-full">
      <div className="flex items-center gap-2">
        <Maximize2 className="h-4 w-4 text-theme-muted" />
        <span className="text-sm text-theme-muted">Fullscreen Workflow Designer</span>
      </div>
      <div className="flex items-center gap-3">
        {hasChanges && (
          <div className="flex items-center gap-2 text-theme-warning text-sm">
            <div className="w-2 h-2 bg-theme-warning-solid rounded-full animate-pulse" />
            <span>Unsaved changes - Use toolbar Save (Ctrl+S)</span>
          </div>
        )}
        {saving && (
          <div className="flex items-center gap-2 text-theme-info text-sm">
            <div className="w-4 h-4 border-2 border-theme-info border-t-transparent rounded-full animate-spin" />
            <span>Saving workflow...</span>
          </div>
        )}
        {!hasChanges && !saving && saveCount > 0 && (
          <div className="flex items-center gap-2 text-theme-success text-sm">
            <div className="w-2 h-2 bg-theme-success-solid rounded-full" />
            <span>All changes saved</span>
          </div>
        )}
        <Button variant="outline" onClick={handleClose}>
          {hasChanges ? 'Close Without Saving' : 'Close'}
        </Button>
      </div>
    </div>
  );

  // Loading state
  if (loading) {
    return (
      <Modal
        isOpen={isOpen}
        onClose={onClose}
        title="Loading Workflow Designer..."
        maxWidth="md"
        icon={<Workflow />}
      >
        <div className="flex items-center justify-center py-8">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-primary"></div>
        </div>
      </Modal>
    );
  }

  // Access denied
  if (!canUpdateWorkflows) {
    return (
      <Modal
        isOpen={isOpen}
        onClose={onClose}
        title="Access Denied"
        maxWidth="md"
        icon={<X />}
        footer={
          <Button variant="outline" onClick={onClose}>
            Close
          </Button>
        }
      >
        <div className="text-center py-8">
          <p className="text-theme-muted">
            You don't have permission to design workflows.
          </p>
        </div>
      </Modal>
    );
  }

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title={`Design: ${workflow?.name || 'Workflow'}`}
      subtitle="Visual workflow designer with drag-and-drop interface"
      variant="fullscreen"
      icon={<Workflow />}
      footer={footer}
      closeOnBackdrop={false}
      closeOnEscape={false}
    >
      <div className="h-full flex flex-col">
        <div className="flex-1 min-h-0">
          <WorkflowBuilderProvider
            workflow={workflow || undefined}
            onSave={handleToolbarSave}
            onValidate={handleValidation}
            showGrid={showGrid}
            onGridToggle={handleGridToggle}
            snapToGrid={snapToGrid}
            onSnapToGridToggle={handleSnapToGridToggle}
            layoutOrientation={layoutOrientation}
            onLayoutOrientationChange={handleLayoutOrientationChange}
            isPreviewMode={isPreviewMode}
            onPreviewModeToggle={setIsPreviewMode}
            isSaving={saving}
            className="h-full w-full"
          />
        </div>
        {ConfirmationDialog}
      </div>
    </Modal>
  );
};