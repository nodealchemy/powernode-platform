import { useState } from 'react';
import { Search, Loader2, CheckCircle, AlertTriangle } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { skillLifecycleApi } from '../services/skillLifecycleApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { ResearchResultsPanel } from './ResearchResultsPanel';
import type { ResearchReport } from '../types/lifecycle';

interface ResearchModalProps {
  isOpen: boolean;
  onClose: () => void;
  onProposalCreated: () => void;
}

type Phase = 'input' | 'researching' | 'results';

export function ResearchModal({ isOpen, onClose, onProposalCreated }: ResearchModalProps) {
  const { showNotification } = useNotifications();
  const [phase, setPhase] = useState<Phase>('input');
  const [topic, setTopic] = useState('');
  const [sources, setSources] = useState<string[]>(['knowledge_graph', 'knowledge_bases', 'mcp_tools']);
  const [report, setReport] = useState<ResearchReport | null>(null);

  const availableSources = [
    { id: 'knowledge_graph', label: 'Knowledge Graph' },
    { id: 'knowledge_bases', label: 'Knowledge Bases' },
    { id: 'mcp_tools', label: 'MCP Tools' },
    { id: 'federation', label: 'A2A Federation' },
    { id: 'web', label: 'Web Search' },
  ];

  const toggleSource = (id: string) => {
    setSources((prev) =>
      prev.includes(id) ? prev.filter((s) => s !== id) : [...prev, id]
    );
  };

  const handleResearch = async () => {
    if (!topic.trim()) return;
    setPhase('researching');

    const response = await skillLifecycleApi.startResearch({ topic: topic.trim(), sources });
    if (response.success && response.data) {
      setReport(response.data.research);
      setPhase('results');
    } else {
      showNotification(response.error || 'Research failed', 'error');
      setPhase('input');
    }
  };

  const handleCreateProposal = () => {
    if (report) {
      onProposalCreated();
      handleReset();
    }
  };

  const handleReset = () => {
    setPhase('input');
    setTopic('');
    setReport(null);
    onClose();
  };

  return (
    <Modal isOpen={isOpen} onClose={handleReset} title="Skill Research" maxWidth="3xl">
      {phase === 'input' && (
        <div className="space-y-5">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1.5">
              Research Topic
            </label>
            <input
              type="text"
              value={topic}
              onChange={(e) => setTopic(e.target.value)}
              placeholder="e.g., Kubernetes deployment management, Document summarization..."
              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-md text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
              onKeyDown={(e) => e.key === 'Enter' && handleResearch()}
              data-testid="research-topic-input"
            />
            <p className="mt-1 text-xs text-theme-tertiary">
              Describe the capability you want to research. The system will search existing skills,
              knowledge bases, MCP tools, and more to help build a skill proposal.
            </p>
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Research Sources
            </label>
            <div className="flex flex-wrap gap-2">
              {availableSources.map((source) => (
                <button
                  key={source.id}
                  onClick={() => toggleSource(source.id)}
                  className={`px-3 py-1.5 text-sm rounded-md border transition-colors ${
                    sources.includes(source.id)
                      ? 'bg-theme-primary text-white border-transparent'
                      : 'text-theme-secondary border-theme hover:bg-theme-surface-hover'
                  }`}
                >
                  {source.label}
                </button>
              ))}
            </div>
          </div>

          <div className="flex justify-end gap-3 pt-2">
            <Button variant="ghost" onClick={handleReset}>Cancel</Button>
            <Button
              variant="primary"
              onClick={handleResearch}
              disabled={!topic.trim() || sources.length === 0}
            >
              <Search className="w-4 h-4 mr-1.5" />
              Research
            </Button>
          </div>
        </div>
      )}

      {phase === 'researching' && (
        <div className="flex flex-col items-center justify-center py-12 space-y-4">
          <Loader2 className="w-8 h-8 text-theme-primary animate-spin" />
          <p className="text-theme-primary font-medium">Researching "{topic}"...</p>
          <p className="text-sm text-theme-tertiary">
            Searching {sources.length} source{sources.length !== 1 ? 's' : ''} for relevant information
          </p>
        </div>
      )}

      {phase === 'results' && report && (
        <div className="space-y-4">
          <div className="flex items-center gap-2 text-theme-primary">
            {(report.overlap_warnings?.length ?? 0) > 0 ? (
              <AlertTriangle className="w-5 h-5 text-theme-warning" />
            ) : (
              <CheckCircle className="w-5 h-5 text-theme-success" />
            )}
            <span className="font-medium">
              Research complete
              {report.confidence_score != null && ` (${Math.round(report.confidence_score * 100)}% confidence)`}
            </span>
          </div>

          <ResearchResultsPanel report={report} />

          <div className="flex justify-end gap-3 pt-2">
            <Button variant="ghost" onClick={() => setPhase('input')}>
              Research Again
            </Button>
            <Button variant="primary" onClick={handleCreateProposal} data-testid="create-proposal-btn">
              Create Proposal
            </Button>
          </div>
        </div>
      )}
    </Modal>
  );
}
