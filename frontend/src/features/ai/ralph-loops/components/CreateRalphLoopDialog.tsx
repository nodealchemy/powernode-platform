import React, { useState } from 'react';
import { RotateCcw } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { ralphLoopsApi } from '@/shared/services/ai/RalphLoopsApiService';
import type { RalphAiTool, CreateRalphLoopRequest } from '@/shared/services/ai/types/ralph-types';

interface CreateRalphLoopDialogProps {
  isOpen: boolean;
  onClose: () => void;
  onCreated: (loopId: string) => void;
}

const aiToolOptions = [
  { value: 'claude_code', label: 'Claude Code' },
  { value: 'amp', label: 'Amp CLI' },
];

export const CreateRalphLoopDialog: React.FC<CreateRalphLoopDialogProps> = ({
  isOpen,
  onClose,
  onCreated,
}) => {
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [aiTool, setAiTool] = useState<RalphAiTool>('claude_code');
  const [maxIterations, setMaxIterations] = useState(50);
  const [repositoryUrl, setRepositoryUrl] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!name.trim()) {
      setError('Name is required');
      return;
    }

    try {
      setLoading(true);
      setError(null);

      const request: CreateRalphLoopRequest = {
        name: name.trim(),
        description: description.trim() || undefined,
        ai_tool: aiTool,
        max_iterations: maxIterations,
        repository_url: repositoryUrl.trim() || undefined,
        prd_json: { tasks: [] },
      };

      const response = await ralphLoopsApi.createLoop(request);
      onCreated(response.ralph_loop.id);
      handleClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create loop');
    } finally {
      setLoading(false);
    }
  };

  const handleClose = () => {
    setName('');
    setDescription('');
    setAiTool('claude_code');
    setMaxIterations(50);
    setRepositoryUrl('');
    setError(null);
    onClose();
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Create Ralph Loop"
      icon={<RotateCcw className="w-6 h-6" />}
      subtitle="Set up an autonomous AI agent loop for iterative task execution"
      size="md"
      footer={
        <>
          <Button
            variant="outline"
            onClick={handleClose}
            disabled={loading}
          >
            Cancel
          </Button>
          <Button
            variant="primary"
            onClick={handleSubmit}
            disabled={loading || !name.trim()}
          >
            {loading ? 'Creating...' : 'Create Loop'}
          </Button>
        </>
      }
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        {error && (
          <div className="p-3 rounded-lg bg-theme-status-error/10 text-theme-status-error text-sm">
            {error}
          </div>
        )}

        <div>
          <label className="block text-sm font-medium text-theme-text-primary mb-1">
            Name *
          </label>
          <Input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="My Ralph Loop"
            autoFocus
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-text-primary mb-1">
            Description
          </label>
          <Input
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Optional description..."
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-text-primary mb-1">
            AI Tool
          </label>
          <Select
            value={aiTool}
            onChange={(value) => setAiTool(value as RalphAiTool)}
          >
            {aiToolOptions.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </Select>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-text-primary mb-1">
            Max Iterations
          </label>
          <Input
            type="number"
            value={maxIterations}
            onChange={(e) => setMaxIterations(parseInt(e.target.value) || 50)}
            min={1}
            max={1000}
          />
          <p className="text-xs text-theme-text-secondary mt-1">
            Maximum number of AI iterations before stopping
          </p>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-text-primary mb-1">
            Repository URL
          </label>
          <Input
            value={repositoryUrl}
            onChange={(e) => setRepositoryUrl(e.target.value)}
            placeholder="https://github.com/user/repo"
          />
          <p className="text-xs text-theme-text-secondary mt-1">
            Git repository URL (optional)
          </p>
        </div>
      </form>
    </Modal>
  );
};

export default CreateRalphLoopDialog;
