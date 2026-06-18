import React, { useEffect, useRef, useState } from 'react';
import { Sparkles, CheckCircle2, GitBranch, Terminal, Boxes } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import type { ProjectBrief, RuntimeHint } from './types';
import { REQUIRED_BRIEF_FIELDS } from './types';

export interface BriefCardProps {
  brief: ProjectBrief;
  /** Snake-case keys returned by `IntentCaptureService#missing_fields_for`. */
  missingFields: string[];
  className?: string;
}

const FIELD_LABELS: Record<string, string> = {
  intent: 'Intent',
  use_case: 'Use case',
  scale: 'Scale',
  regions: 'Regions',
  budget_cap_usd_monthly: 'Budget cap',
  compliance: 'Compliance',
  latency_targets_ms: 'Latency',
  data_residency: 'Data residency',
  preferred_provider: 'Preferred provider'
};

const FIELD_ORDER: string[] = [
  'intent',
  'use_case',
  'scale',
  'regions',
  'budget_cap_usd_monthly',
  'compliance',
  'latency_targets_ms',
  'data_residency',
  'preferred_provider'
];

/**
 * M3 — friendly display labels for the runtime_hint slug returned by the
 * planner. Mirrors the runtime allow-list in `Ai::Provisioning::BriefSchema`.
 */
const RUNTIME_LABELS: Record<RuntimeHint, string> = {
  node: 'Node.js',
  python: 'Python 3',
  ruby: 'Ruby',
  go: 'Go',
  docker: 'Docker',
  java: 'Java',
  none: 'None'
};

const APP_CODE_KEY = 'app_code';
const APP_CODE_FIELDS = ['repo_url', 'branch', 'start_command', 'runtime_hint'] as const;

const PULSE_DURATION_MS = 200;

const formatField = (key: string, value: unknown): string | null => {
  if (value === null || value === undefined || value === '') return null;
  switch (key) {
    case 'scale': {
      const scale = value as { initial?: number; target?: number; growth_profile?: string };
      if (!scale || (scale.initial == null && scale.target == null && !scale.growth_profile)) {
        return null;
      }
      const parts: string[] = [];
      if (scale.initial != null) {
        parts.push(`${scale.initial.toLocaleString()}→${scale.target?.toLocaleString() ?? '?'} users`);
      }
      if (scale.growth_profile) parts.push(scale.growth_profile);
      return parts.length ? parts.join(' · ') : null;
    }
    case 'budget_cap_usd_monthly':
      return typeof value === 'number'
        ? `$${value.toLocaleString(undefined, { maximumFractionDigits: 0 })}/mo`
        : String(value);
    case 'regions':
    case 'compliance':
    case 'data_residency':
      return Array.isArray(value) && value.length ? (value as string[]).join(', ') : null;
    case 'latency_targets_ms': {
      const lat = value as { p99?: number };
      return lat?.p99 != null ? `p99 ≤ ${lat.p99}ms` : null;
    }
    default:
      return typeof value === 'string' ? value : JSON.stringify(value);
  }
};

/**
 * Build a stable signature of the M3 application-code fields. Returns null
 * when all four fields are unset so the section pulses on appearance and
 * subsequent edits, but stays quiet when nothing about the code source has
 * changed.
 */
const formatAppCodeSignature = (brief: ProjectBrief): string | null => {
  const parts: string[] = [];
  if (brief.repo_url) parts.push(`repo:${brief.repo_url}`);
  if (brief.branch) parts.push(`branch:${brief.branch}`);
  if (brief.start_command) parts.push(`cmd:${brief.start_command}`);
  if (brief.runtime_hint) parts.push(`runtime:${brief.runtime_hint}`);
  return parts.length ? parts.join('|') : null;
};

/**
 * Returns the parsed URL when `value` is a valid http/https URL, otherwise
 * null. Used to decide whether to render the repo as a clickable link.
 */
const parseHttpUrl = (value: string | null | undefined): URL | null => {
  if (!value) return null;
  try {
    const u = new URL(value);
    if (u.protocol === 'https:' || u.protocol === 'http:') return u;
    return null;
  } catch {
    return null;
  }
};

/**
 * BriefCard — companion rail card for the concierge provisioning conversation.
 *
 * Renders the captured brief with placeholders for missing values. The
 * confidence pill flips from `Sketching…` to `Ready to plan` when none of
 * `REQUIRED_BRIEF_FIELDS` remain in `missingFields`. Updated fields ring with
 * `theme-info` for `PULSE_DURATION_MS` so operators can see the brief settle
 * as the LLM extracts new intent.
 *
 * M3 ("Run My Code") adds an optional "Application code" section rendered
 * only when at least one of `repo_url`/`branch`/`start_command`/`runtime_hint`
 * is set on the brief.
 */
export const BriefCard: React.FC<BriefCardProps> = ({ brief, missingFields, className = '' }) => {
  const ready = REQUIRED_BRIEF_FIELDS.every((field) => !missingFields.includes(field));

  const previousValues = useRef<Record<string, string | null>>({});
  const initialized = useRef(false);
  const [pulsing, setPulsing] = useState<Record<string, boolean>>({});

  useEffect(() => {
    const next: Record<string, string | null> = {};
    const triggered: string[] = [];
    Object.keys(FIELD_LABELS).forEach((key) => {
      const formatted = formatField(key, (brief as Record<string, unknown>)[key]);
      next[key] = formatted;
      if (
        initialized.current &&
        previousValues.current[key] !== formatted &&
        formatted !== null
      ) {
        triggered.push(key);
      }
    });

    // M3 — pulse the whole "Application code" section when any of its fields
    // change. Tracked under a synthetic `app_code` key so we don't have to
    // ring four sub-rows individually.
    const appCodeSignature = formatAppCodeSignature(brief);
    next[APP_CODE_KEY] = appCodeSignature;
    if (
      initialized.current &&
      previousValues.current[APP_CODE_KEY] !== appCodeSignature &&
      appCodeSignature !== null
    ) {
      triggered.push(APP_CODE_KEY);
    }

    previousValues.current = next;
    initialized.current = true;

    if (triggered.length === 0) return undefined;
    setPulsing((prev) => {
      const updated = { ...prev };
      triggered.forEach((k) => { updated[k] = true; });
      return updated;
    });
    const timer = setTimeout(() => {
      setPulsing((prev) => {
        const cleared = { ...prev };
        triggered.forEach((k) => { cleared[k] = false; });
        return cleared;
      });
    }, PULSE_DURATION_MS);
    return () => clearTimeout(timer);
  }, [brief]);

  const repoUrl = brief.repo_url ?? null;
  const branch = brief.branch ?? null;
  const startCommand = brief.start_command ?? null;
  const runtimeHint = brief.runtime_hint ?? null;
  const showAppCode = APP_CODE_FIELDS.some((field) => {
    const value = (brief as Record<string, unknown>)[field];
    return value !== null && value !== undefined && value !== '';
  });
  const appCodePulsing = !!pulsing[APP_CODE_KEY];
  const repoUrlParsed = parseHttpUrl(repoUrl);
  const runtimeLabel =
    runtimeHint && Object.prototype.hasOwnProperty.call(RUNTIME_LABELS, runtimeHint)
      ? RUNTIME_LABELS[runtimeHint]
      : runtimeHint;

  return (
    <Card variant="default" padding="md" className={className} data-testid="brief-card">
      <div className="flex items-center justify-between mb-3">
        <h4 className="text-sm font-semibold text-theme-primary">Project brief</h4>
        <span data-testid="brief-confidence-pill">
          {ready ? (
            <Badge variant="success" size="sm" icon={<CheckCircle2 className="w-3 h-3" />}>
              Ready to plan
            </Badge>
          ) : (
            <Badge variant="info" size="sm" icon={<Sparkles className="w-3 h-3" />}>
              Sketching…
            </Badge>
          )}
        </span>
      </div>
      <dl className="space-y-1.5">
        {FIELD_ORDER.map((key) => {
          const label = FIELD_LABELS[key];
          const value = formatField(key, (brief as Record<string, unknown>)[key]);
          const isMissing = missingFields.includes(key);
          const isRequired = (REQUIRED_BRIEF_FIELDS as readonly string[]).includes(key);
          const isPulsing = !!pulsing[key];
          return (
            <div
              key={key}
              data-testid={`brief-field-${key}`}
              className={`flex items-start justify-between gap-3 px-2 py-1.5 rounded transition-shadow ${
                isPulsing ? 'ring-2 ring-theme-info-fg bg-theme-info-fg/10' : ''
              }`}
            >
              <dt className="text-xs text-theme-secondary flex-shrink-0">
                {label}
                {isRequired && !value && (
                  <span className="text-theme-danger-fg ml-1" aria-label="required">*</span>
                )}
              </dt>
              <dd
                className={`text-xs text-right break-words min-w-0 ${
                  value ? 'text-theme-primary' : 'text-theme-tertiary italic'
                }`}
              >
                {value ?? (isMissing && isRequired ? '— required' : '—')}
              </dd>
            </div>
          );
        })}
      </dl>

      {showAppCode && (
        <section
          data-testid="brief-app-code"
          className={`mt-3 pt-3 border-t border-theme transition-shadow ${
            appCodePulsing ? 'ring-2 ring-theme-info-fg bg-theme-info-fg/10 rounded' : ''
          }`}
        >
          <h5 className="flex items-center gap-1.5 text-xs font-semibold text-theme-secondary mb-2">
            <GitBranch className="w-3 h-3 text-theme-info-fg" aria-hidden="true" />
            App code
          </h5>
          <dl className="space-y-1.5">
            {(repoUrl || branch) && (
              <div
                data-testid="brief-app-code-repo"
                className="flex items-start justify-between gap-3 px-2 py-1 rounded"
              >
                <dt className="text-xs text-theme-secondary flex-shrink-0">Repo</dt>
                <dd className="text-xs text-right break-all min-w-0 text-theme-primary">
                  {repoUrl ? (
                    repoUrlParsed ? (
                      <a
                        href={repoUrlParsed.toString()}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-theme-info-fg hover:underline"
                      >
                        {repoUrl}
                      </a>
                    ) : (
                      <span>{repoUrl}</span>
                    )
                  ) : (
                    <span className="text-theme-tertiary italic">—</span>
                  )}
                  {branch && (
                    <span className="text-theme-secondary ml-1">
                      branch: <span className="text-theme-primary">{branch}</span>
                    </span>
                  )}
                </dd>
              </div>
            )}
            {startCommand && (
              <div
                data-testid="brief-app-code-start"
                className="flex items-start justify-between gap-3 px-2 py-1 rounded"
              >
                <dt className="text-xs text-theme-secondary flex-shrink-0 flex items-center gap-1">
                  <Terminal className="w-3 h-3" aria-hidden="true" />
                  Start
                </dt>
                <dd className="text-xs text-right break-all min-w-0">
                  <code className="font-mono px-1.5 py-0.5 rounded bg-theme-background-secondary text-theme-primary">
                    {startCommand}
                  </code>
                </dd>
              </div>
            )}
            {runtimeHint && (
              <div
                data-testid="brief-app-code-runtime"
                className="flex items-start justify-between gap-3 px-2 py-1 rounded"
              >
                <dt className="text-xs text-theme-secondary flex-shrink-0">Runtime</dt>
                <dd className="text-xs text-right min-w-0">
                  <Badge variant="info" size="sm" icon={<Boxes className="w-3 h-3" />}>
                    {runtimeLabel}
                  </Badge>
                </dd>
              </div>
            )}
          </dl>
        </section>
      )}
    </Card>
  );
};

export default BriefCard;
