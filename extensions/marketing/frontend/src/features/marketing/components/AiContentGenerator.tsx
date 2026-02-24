import React, { useState } from 'react';
import { Sparkles, Copy, RefreshCw } from 'lucide-react';
import { apiClient } from '@/shared/services/apiClient';
import { logger } from '@/shared/utils/logger';
import type { ChannelType, ApiResponse } from '../types';

interface AiContentGeneratorProps {
  channel?: ChannelType;
  campaignName?: string;
  onInsert?: (content: string) => void;
}

interface GeneratedContent {
  subject: string;
  body: string;
  hashtags: string[];
}

export const AiContentGenerator: React.FC<AiContentGeneratorProps> = ({
  channel = 'email',
  campaignName = '',
  onInsert,
}) => {
  const [prompt, setPrompt] = useState('');
  const [tone, setTone] = useState<'professional' | 'casual' | 'urgent' | 'friendly'>('professional');
  const [generating, setGenerating] = useState(false);
  const [result, setResult] = useState<GeneratedContent | null>(null);
  const [error, setError] = useState<string | null>(null);

  const handleGenerate = async () => {
    if (!prompt.trim()) return;
    try {
      setGenerating(true);
      setError(null);
      const response = await apiClient.post<ApiResponse<{ content: GeneratedContent }>>(
        '/marketing/ai/generate_content',
        {
          prompt: prompt.trim(),
          channel,
          tone,
          campaign_name: campaignName,
        }
      );
      setResult(response.data.data.content);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Content generation failed';
      setError(message);
      logger.error('AI content generation failed:', err);
    } finally {
      setGenerating(false);
    }
  };

  const handleCopy = (text: string) => {
    navigator.clipboard.writeText(text);
  };

  return (
    <div className="card-theme p-6 space-y-4">
      <div className="flex items-center gap-2">
        <Sparkles className="w-5 h-5 text-theme-warning" />
        <h3 className="text-lg font-medium text-theme-primary">AI Content Generator</h3>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <div className="md:col-span-3">
          <label className="block text-sm font-medium text-theme-primary mb-1">Prompt</label>
          <textarea
            value={prompt}
            onChange={(e) => setPrompt(e.target.value)}
            className="input-theme w-full"
            rows={3}
            placeholder="Describe the content you want to generate..."
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">Tone</label>
          <select
            value={tone}
            onChange={(e) => setTone(e.target.value as typeof tone)}
            className="input-theme w-full"
          >
            <option value="professional">Professional</option>
            <option value="casual">Casual</option>
            <option value="urgent">Urgent</option>
            <option value="friendly">Friendly</option>
          </select>
          <button
            onClick={handleGenerate}
            disabled={generating || !prompt.trim()}
            className="btn-theme btn-theme-primary w-full mt-3 disabled:opacity-50"
          >
            {generating ? (
              <RefreshCw className="w-4 h-4 mr-2 inline animate-spin" />
            ) : (
              <Sparkles className="w-4 h-4 mr-2 inline" />
            )}
            {generating ? 'Generating...' : 'Generate'}
          </button>
        </div>
      </div>

      {error && (
        <div className="p-3 rounded-lg bg-theme-error bg-opacity-10 text-theme-error text-sm">
          {error}
        </div>
      )}

      {result && (
        <div className="space-y-4 pt-4 border-t border-theme-border">
          <div>
            <div className="flex items-center justify-between mb-1">
              <label className="text-sm font-medium text-theme-primary">Subject / Headline</label>
              <div className="flex gap-1">
                <button
                  onClick={() => handleCopy(result.subject)}
                  className="p-1 rounded hover:bg-theme-surface-hover text-theme-secondary"
                  title="Copy"
                >
                  <Copy className="w-3.5 h-3.5" />
                </button>
              </div>
            </div>
            <div className="p-3 rounded-lg bg-theme-surface text-sm text-theme-primary">
              {result.subject}
            </div>
          </div>

          <div>
            <div className="flex items-center justify-between mb-1">
              <label className="text-sm font-medium text-theme-primary">Body</label>
              <div className="flex gap-1">
                <button
                  onClick={() => handleCopy(result.body)}
                  className="p-1 rounded hover:bg-theme-surface-hover text-theme-secondary"
                  title="Copy"
                >
                  <Copy className="w-3.5 h-3.5" />
                </button>
                {onInsert && (
                  <button
                    onClick={() => onInsert(result.body)}
                    className="btn-theme btn-theme-secondary btn-theme-sm"
                  >
                    Insert
                  </button>
                )}
              </div>
            </div>
            <div className="p-3 rounded-lg bg-theme-surface text-sm text-theme-primary whitespace-pre-wrap">
              {result.body}
            </div>
          </div>

          {result.hashtags.length > 0 && (
            <div>
              <label className="text-sm font-medium text-theme-primary mb-1 block">Suggested Hashtags</label>
              <div className="flex gap-2 flex-wrap">
                {result.hashtags.map(tag => (
                  <span
                    key={tag}
                    className="px-2 py-1 rounded bg-theme-info bg-opacity-10 text-theme-info text-xs cursor-pointer hover:bg-opacity-20"
                    onClick={() => handleCopy(tag)}
                  >
                    {tag}
                  </span>
                ))}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
};
