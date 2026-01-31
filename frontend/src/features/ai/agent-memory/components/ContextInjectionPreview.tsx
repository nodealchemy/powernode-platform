import React, { useState } from 'react';
import {
  Sparkles,
  Brain,
  Lightbulb,
  Activity,
  Copy,
  RefreshCw,
} from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Loading } from '@/shared/components/ui/Loading';
import { memoryApiService } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { cn } from '@/shared/utils/cn';
import type {
  ContextInjectionResponse,
  ContextInjectionRequest,
  MemoryType,
} from '@/shared/services/ai/types/memory-types';

interface ContextInjectionPreviewProps {
  agentId: string;
  className?: string;
}

export const ContextInjectionPreview: React.FC<ContextInjectionPreviewProps> = ({
  agentId,
  className,
}) => {
  const [query, setQuery] = useState('');
  const [tokenBudget, setTokenBudget] = useState(4000);
  const [includeTypes, setIncludeTypes] = useState<MemoryType[]>(['factual', 'experiential']);
  const [response, setResponse] = useState<ContextInjectionResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const { addNotification } = useNotifications();

  const handleGenerate = async () => {
    try {
      setLoading(true);
      setError(null);

      const request: ContextInjectionRequest = {
        query: query || undefined,
        token_budget: tokenBudget,
        include_types: includeTypes.length > 0 ? includeTypes : undefined,
      };

      const result = await memoryApiService.getContextInjection(agentId, request);
      setResponse(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to generate context');
    } finally {
      setLoading(false);
    }
  };

  const handleCopy = () => {
    if (response?.context) {
      navigator.clipboard.writeText(response.context);
      addNotification({ type: 'success', title: 'Copied', message: 'Context copied to clipboard' });
    }
  };

  const toggleType = (type: MemoryType) => {
    if (includeTypes.includes(type)) {
      setIncludeTypes(includeTypes.filter((t) => t !== type));
    } else {
      setIncludeTypes([...includeTypes, type]);
    }
  };

  return (
    <Card className={className}>
      <CardHeader
        title="Context Injection Preview"
        icon={<Sparkles className="h-5 w-5" />}
      />
      <CardContent className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Query (optional)
          </label>
          <Input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Enter a task or query for relevant context..."
          />
          <p className="text-xs text-theme-muted mt-1">
            Provide a query to get contextually relevant memories
          </p>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Token Budget
          </label>
          <Input
            type="number"
            value={tokenBudget}
            onChange={(e) => setTokenBudget(parseInt(e.target.value) || 4000)}
            min={100}
            max={32000}
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-2">
            Include Memory Types
          </label>
          <div className="flex gap-2">
            <Button
              variant={includeTypes.includes('factual') ? 'primary' : 'outline'}
              size="sm"
              onClick={() => toggleType('factual')}
            >
              <Brain className="h-4 w-4 mr-1" />
              Factual
            </Button>
            <Button
              variant={includeTypes.includes('experiential') ? 'primary' : 'outline'}
              size="sm"
              onClick={() => toggleType('experiential')}
            >
              <Lightbulb className="h-4 w-4 mr-1" />
              Experiential
            </Button>
            <Button
              variant={includeTypes.includes('working') ? 'primary' : 'outline'}
              size="sm"
              onClick={() => toggleType('working')}
            >
              <Activity className="h-4 w-4 mr-1" />
              Working
            </Button>
          </div>
        </div>

        <Button
          variant="primary"
          onClick={handleGenerate}
          disabled={loading}
          className="w-full"
        >
          {loading ? (
            <>
              <RefreshCw className="h-4 w-4 mr-2 animate-spin" />
              Generating...
            </>
          ) : (
            <>
              <Sparkles className="h-4 w-4 mr-2" />
              Generate Context
            </>
          )}
        </Button>

        {error && (
          <div className="p-3 bg-theme-danger/10 border border-theme-danger/30 rounded-lg text-theme-danger text-sm">
            {error}
          </div>
        )}

        {response && (
          <div className="space-y-4 pt-4 border-t border-theme">
            <div className="flex items-center justify-between">
              <div className="space-y-1">
                <h4 className="text-sm font-medium text-theme-secondary">Generated Context</h4>
                <p className="text-xs text-theme-muted">
                  ~{response.token_estimate} tokens
                </p>
              </div>
              <Button variant="ghost" size="sm" onClick={handleCopy}>
                <Copy className="h-4 w-4 mr-1" />
                Copy
              </Button>
            </div>

            {/* Token breakdown */}
            <div className="grid grid-cols-3 gap-2">
              <div className="p-2 bg-theme-info/10 rounded text-center">
                <div className="text-sm font-medium text-theme-primary">
                  {response.breakdown.factual}
                </div>
                <div className="text-xs text-theme-muted">Factual</div>
              </div>
              <div className="p-2 bg-theme-warning/10 rounded text-center">
                <div className="text-sm font-medium text-theme-primary">
                  {response.breakdown.experiential}
                </div>
                <div className="text-xs text-theme-muted">Experiential</div>
              </div>
              <div className="p-2 bg-theme-success/10 rounded text-center">
                <div className="text-sm font-medium text-theme-primary">
                  {response.breakdown.working}
                </div>
                <div className="text-xs text-theme-muted">Working</div>
              </div>
            </div>

            {/* Context preview */}
            <div className="relative">
              <pre className="bg-theme-surface-dark p-4 rounded-lg text-xs overflow-x-auto max-h-64 whitespace-pre-wrap">
                <code className="text-theme-primary">{response.context}</code>
              </pre>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
};

export default ContextInjectionPreview;
