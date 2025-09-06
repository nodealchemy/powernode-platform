import React, { useState } from 'react';
import {
  DndContext,
  DragEndEvent,
  DragOverlay,
  PointerSensor,
  useSensor,
  useSensors,
} from '@dnd-kit/core';
import {
  SortableContext,
  arrayMove,
  useSortable,
  verticalListSortingStrategy,
} from '@dnd-kit/sortable';
import {
  CSS,
} from '@dnd-kit/utilities';
import { useNotification } from '@/shared/hooks/useNotification';
import proxySettingsApi from '@/shared/services/proxySettingsApi';

interface MultiTenancyConfig {
  enabled: boolean;
  wildcard_patterns: string[];
}

interface MultiTenancyConfigPanelProps {
  config: MultiTenancyConfig;
  onConfigChange: (config: MultiTenancyConfig) => void;
}

interface SortableWildcardItemProps {
  pattern: string;
  index: number;
  onRemove: (pattern: string) => void;
  onEdit: (oldPattern: string, newPattern: string) => void;
}

const SortableWildcardItem: React.FC<SortableWildcardItemProps> = ({ 
  pattern, 
  index, 
  onRemove, 
  onEdit 
}) => {
  const [isEditing, setIsEditing] = useState(false);
  const [editValue, setEditValue] = useState(pattern);
  
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: pattern });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
  };

  const handleSaveEdit = () => {
    if (editValue.trim() && editValue !== pattern) {
      onEdit(pattern, editValue.trim());
    }
    setIsEditing(false);
    setEditValue(pattern);
  };

  const handleCancelEdit = () => {
    setIsEditing(false);
    setEditValue(pattern);
  };

  const getPatternType = (pattern: string) => {
    if (pattern.startsWith('*.')) {
      return { label: 'Subdomain Wildcard', color: 'bg-theme-info/20 text-theme-info' };
    }
    if (pattern.includes('*')) {
      return { label: 'Pattern', color: 'bg-theme-warning/20 text-theme-warning' };
    }
    return { label: 'Domain', color: 'bg-theme-success/20 text-theme-success' };
  };

  const patternType = getPatternType(pattern);

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={`flex items-center justify-between p-4 bg-theme-background rounded-md border border-theme ${
        isDragging ? 'shadow-lg' : ''
      }`}
    >
      <div className="flex items-center flex-1">
        {/* Drag handle */}
        <div
          {...attributes}
          {...listeners}
          className="mr-3 cursor-grab hover:cursor-grabbing text-theme-secondary hover:text-theme-primary transition-colors"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 8h16M4 16h16" />
          </svg>
        </div>
        
        <div className="flex items-center flex-1">
          {isEditing ? (
            <div className="flex items-center space-x-2 flex-1">
              <input
                type="text"
                value={editValue}
                onChange={(e) => setEditValue(e.target.value)}
                onKeyPress={(e) => {
                  if (e.key === 'Enter') handleSaveEdit();
                  if (e.key === 'Escape') handleCancelEdit();
                }}
                className="flex-1 px-2 py-1 text-sm border border-theme rounded bg-theme-surface text-theme-primary focus:ring-2 focus:ring-theme-primary focus:border-theme-primary"
                autoFocus
              />
              <button
                onClick={handleSaveEdit}
                className="p-1 text-theme-success hover:text-theme-success/80"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                </svg>
              </button>
              <button
                onClick={handleCancelEdit}
                className="p-1 text-theme-error hover:text-theme-error/80"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          ) : (
            <>
              <span className="text-theme-primary font-mono text-sm mr-2">{pattern}</span>
              <span className={`px-2 py-1 text-xs rounded ${patternType.color}`}>
                {patternType.label}
              </span>
            </>
          )}
        </div>
      </div>
      
      <div className="flex items-center space-x-2 ml-3">
        {!isEditing && (
          <button
            onClick={() => setIsEditing(true)}
            className="p-1 text-theme-secondary hover:text-theme-primary transition-colors"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
            </svg>
          </button>
        )}
        <button
          onClick={() => onRemove(pattern)}
          className="p-1 text-theme-error hover:text-theme-error/80 transition-colors"
        >
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
          </svg>
        </button>
      </div>
    </div>
  );
};

const MultiTenancyConfigPanel: React.FC<MultiTenancyConfigPanelProps> = ({ 
  config, 
  onConfigChange 
}) => {
  const { showNotification } = useNotification();
  const showSuccess = (msg: string) => showNotification(msg, 'success');
  const showError = (msg: string) => showNotification(msg, 'error');
  
  const [newPattern, setNewPattern] = useState('');
  const [validating, setValidating] = useState(false);
  const [activeId, setActiveId] = useState<string | null>(null);
  
  const sensors = useSensors(
    useSensor(PointerSensor, {
      activationConstraint: {
        distance: 8,
      },
    }),
  );

  const handleToggleEnabled = () => {
    const updatedConfig = {
      ...config,
      enabled: !config.enabled
    };
    onConfigChange(updatedConfig);
  };

  const handleAddPattern = async () => {
    if (!newPattern.trim()) return;

    setValidating(true);
    try {
      // Validate the pattern
      if (!newPattern.includes('*') && !newPattern.match(/^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/)) {
        showError('Pattern must be a valid domain or wildcard pattern (e.g., *.example.com)');
        return;
      }

      const updatedPatterns = [...config.wildcard_patterns, newPattern.trim()];
      const updatedConfig = {
        ...config,
        wildcard_patterns: updatedPatterns
      };
      
      onConfigChange(updatedConfig);
      setNewPattern('');
      showSuccess(`Added wildcard pattern: ${newPattern}`);
    } catch (error) {
      showError('Failed to add wildcard pattern');
    } finally {
      setValidating(false);
    }
  };

  const handleRemovePattern = async (pattern: string) => {
    try {
      const updatedPatterns = config.wildcard_patterns.filter(p => p !== pattern);
      const updatedConfig = {
        ...config,
        wildcard_patterns: updatedPatterns
      };
      
      onConfigChange(updatedConfig);
      showSuccess(`Removed wildcard pattern: ${pattern}`);
    } catch (error) {
      showError('Failed to remove wildcard pattern');
    }
  };

  const handleEditPattern = async (oldPattern: string, newPattern: string) => {
    try {
      const updatedPatterns = config.wildcard_patterns.map(p => 
        p === oldPattern ? newPattern : p
      );
      const updatedConfig = {
        ...config,
        wildcard_patterns: updatedPatterns
      };
      
      onConfigChange(updatedConfig);
      showSuccess(`Updated pattern: ${oldPattern} → ${newPattern}`);
    } catch (error) {
      showError('Failed to update wildcard pattern');
    }
  };

  const handleDragStart = (event: any) => {
    setActiveId(event.active.id);
  };

  const handleDragEnd = async (event: DragEndEvent) => {
    const { active, over } = event;
    setActiveId(null);

    if (!over || active.id === over.id) {
      return;
    }

    const oldIndex = config.wildcard_patterns.findIndex((pattern) => pattern === active.id);
    const newIndex = config.wildcard_patterns.findIndex((pattern) => pattern === over.id);

    const newOrder = arrayMove(config.wildcard_patterns, oldIndex, newIndex);
    
    const updatedConfig = {
      ...config,
      wildcard_patterns: newOrder
    };
    
    onConfigChange(updatedConfig);
    showSuccess('Wildcard pattern order updated');
  };

  return (
    <div className="bg-theme-surface rounded-lg p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h3 className="text-lg font-medium text-theme-primary">
            Multi-Tenancy Configuration
          </h3>
          <p className="mt-1 text-sm text-theme-secondary">
            Configure wildcard domains for multi-tenant support
          </p>
        </div>
        <button
          onClick={handleToggleEnabled}
          className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
            config.enabled ? 'bg-theme-success' : 'bg-theme-muted'
          }`}
        >
          <span
            className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
              config.enabled ? 'translate-x-6' : 'translate-x-1'
            }`}
          />
        </button>
      </div>

      {config.enabled && (
        <>
          {/* Add new pattern */}
          <div className="mb-6">
            <div className="flex space-x-2 mb-4">
              <input
                type="text"
                value={newPattern}
                onChange={(e) => setNewPattern(e.target.value)}
                onKeyPress={(e) => e.key === 'Enter' && handleAddPattern()}
                placeholder="*.customers.example.com"
                className="flex-1 px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-primary focus:border-theme-primary"
              />
              <button
                onClick={handleAddPattern}
                disabled={validating || !newPattern.trim()}
                className="btn-theme btn-theme-primary"
              >
                {validating ? 'Adding...' : 'Add Pattern'}
              </button>
            </div>
            
            <div className="text-sm text-theme-secondary">
              <p className="mb-2"><strong>Pattern Examples:</strong></p>
              <ul className="space-y-1">
                <li>• <code className="font-mono bg-theme-background px-1 rounded">*.customers.example.com</code> - All customer subdomains</li>
                <li>• <code className="font-mono bg-theme-background px-1 rounded">*.saas.myapp.com</code> - SaaS tenant subdomains</li>
                <li>• <code className="font-mono bg-theme-background px-1 rounded">tenant-*.example.com</code> - Prefix pattern matching</li>
                <li>• <code className="font-mono bg-theme-background px-1 rounded">specific.example.com</code> - Exact domain match</li>
              </ul>
            </div>
          </div>

          {/* Wildcard patterns list */}
          <div className="space-y-2">
            <h4 className="text-md font-medium text-theme-primary">
              Wildcard Patterns ({config.wildcard_patterns.length})
            </h4>
            
            {config.wildcard_patterns.length === 0 ? (
              <div className="text-center py-8 text-theme-secondary">
                <svg className="w-12 h-12 mx-auto mb-4 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
                </svg>
                <p>No wildcard patterns configured</p>
                <p className="text-xs mt-1">Add patterns above to enable multi-tenant domains</p>
              </div>
            ) : (
              <DndContext 
                sensors={sensors} 
                onDragStart={handleDragStart} 
                onDragEnd={handleDragEnd}
              >
                <SortableContext items={config.wildcard_patterns} strategy={verticalListSortingStrategy}>
                  {config.wildcard_patterns.map((pattern, index) => (
                    <SortableWildcardItem
                      key={pattern}
                      pattern={pattern}
                      index={index}
                      onRemove={handleRemovePattern}
                      onEdit={handleEditPattern}
                    />
                  ))}
                </SortableContext>
                
                <DragOverlay>
                  {activeId ? (
                    <div className="flex items-center justify-between p-4 bg-theme-background rounded-md border border-theme shadow-lg opacity-90">
                      <div className="flex items-center">
                        <div className="mr-3 text-theme-secondary">
                          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 8h16M4 16h16" />
                          </svg>
                        </div>
                        <span className="text-theme-primary font-mono text-sm">{activeId}</span>
                      </div>
                    </div>
                  ) : null}
                </DragOverlay>
              </DndContext>
            )}
          </div>

          {/* Status and impact info */}
          <div className="mt-6 p-4 bg-theme-info/10 border border-theme-info rounded-md">
            <div className="flex items-start space-x-2">
              <svg className="w-5 h-5 text-theme-info flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <div className="text-sm text-theme-info">
                <p className="font-medium mb-2">Multi-Tenancy Impact:</p>
                <ul className="space-y-1">
                  <li>• CORS origins will include all wildcard patterns</li>
                  <li>• Each pattern allows unlimited subdomains/variations</li>
                  <li>• Patterns are checked in the order listed (drag to reorder)</li>
                  <li>• Higher patterns have priority in matching</li>
                </ul>
              </div>
            </div>
          </div>
        </>
      )}

      {!config.enabled && (
        <div className="text-center py-8 text-theme-secondary">
          <svg className="w-16 h-16 mx-auto mb-4 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
          </svg>
          <h4 className="text-lg font-medium text-theme-primary mb-2">Multi-Tenancy Disabled</h4>
          <p className="text-sm mb-4">
            Enable multi-tenancy to allow multiple tenants to use wildcard domains
          </p>
          <div className="text-xs space-y-1">
            <p><strong>When enabled:</strong></p>
            <p>• Support for *.customers.example.com patterns</p>
            <p>• Automatic CORS configuration for tenant domains</p>
            <p>• Flexible domain routing and validation</p>
          </div>
        </div>
      )}
    </div>
  );
};

export default MultiTenancyConfigPanel;