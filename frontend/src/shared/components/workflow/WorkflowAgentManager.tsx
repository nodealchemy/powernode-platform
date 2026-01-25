import React, { useState, useEffect } from 'react';
import { Plus, Settings, Trash2, Eye, EyeOff, ChevronUp, ChevronDown } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import { Input } from '@/shared/components/ui/Input';
import { Modal } from '@/shared/components/ui/Modal';
import { agentsApi } from '@/shared/services/ai';
import { AiAgent } from '@/shared/types/ai';

interface WorkflowAgentAssignment {
  id?: string;
  agent_id: string;
  agent_role: 'operations' | 'optimizer' | 'assistant' | 'monitor' | 'custom';
  priority: number;
  is_active: boolean;
  configuration: Record<string, any>;
}

interface WorkflowAgentManagerProps {
  assignments: WorkflowAgentAssignment[];
  onAssignmentsChange: (assignments: WorkflowAgentAssignment[]) => void;
  scope: 'workflow' | 'node';
  scopeId?: string;
}

const AGENT_ROLES = [
  { value: 'operations', label: 'Operations', description: 'Manages workflow execution and node operations' },
  { value: 'optimizer', label: 'Optimizer', description: 'Analyzes and optimizes workflow performance' },
  { value: 'assistant', label: 'Assistant', description: 'Provides general workflow development assistance' },
  { value: 'monitor', label: 'Monitor', description: 'Monitors workflow execution and health' },
  { value: 'custom', label: 'Custom', description: 'Custom role with specific configuration' }
];

export const WorkflowAgentManager: React.FC<WorkflowAgentManagerProps> = ({
  assignments,
  onAssignmentsChange,
  scope
}) => {
  const [availableAgents, setAvailableAgents] = useState<AiAgent[]>([]);
  const [loadingAgents, setLoadingAgents] = useState(false);
  const [showAddModal, setShowAddModal] = useState(false);
  const [editingAssignment, setEditingAssignment] = useState<WorkflowAgentAssignment | null>(null);

  // Load available agents
  useEffect(() => {
    loadAvailableAgents();
  }, []);

  const loadAvailableAgents = async () => {
    try {
      setLoadingAgents(true);
      const response = await agentsApi.getAgents({
        status: 'active',
        per_page: 100
      });
      setAvailableAgents(response.items || []);
    } catch (error) {
      console.error('Failed to load agents:', error);
    } finally {
      setLoadingAgents(false);
    }
  };

  const addAssignment = (assignment: Omit<WorkflowAgentAssignment, 'id' | 'priority'>) => {
    const newAssignment: WorkflowAgentAssignment = {
      ...assignment,
      id: `temp-${Date.now()}`,
      priority: Math.max(0, ...assignments.map(a => a.priority)) + 1
    };
    onAssignmentsChange([...assignments, newAssignment]);
    setShowAddModal(false);
  };

  const updateAssignment = (index: number, updates: Partial<WorkflowAgentAssignment>) => {
    const updated = assignments.map((assignment, i) =>
      i === index ? { ...assignment, ...updates } : assignment
    );
    onAssignmentsChange(updated);
  };

  const removeAssignment = (index: number) => {
    onAssignmentsChange(assignments.filter((_, i) => i !== index));
  };

  const moveAssignment = (index: number, direction: 'up' | 'down') => {
    const newAssignments = [...assignments];
    const targetIndex = direction === 'up' ? index - 1 : index + 1;

    if (targetIndex >= 0 && targetIndex < assignments.length) {
      // Swap priorities
      const temp = newAssignments[index].priority;
      newAssignments[index].priority = newAssignments[targetIndex].priority;
      newAssignments[targetIndex].priority = temp;

      // Swap positions
      [newAssignments[index], newAssignments[targetIndex]] =
      [newAssignments[targetIndex], newAssignments[index]];

      onAssignmentsChange(newAssignments);
    }
  };

  const getAgentName = (agentId: string) => {
    const agent = availableAgents.find(a => a.id === agentId);
    return agent ? `${agent.name} (${agent.agent_type})` : 'Unknown Agent';
  };

  const getRoleColor = (role: string) => {
    switch (role) {
      case 'operations': return 'bg-theme-info/20 text-theme-info';
      case 'optimizer': return 'bg-theme-success/20 text-theme-success';
      case 'assistant': return 'bg-theme-interactive-primary/20 text-theme-interactive-primary';
      case 'monitor': return 'bg-theme-warning/20 text-theme-warning';
      case 'custom': return 'bg-theme-surface text-theme-primary';
      default: return 'bg-theme-surface text-theme-primary';
    }
  };

  const sortedAssignments = [...assignments].sort((a, b) => a.priority - b.priority);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-medium text-theme-primary">
            {scope === 'workflow' ? 'Workflow Agents' : 'Node Agents'}
          </h3>
          <p className="text-sm text-theme-muted">
            {scope === 'workflow'
              ? 'Agents assigned at workflow level apply to all nodes unless overridden'
              : 'Node-level agents override workflow-level assignments for this specific node'
            }
          </p>
        </div>
        <Button
          type="button"
          variant="outline"
          size="sm"
          onClick={() => setShowAddModal(true)}
          disabled={loadingAgents}
        >
          <Plus className="h-4 w-4 mr-1" />
          Add Agent
        </Button>
      </div>

      {sortedAssignments.length === 0 ? (
        <div className="text-center py-8 border-2 border-dashed border-theme rounded-lg">
          <p className="text-theme-muted">
            No agents assigned. Click "Add Agent" to get started.
          </p>
        </div>
      ) : (
        <div className="space-y-2">
          {sortedAssignments.map((assignment, index) => (
            <div
              key={assignment.id || index}
              className={`
                p-4 border rounded-lg transition-all duration-200
                ${assignment.is_active
                  ? 'border-theme bg-theme-surface'
                  : 'border-theme-muted bg-theme-muted/5'
                }
              `}
            >
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3 flex-1">
                  <div className="flex flex-col gap-1">
                    <button
                      onClick={() => moveAssignment(index, 'up')}
                      disabled={index === 0}
                      className="p-1 hover:bg-theme-secondary rounded disabled:opacity-50"
                    >
                      <ChevronUp className="h-3 w-3" />
                    </button>
                    <button
                      onClick={() => moveAssignment(index, 'down')}
                      disabled={index === sortedAssignments.length - 1}
                      className="p-1 hover:bg-theme-secondary rounded disabled:opacity-50"
                    >
                      <ChevronDown className="h-3 w-3" />
                    </button>
                  </div>

                  <div className="flex-1">
                    <div className="flex items-center gap-2 mb-1">
                      <span className="font-medium text-theme-primary">
                        {getAgentName(assignment.agent_id)}
                      </span>
                      <span className={`px-2 py-1 rounded-full text-xs font-medium ${getRoleColor(assignment.agent_role)}`}>
                        {assignment.agent_role}
                      </span>
                      <span className="text-xs text-theme-muted">
                        Priority: {assignment.priority}
                      </span>
                    </div>
                    {Object.keys(assignment.configuration).length > 0 && (
                      <div className="text-xs text-theme-muted">
                        {Object.keys(assignment.configuration).length} configuration options
                      </div>
                    )}
                  </div>
                </div>

                <div className="flex items-center gap-2">
                  <button
                    onClick={() => updateAssignment(index, { is_active: !assignment.is_active })}
                    className={`p-2 rounded-md transition-colors ${
                      assignment.is_active
                        ? 'text-theme-success hover:bg-theme-success/10'
                        : 'text-theme-muted hover:bg-theme-surface'
                    }`}
                    title={assignment.is_active ? 'Disable agent' : 'Enable agent'}
                  >
                    {assignment.is_active ? (
                      <Eye className="h-4 w-4" />
                    ) : (
                      <EyeOff className="h-4 w-4" />
                    )}
                  </button>

                  <button
                    onClick={() => setEditingAssignment(assignment)}
                    className="p-2 text-theme-secondary hover:text-theme-primary hover:bg-theme-secondary rounded-md transition-colors"
                    title="Configure agent"
                  >
                    <Settings className="h-4 w-4" />
                  </button>

                  <button
                    onClick={() => removeAssignment(index)}
                    className="p-2 text-theme-danger hover:text-theme-danger hover:bg-theme-danger/10 rounded-md transition-colors"
                    title="Remove agent"
                  >
                    <Trash2 className="h-4 w-4" />
                  </button>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Add Agent Modal */}
      <AddAgentModal
        isOpen={showAddModal}
        onClose={() => setShowAddModal(false)}
        onAdd={addAssignment}
        availableAgents={availableAgents}
        existingRoles={assignments.map(a => a.agent_role)}
      />

      {/* Edit Assignment Modal */}
      {editingAssignment && (
        <EditAssignmentModal
          assignment={editingAssignment}
          onClose={() => setEditingAssignment(null)}
          onSave={(updates) => {
            const index = assignments.findIndex(a => a.id === editingAssignment.id);
            if (index >= 0) {
              updateAssignment(index, updates);
            }
            setEditingAssignment(null);
          }}
          availableAgents={availableAgents}
        />
      )}
    </div>
  );
};

// Add Agent Modal Component
interface AddAgentModalProps {
  isOpen: boolean;
  onClose: () => void;
  onAdd: (assignment: Omit<WorkflowAgentAssignment, 'id' | 'priority'>) => void;
  availableAgents: AiAgent[];
  existingRoles: string[];
}

const AddAgentModal: React.FC<AddAgentModalProps> = ({
  isOpen,
  onClose,
  onAdd,
  availableAgents,
  existingRoles
}) => {
  const [selectedAgentId, setSelectedAgentId] = useState('');
  const [selectedRole, setSelectedRole] = useState('');

  const handleAdd = () => {
    if (selectedAgentId && selectedRole) {
      onAdd({
        agent_id: selectedAgentId,
        agent_role: selectedRole as WorkflowAgentAssignment['agent_role'],
        is_active: true,
        configuration: {}
      });
      setSelectedAgentId('');
      setSelectedRole('');
      onClose();
    }
  };

  const availableRoles = AGENT_ROLES.filter(role =>
    role.value === 'custom' || !existingRoles.includes(role.value)
  );

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Add Agent Assignment"
      maxWidth="md"
      footer={
        <div className="flex gap-3">
          <Button variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button
            onClick={handleAdd}
            disabled={!selectedAgentId || !selectedRole}
          >
            Add Agent
          </Button>
        </div>
      }
    >
      <div className="space-y-4">
        <EnhancedSelect
          label="Agent"
          value={selectedAgentId}
          onChange={setSelectedAgentId}
          options={availableAgents.map(agent => ({
            value: agent.id,
            label: `${agent.name} (${agent.agent_type})`,
            description: agent.description
          }))}
          placeholder="Select an agent..."
        />

        <EnhancedSelect
          label="Role"
          value={selectedRole}
          onChange={setSelectedRole}
          options={availableRoles}
          placeholder="Select a role..."
        />
      </div>
    </Modal>
  );
};

// Edit Assignment Modal Component
interface EditAssignmentModalProps {
  assignment: WorkflowAgentAssignment;
  onClose: () => void;
  onSave: (updates: Partial<WorkflowAgentAssignment>) => void;
  availableAgents: AiAgent[];
}

const EditAssignmentModal: React.FC<EditAssignmentModalProps> = ({
  assignment,
  onClose,
  onSave,
  availableAgents
}) => {
  const [priority, setPriority] = useState(assignment.priority);
  const [customConfig, setCustomConfig] = useState(
    JSON.stringify(assignment.configuration, null, 2)
  );

  const handleSave = () => {
    try {
      const configuration = customConfig.trim()
        ? JSON.parse(customConfig)
        : {};

      onSave({
        priority,
        configuration
      });
    } catch (error) {
      // Handle JSON parse error
      console.error('Invalid JSON configuration:', error);
    }
  };

  const agentName = availableAgents.find(a => a.id === assignment.agent_id)?.name || 'Unknown Agent';

  return (
    <Modal
      isOpen={true}
      onClose={onClose}
      title={`Configure: ${agentName}`}
      maxWidth="lg"
      footer={
        <div className="flex gap-3">
          <Button variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={handleSave}>
            Save Changes
          </Button>
        </div>
      }
    >
      <div className="space-y-4">
        <Input
          label="Priority"
          type="number"
          value={priority}
          onChange={(e) => setPriority(parseInt(e.target.value) || 1)}
          min={1}
          max={100}
        />

        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">
            Custom Configuration (JSON)
          </label>
          <textarea
            value={customConfig}
            onChange={(e) => setCustomConfig(e.target.value)}
            className="w-full h-48 p-3 border rounded-md font-mono text-sm resize-none"
            placeholder='{"key": "value"}'
          />
          <p className="text-xs text-theme-muted mt-1">
            Optional JSON configuration for agent-specific settings
          </p>
        </div>
      </div>
    </Modal>
  );
};