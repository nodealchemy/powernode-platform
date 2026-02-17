import React, { useState } from 'react';
import { codeFactoryApi } from '../api/codeFactoryApi';

interface Props {
  contractId?: string;
}

export const PrdGenerator: React.FC<Props> = ({ contractId }) => {
  const [prompt, setPrompt] = useState('');
  const [generating, setGenerating] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const handleGenerate = async () => {
    if (!prompt.trim()) return;
    setGenerating(true);
    setError(null);
    setResult(null);
    try {
      const response = await codeFactoryApi.processWebhook({
        event_type: 'prd_generate',
        pr_number: 0,
        head_sha: '',
        changed_files: [],
        repository_id: contractId,
      });
      setResult(JSON.stringify(response.data?.result || {}, null, 2));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'PRD generation failed');
    } finally {
      setGenerating(false);
    }
  };

  return (
    <div className="space-y-4">
      <div className="card-theme p-4">
        <h3 className="text-sm font-semibold text-theme-primary mb-3">Generate PRD</h3>
        <div className="space-y-3">
          <textarea
            value={prompt}
            onChange={(e) => setPrompt(e.target.value)}
            placeholder="Describe the feature or change you want to implement..."
            className="w-full h-32 bg-theme-secondary-bg text-theme-primary border border-theme-border rounded-lg p-3 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-theme-accent/50"
          />
          <div className="flex items-center justify-between">
            <span className="text-xs text-theme-secondary">
              PRD generation uses RALPH for task decomposition
            </span>
            <button
              onClick={handleGenerate}
              disabled={generating || !prompt.trim()}
              className="px-4 py-2 bg-theme-accent text-theme-on-primary text-sm rounded-lg hover:bg-theme-accent-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {generating ? 'Generating...' : 'Generate PRD'}
            </button>
          </div>
        </div>
      </div>

      {error && (
        <div className="card-theme p-3 border-l-4 border-theme-error text-sm text-theme-error">
          {error}
        </div>
      )}

      {result && (
        <div className="card-theme p-4">
          <h3 className="text-sm font-semibold text-theme-primary mb-2">Generated PRD</h3>
          <pre className="text-xs text-theme-secondary bg-theme-secondary-bg p-3 rounded-lg overflow-x-auto whitespace-pre-wrap">
            {result}
          </pre>
        </div>
      )}
    </div>
  );
};
