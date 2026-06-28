import React, { useState, useEffect, useCallback } from 'react';
import { HelpCircle, GitBranch, ListChecks, StopCircle, Activity, Lock, Send } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Progress } from '@/shared/components/ui/Progress';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { campaignsApi } from '../api/campaignsApi';
import type { CampaignDetail, DriverKind } from '../types/campaign';
import { STATUS_CONFIG, DECISION_AUTHORITY_LABELS, DRIVER_KIND_OPTIONS, DRIVER_KIND_LABELS } from '../constants/campaign';

// Map a platform driver_kind to the target key its delegate call expects.
const TARGET_KEY: Partial<Record<DriverKind, string>> = {
  platform_agent: 'agent_id',
  platform_team: 'team_id',
  platform_mission: 'mission_id',
};

interface CampaignDetailModalProps {
  campaignId: string | null;
  isOpen: boolean;
  onClose: () => void;
  canManage: boolean;
  onChanged: () => void;
}

const TERMINAL = ['completed', 'archived'];

export const CampaignDetailModal: React.FC<CampaignDetailModalProps> = ({
  campaignId,
  isOpen,
  onClose,
  canManage,
  onChanged,
}) => {
  const [detail, setDetail] = useState<CampaignDetail | null>(null);
  const [loading, setLoading] = useState(false);
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState<string | null>(null);
  const [driverKind, setDriverKind] = useState<DriverKind>('claude_code');
  const [targetId, setTargetId] = useState('');
  const { addNotification } = useNotifications();

  const load = useCallback(async () => {
    if (!campaignId) return;
    setLoading(true);
    try {
      const response = await campaignsApi.getCampaign(campaignId);
      setDetail(response.data);
    } finally {
      setLoading(false);
    }
  }, [campaignId]);

  useEffect(() => {
    if (isOpen && campaignId) {
      setAnswers({});
      load();
    }
  }, [isOpen, campaignId, load]);

  const handleAnswer = async (questionId: string) => {
    if (!campaignId) return;
    const answer = (answers[questionId] || '').trim();
    if (!answer) return;
    setBusy(questionId);
    try {
      await campaignsApi.answerQuestion(campaignId, questionId, answer);
      await load();
      onChanged();
    } finally {
      setBusy(null);
    }
  };

  const handleStop = async () => {
    if (!campaignId) return;
    setBusy('stop');
    try {
      await campaignsApi.stopCampaign(campaignId, 'Stopped from dashboard');
      await load();
      onChanged();
    } finally {
      setBusy(null);
    }
  };

  const handleDelegate = async () => {
    if (!campaignId) return;
    const targetKey = TARGET_KEY[driverKind];
    if (targetKey && !targetId.trim()) {
      addNotification({ type: 'error', message: `A ${targetKey.replace('_', ' ')} is required for ${DRIVER_KIND_LABELS[driverKind]}` });
      return;
    }
    setBusy('delegate');
    try {
      const target = targetKey && targetId.trim() ? { [targetKey]: targetId.trim() } : {};
      await campaignsApi.delegateCampaign(campaignId, { driver_kind: driverKind, target });
      addNotification({ type: 'success', message: `Delegated to ${DRIVER_KIND_LABELS[driverKind]}` });
      await load();
      onChanged();
    } catch (err) {
      addNotification({ type: 'error', message: err instanceof Error ? err.message : 'Delegation failed' });
    } finally {
      setBusy(null);
    }
  };

  const statusConfig = detail ? (STATUS_CONFIG[detail.status] || { label: detail.status, variant: 'outline' as const }) : null;
  const isTerminal = detail ? TERMINAL.includes(detail.status) : false;

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={detail?.name || 'Campaign'}
      subtitle={detail?.description || undefined}
      size="3xl"
      footer={
        <div className="flex items-center justify-between">
          <span className="text-xs text-theme-tertiary">
            {detail && `${DECISION_AUTHORITY_LABELS[detail.decision_authority]} authority`}
          </span>
          <div className="flex gap-2">
            {canManage && detail && !isTerminal && (
              <Button variant="danger" size="sm" onClick={handleStop} loading={busy === 'stop'}>
                <StopCircle size={14} className="mr-1" />
                Stop Campaign
              </Button>
            )}
            <Button variant="ghost" onClick={onClose}>Close</Button>
          </div>
        </div>
      }
    >
      {loading || !detail ? (
        <div className="flex justify-center py-12"><LoadingSpinner /></div>
      ) : (
        <div className="space-y-6">
          {/* Header stats */}
          <div className="flex flex-wrap items-center gap-4">
            {statusConfig && <Badge variant={statusConfig.variant}>{statusConfig.label}</Badge>}
            {detail.driver_lease && (
              <Badge variant="outline" size="xs" className="flex items-center gap-1">
                <Lock className="h-3 w-3" />
                Driven by {detail.driver_lease.holder} · until {new Date(detail.driver_lease.expires_at).toLocaleTimeString()}
              </Badge>
            )}
            <div className="flex-1 min-w-[12rem]">
              <Progress value={detail.completion_pct} />
              <div className="mt-1 text-xs text-theme-secondary">{detail.completion_pct}% complete</div>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
            <Stat label="Loops" value={detail.loop_count} />
            <Stat label="Completed" value={detail.completed_tasks} tone="success" />
            <Stat label="Failed" value={detail.failed_tasks} tone={detail.failed_tasks > 0 ? 'error' : undefined} />
            <Stat label="Blocked" value={detail.blocked_tasks} tone={detail.blocked_tasks > 0 ? 'warning' : undefined} />
          </div>

          {/* Open questions */}
          <Section icon={HelpCircle} title={`Open Questions (${detail.open_questions_list.length})`}>
            {detail.open_questions_list.length === 0 ? (
              <p className="text-sm text-theme-secondary">No parked questions awaiting an answer.</p>
            ) : (
              <div className="space-y-3">
                {detail.open_questions_list.map((q) => (
                  <div key={q.id} className="rounded-md border border-theme bg-theme-surface-hover p-3">
                    <div className="text-sm font-medium text-theme-primary">{q.question}</div>
                    {q.context && <div className="mt-1 text-xs text-theme-secondary">{q.context}</div>}
                    {canManage && (
                      <div className="mt-2 flex items-end gap-2">
                        <Textarea
                          value={answers[q.id] || ''}
                          onChange={(e) => setAnswers((prev) => ({ ...prev, [q.id]: e.target.value }))}
                          placeholder="Answer to unblock the campaign…"
                          rows={2}
                          className="flex-1"
                        />
                        <Button
                          size="sm"
                          onClick={() => handleAnswer(q.id)}
                          loading={busy === q.id}
                          disabled={!(answers[q.id] || '').trim()}
                        >
                          Answer
                        </Button>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </Section>

          {/* Loops */}
          <Section icon={GitBranch} title={`Loops (${detail.loops.length})`}>
            {detail.loops.length === 0 ? (
              <p className="text-sm text-theme-secondary">No loops driven yet.</p>
            ) : (
              <div className="space-y-2">
                {detail.loops.map((l) => (
                  <div key={l.id} className="flex items-center justify-between rounded-md border border-theme px-3 py-2 text-sm">
                    <span className="font-mono text-theme-secondary">{l.branch || l.name}</span>
                    <span className="flex items-center gap-3 text-theme-secondary">
                      {l.driver_kind && (
                        <Badge variant="primary" size="xs">{DRIVER_KIND_LABELS[l.driver_kind]}</Badge>
                      )}
                      <Badge variant="outline" size="xs">{l.status}</Badge>
                      <span>{l.total_tasks} tasks</span>
                    </span>
                  </div>
                ))}
              </div>
            )}
          </Section>

          {/* Delegation: route the campaign's dev-loop to a driver (claude_code | platform_*) */}
          {canManage && !isTerminal && (
            <Section icon={Send} title="Delegate driver">
              <p className="mb-2 text-xs text-theme-secondary">
                Route this campaign's loop to a Claude Code session (dev-loop pull queue) or the
                platform executor. The single-driver lease enforces one active driver at a time.
              </p>
              <div className="flex flex-wrap items-end gap-2">
                <Select
                  value={driverKind}
                  options={DRIVER_KIND_OPTIONS}
                  onChange={(v) => setDriverKind(v as DriverKind)}
                  className="min-w-[12rem]"
                />
                {TARGET_KEY[driverKind] && (
                  <Input
                    value={targetId}
                    onChange={(e) => setTargetId(e.target.value)}
                    placeholder={`${TARGET_KEY[driverKind]?.replace('_', ' ')}…`}
                    className="min-w-[14rem] flex-1 font-mono"
                  />
                )}
                <Button size="sm" onClick={handleDelegate} loading={busy === 'delegate'}>
                  <Send size={14} className="mr-1" />
                  Delegate
                </Button>
              </div>
            </Section>
          )}

          {/* Decision log */}
          <Section icon={ListChecks} title={`Recent Decisions (${detail.recent_decisions.length})`}>
            {detail.recent_decisions.length === 0 ? (
              <p className="text-sm text-theme-secondary">No decisions recorded yet.</p>
            ) : (
              <div className="space-y-2">
                {detail.recent_decisions.map((d) => (
                  <div key={d.id} className="rounded-md border border-theme px-3 py-2">
                    <div className="flex items-center gap-2">
                      <Badge variant="secondary" size="xs">{d.decision_type}</Badge>
                      <span className="text-sm font-medium text-theme-primary">{d.title}</span>
                    </div>
                    {d.rationale && <div className="mt-1 text-xs text-theme-secondary">{d.rationale}</div>}
                  </div>
                ))}
              </div>
            )}
          </Section>

          {/* Unified activity feed (decisions + parked questions + completed tasks) */}
          <Section icon={Activity} title={`Activity (${detail.activity.length})`}>
            {detail.activity.length === 0 ? (
              <p className="text-sm text-theme-secondary">No activity yet.</p>
            ) : (
              <ul className="space-y-1.5">
                {detail.activity.map((e, i) => (
                  <li key={`${e.kind}-${e.at}-${i}`} className="flex items-center gap-2 text-sm">
                    <Badge variant="secondary" size="xs">{e.kind.replace('_', ' ')}</Badge>
                    <span className="text-theme-secondary">{e.status}</span>
                    <span className="truncate text-theme-primary">{e.title}</span>
                    <span className="ml-auto shrink-0 text-xs text-theme-tertiary">
                      {new Date(e.at).toLocaleString()}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </Section>
        </div>
      )}
    </Modal>
  );
};

const Stat: React.FC<{ label: string; value: number; tone?: 'success' | 'error' | 'warning' }> = ({ label, value, tone }) => {
  const toneClass =
    tone === 'success' ? 'text-theme-success-fg'
      : tone === 'error' ? 'text-theme-error-fg'
        : tone === 'warning' ? 'text-theme-warning-fg'
          : 'text-theme-primary';
  return (
    <div className="rounded-md border border-theme bg-theme-surface-hover p-3">
      <div className={`text-2xl font-semibold ${toneClass}`}>{value}</div>
      <div className="text-xs uppercase tracking-wider text-theme-tertiary">{label}</div>
    </div>
  );
};

const Section: React.FC<{ icon: React.ElementType; title: string; children: React.ReactNode }> = ({ icon: Icon, title, children }) => (
  <div>
    <h4 className="mb-2 flex items-center gap-2 text-sm font-semibold text-theme-primary">
      <Icon size={16} />
      {title}
    </h4>
    {children}
  </div>
);
