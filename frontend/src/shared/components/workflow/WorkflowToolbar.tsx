import React, { useState, useEffect, useRef } from 'react';
import {
  Save,
  CheckCircle,
  AlertTriangle,
  RefreshCw,
  Undo,
  Redo,
  ZoomIn,
  ZoomOut,
  Maximize,
  Grid,
  Eye,
  X,
  Layout,
  RotateCcw,
  Move,
  ArrowRight,
  ArrowDown,
  ChevronDown
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { useReactFlow } from '@xyflow/react';

export interface WorkflowToolbarProps {
  onSave: () => void;
  onValidate: () => Promise<{
    valid: boolean;
    errors: string[];
    warnings: string[];
  }>;
  validationResult?: {
    valid: boolean;
    errors: string[];
    warnings: string[];
  } | null;
  hasChanges: boolean;
  isValidating?: boolean;
  isSaving?: boolean;
  onUndo?: () => void;
  onRedo?: () => void;
  canUndo?: boolean;
  canRedo?: boolean;
  showGrid?: boolean;
  onGridToggle?: (showGrid: boolean) => void;
  snapToGrid?: boolean;
  onSnapToGridToggle?: (snapToGrid: boolean) => void;
  isPreviewMode?: boolean;
  onPreviewModeToggle?: (isPreviewMode: boolean) => void;
  onArrange?: (orientation?: 'horizontal' | 'vertical') => void;
  isArranging?: boolean;
  onReset?: () => void;
  layoutOrientation?: 'horizontal' | 'vertical';
  onLayoutOrientationChange?: (orientation: 'horizontal' | 'vertical') => void;
  className?: string;
}

export const WorkflowToolbar: React.FC<WorkflowToolbarProps> = ({
  onSave,
  onValidate,
  validationResult,
  hasChanges,
  isValidating = false,
  isSaving = false,
  onUndo,
  onRedo,
  canUndo = false,
  canRedo = false,
  showGrid = true,
  onGridToggle,
  snapToGrid = false,
  onSnapToGridToggle,
  isPreviewMode = false,
  onPreviewModeToggle,
  onArrange,
  isArranging = false,
  onReset,
  className = ''
}) => {
  const [isValidatingLocal, setIsValidatingLocal] = useState(false);
  const [showValidationDetails, setShowValidationDetails] = useState(false);
  const [showArrangeDropdown, setShowArrangeDropdown] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);
  
  const { zoomIn, zoomOut, fitView } = useReactFlow();

  const handleValidate = async () => {
    setIsValidatingLocal(true);
    // Toggle validation details visibility when Validate button is pressed
    setShowValidationDetails(!showValidationDetails);
    try {
      await onValidate();
    } finally {
      setIsValidatingLocal(false);
    }
  };

  const handleArrangeClick = (orientation: 'horizontal' | 'vertical') => {
    setShowArrangeDropdown(false);
    onArrange?.(orientation);
  };

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setShowArrangeDropdown(false);
      }
    };

    if (showArrangeDropdown) {
      document.addEventListener('mousedown', handleClickOutside);
      return () => document.removeEventListener('mousedown', handleClickOutside);
    }
  }, [showArrangeDropdown]);

  const getValidationStatus = () => {
    if (!validationResult) return null;
    
    if (validationResult.valid) {
      return {
        icon: <CheckCircle className="h-4 w-4" />,
        text: validationResult.warnings.length > 0 ? 
          `Valid (${validationResult.warnings.length} warning${validationResult.warnings.length !== 1 ? 's' : ''})` : 
          'Valid',
        color: 'text-theme-success',
        bgColor: 'bg-theme-success/10 border-theme-success/20'
      };
    } else {
      return {
        icon: <AlertTriangle className="h-4 w-4" />,
        text: `${validationResult.errors.length} Error${validationResult.errors.length !== 1 ? 's' : ''}`,
        color: 'text-theme-error',
        bgColor: 'bg-theme-error/10 border-theme-error/20'
      };
    }
  };

  const validationStatus = getValidationStatus();

  return (
    <div className={`bg-theme-surface border border-theme rounded-lg shadow-lg ${className}`}>
      <div className="flex items-center gap-2 p-3">
        {/* Save Section - Hidden in preview mode */}
        {!isPreviewMode && (
          <div className="flex items-center gap-2 border-r border-theme pr-3">
            <Button
              onClick={onSave}
              disabled={!hasChanges || isSaving}
              size="sm"
              className={hasChanges ? 'bg-theme-interactive-primary' : ''}
            >
              {isSaving ? (
                <RefreshCw className="h-4 w-4 mr-2 animate-spin" />
              ) : (
                <Save className="h-4 w-4 mr-2" />
              )}
              {isSaving ? 'Saving...' : 'Save'}
            </Button>

            {hasChanges && (
              <div className="flex items-center gap-1 text-theme-warning text-xs">
                <div className="w-2 h-2 bg-theme-warning rounded-full animate-pulse" />
                Unsaved
              </div>
            )}
          </div>
        )}

        {/* Validation Section - Hidden in preview mode */}
        {!isPreviewMode && (
          <div className="flex items-center gap-2 border-r border-theme pr-3">
            <Button
              onClick={handleValidate}
              disabled={isValidating || isValidatingLocal}
              size="sm"
              variant="outline"
            >
              {(isValidating || isValidatingLocal) ? (
                <RefreshCw className="h-4 w-4 mr-2 animate-spin" />
              ) : (
                <CheckCircle className="h-4 w-4 mr-2" />
              )}
              Validate
            </Button>

            {onReset && (
              <Button
                onClick={onReset}
                disabled={!hasChanges}
                size="sm"
                variant="outline"
                title="Reset to last saved state"
              >
                <RotateCcw className="h-4 w-4 mr-2" />
                Reset
              </Button>
            )}

            {validationStatus && (
              <div className={`
                flex items-center gap-2 px-2 py-1 rounded-md border text-xs
                ${validationStatus.color} ${validationStatus.bgColor}
              `}>
                {validationStatus.icon}
                {validationStatus.text}
              </div>
            )}
          </div>
        )}

        {/* History Section - Hidden in preview mode */}
        {!isPreviewMode && (onUndo || onRedo) && (
          <div className="flex items-center gap-1 border-r border-theme pr-3">
            <Button
              onClick={onUndo}
              disabled={!canUndo}
              size="sm"
              variant="outline"
              title="Undo (Ctrl+Z)"
            >
              <Undo className="h-4 w-4" />
            </Button>
            <Button
              onClick={onRedo}
              disabled={!canRedo}
              size="sm"
              variant="outline"
              title="Redo (Ctrl+Y)"
            >
              <Redo className="h-4 w-4" />
            </Button>
          </div>
        )}

        {/* View Controls */}
        <div className="flex items-center gap-1 border-r border-theme pr-3">
          <Button
            onClick={() => zoomIn()}
            size="sm"
            variant="outline"
            title="Zoom In"
          >
            <ZoomIn className="h-4 w-4" />
          </Button>
          <Button
            onClick={() => zoomOut()}
            size="sm"
            variant="outline"
            title="Zoom Out"
          >
            <ZoomOut className="h-4 w-4" />
          </Button>
          <Button
            onClick={() => fitView()}
            size="sm"
            variant="outline"
            title="Fit to View"
          >
            <Maximize className="h-4 w-4" />
          </Button>
          {!isPreviewMode && onArrange && (
            <div className="relative" ref={dropdownRef}>
              <Button
                onClick={() => setShowArrangeDropdown(!showArrangeDropdown)}
                disabled={isArranging}
                size="sm"
                variant="outline"
                title="Auto-arrange nodes"
                className="flex items-center gap-1"
              >
                {isArranging ? (
                  <RefreshCw className="h-4 w-4 animate-spin" />
                ) : (
                  <Layout className="h-4 w-4" />
                )}
                <ChevronDown className="h-3 w-3" />
              </Button>

              {showArrangeDropdown && (
                <div className="absolute top-full left-0 mt-1 bg-theme-surface border border-theme rounded-md shadow-lg z-50 min-w-[140px]">
                  <button
                    onClick={() => handleArrangeClick('vertical')}
                    className="w-full flex items-center gap-2 px-3 py-2 text-sm text-theme-primary hover:bg-theme-secondary transition-colors"
                  >
                    <ArrowDown className="h-4 w-4" />
                    Vertical
                  </button>
                  <button
                    onClick={() => handleArrangeClick('horizontal')}
                    className="w-full flex items-center gap-2 px-3 py-2 text-sm text-theme-primary hover:bg-theme-secondary transition-colors"
                  >
                    <ArrowRight className="h-4 w-4" />
                    Horizontal
                  </button>
                </div>
              )}
            </div>
          )}
        </div>

        {/* Display Options */}
        <div className="flex items-center gap-1">
          <Button
            onClick={() => onGridToggle?.(!showGrid)}
            size="sm"
            variant={showGrid ? 'primary' : 'outline'}
            className={showGrid ? 'border-theme-interactive-primary' : ''}
            title="Toggle Grid"
          >
            <Grid className="h-4 w-4" />
          </Button>
          <Button
            onClick={() => onSnapToGridToggle?.(!snapToGrid)}
            size="sm"
            variant={snapToGrid ? 'primary' : 'outline'}
            className={snapToGrid ? 'border-theme-interactive-primary' : ''}
            title="Toggle Snap to Grid"
          >
            <Move className="h-4 w-4" />
          </Button>
          <Button
            onClick={() => onPreviewModeToggle?.(!isPreviewMode)}
            size="sm"
            variant={isPreviewMode ? 'primary' : 'outline'}
            title="Preview Mode"
          >
            <Eye className="h-4 w-4" />
          </Button>
          {isPreviewMode && (
            <div className="flex items-center gap-2 px-3 py-1 bg-theme-interactive-primary/10 border border-theme-interactive-primary/20 rounded-md">
              <Eye className="h-3 w-3 text-theme-interactive-primary" />
              <span className="text-xs font-medium text-theme-interactive-primary">Preview Mode</span>
            </div>
          )}
        </div>
      </div>

      {/* Validation Details */}
      {validationResult && showValidationDetails && !validationResult.valid && validationResult.errors.length > 0 && (
        <div className="border-t border-theme p-3 bg-theme-error/5">
          <div className="flex items-center justify-between mb-2">
            <div className="text-sm font-medium text-theme-error">Validation Errors:</div>
            <button
              onClick={() => setShowValidationDetails(false)}
              className="text-theme-error hover:text-theme-error/80 transition-colors p-1 rounded hover:bg-theme-error/20 border border-theme-error/30 hover:border-theme-error"
              title="Dismiss validation details"
            >
              <X className="h-3 w-3" />
            </button>
          </div>
          <ul className="text-sm text-theme-error space-y-1">
            {validationResult.errors.map((error, index) => (
              <li key={index} className="flex items-start gap-2">
                <AlertTriangle className="h-3 w-3 mt-0.5 flex-shrink-0" />
                {error}
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Validation Warnings */}
      {validationResult && showValidationDetails && validationResult.warnings.length > 0 && (
        <div className="border-t border-theme p-3 bg-theme-warning/5">
          <div className="flex items-center justify-between mb-2">
            <div className="text-sm font-medium text-theme-warning">Warnings:</div>
            <button
              onClick={() => setShowValidationDetails(false)}
              className="text-theme-warning hover:text-theme-warning/80 transition-colors p-1 rounded hover:bg-theme-warning/20 border border-theme-warning/30 hover:border-theme-warning"
              title="Dismiss validation details"
            >
              <X className="h-3 w-3" />
            </button>
          </div>
          <ul className="text-sm text-theme-warning space-y-1">
            {validationResult.warnings.map((warning, index) => (
              <li key={index} className="flex items-start gap-2">
                <AlertTriangle className="h-3 w-3 mt-0.5 flex-shrink-0" />
                {warning}
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Keyboard Shortcuts Help */}
      <div className="border-t border-theme px-3 py-2 bg-theme-background">
        <div className="text-xs text-theme-secondary">
          <span className="font-medium text-theme-primary">Shortcuts:</span>
          <span className="ml-2">Ctrl+S: Save</span>
          <span className="ml-2">Ctrl+Z: Undo</span>
          <span className="ml-2">Ctrl+Y: Redo</span>
          <span className="ml-2">Del: Delete selected</span>
        </div>
      </div>
    </div>
  );
};