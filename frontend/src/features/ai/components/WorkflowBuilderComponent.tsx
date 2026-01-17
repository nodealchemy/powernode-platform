import React, { useState } from 'react';
import { Workflow, Plus, Play, Save, Settings, ArrowRight } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Input } from '@/shared/components/ui/Input';

interface WorkflowStep {
  id: string;
  name: string;
  type: 'trigger' | 'action' | 'condition';
  status: 'pending' | 'running' | 'completed' | 'error';
}

export const WorkflowBuilderComponent: React.FC = () => {
  const [workflowName, setWorkflowName] = useState('');
  const [steps, setSteps] = useState<WorkflowStep[]>([]);

  const getStepColor = (type: string) => {
    switch (type) {
      case 'trigger':
        return 'bg-theme-success';
      case 'action':
        return 'bg-theme-info';
      case 'condition':
        return 'bg-theme-warning';
      default:
        return 'bg-theme-tertiary';
    }
  };

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'completed':
        return <Badge variant="success" size="sm">Completed</Badge>;
      case 'running':
        return <Badge variant="warning" size="sm">Running</Badge>;
      case 'error':
        return <Badge variant="danger" size="sm">Error</Badge>;
      default:
        return <Badge variant="outline" size="sm">Pending</Badge>;
    }
  };

  const handleAddStep = () => {
    const newStep: WorkflowStep = {
      id: Date.now().toString(),
      name: 'New Step',
      type: 'action',
      status: 'pending'
    };
    setSteps([...steps, newStep]);
  };

  return (
    <Card className="p-6">
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <div className="h-10 w-10 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
            <Workflow className="h-5 w-5 text-theme-info" />
          </div>
          <div>
            <h3 className="text-lg font-semibold text-theme-primary">Workflow Builder</h3>
            <p className="text-sm text-theme-tertiary">Create and manage AI workflows</p>
          </div>
        </div>
        
        <div className="flex items-center gap-2">
          <Button variant="outline" size="sm">
            <Save className="h-4 w-4 mr-2" />
            Save
          </Button>
          <Button variant="outline" size="sm">
            <Play className="h-4 w-4 mr-2" />
            Test
          </Button>
          <Button size="sm">
            <Settings className="h-4 w-4 mr-2" />
            Deploy
          </Button>
        </div>
      </div>

      {/* Workflow Name */}
      <div className="mb-6">
        <label className="block text-sm font-medium text-theme-secondary mb-2">
          Workflow Name
        </label>
        <Input
          value={workflowName}
          onChange={(e) => setWorkflowName(e.target.value)}
          placeholder="Enter workflow name..."
          className="max-w-md"
        />
      </div>

      {/* Workflow Steps */}
      <div className="space-y-4">
        <div className="flex items-center justify-between">
          <h4 className="text-md font-semibold text-theme-primary">Workflow Steps</h4>
          <Button variant="outline" size="sm" onClick={handleAddStep}>
            <Plus className="h-4 w-4 mr-2" />
            Add Step
          </Button>
        </div>

        <div className="space-y-3">
          {steps.map((step, index) => (
            <div key={step.id} className="flex items-center gap-4">
              {/* Step Number */}
              <div className="flex items-center justify-center w-8 h-8 rounded-full bg-theme-surface border border-theme text-sm font-semibold text-theme-primary">
                {index + 1}
              </div>

              {/* Step Card */}
              <div className="flex-1">
                <div className="flex items-center justify-between p-4 bg-theme-surface rounded-lg border border-theme">
                  <div className="flex items-center gap-3">
                    <div className={`w-3 h-3 rounded-full ${getStepColor(step.type)}`} />
                    <div>
                      <p className="font-medium text-theme-primary">{step.name}</p>
                      <p className="text-sm text-theme-tertiary capitalize">{step.type}</p>
                    </div>
                  </div>
                  
                  <div className="flex items-center gap-3">
                    {getStatusBadge(step.status)}
                    <Button variant="ghost" size="sm">
                      <Settings className="h-4 w-4" />
                    </Button>
                  </div>
                </div>
              </div>

              {/* Arrow */}
              {index < steps.length - 1 && (
                <ArrowRight className="h-4 w-4 text-theme-tertiary" />
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Workflow Actions */}
      <div className="mt-8 p-4 bg-theme-surface rounded-lg border border-theme">
        <h5 className="text-sm font-semibold text-theme-primary mb-3">Quick Actions</h5>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
          <Button variant="outline" size="sm" className="justify-start">
            <Plus className="h-4 w-4 mr-2" />
            Add Trigger
          </Button>
          <Button variant="outline" size="sm" className="justify-start">
            <Plus className="h-4 w-4 mr-2" />
            Add Condition
          </Button>
          <Button variant="outline" size="sm" className="justify-start">
            <Plus className="h-4 w-4 mr-2" />
            Add Action
          </Button>
        </div>
      </div>
    </Card>
  );
};