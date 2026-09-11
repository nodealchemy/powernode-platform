import React, { useState } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotification } from '@/shared/hooks/useNotification';
import { logger } from '@/shared/utils/logger';
import { formatRelativeTimeCompact } from '@/shared/utils/formatters';
import {
  openInvestigation,
  InvestigationRefusedError,
} from '@/features/platform/status/api/platformStatusApi';
import type {
  Investigation,
  InvestigationEvidence,
  InvestigationHypothesis,
  InvestigationsData,
} from '@/shared/types/platformStatus';

// Evidence-first investigation (design §5.3, shapes from A9 §4.4/§4.5).
//
// ── `confidence` IS NULL WHEN NOTHING WAS MEASURED ─────────────────────────
//
// `confidence_state: "not_measured"` means the evidence set was EMPTY. That is a
// different answer from a confidence of 0, and the two are rendered differently
// here. `confidence ?? 0` would report certainty about nothing — a UI stating
// "0% confident" where the honest answer is "we had nothing to go on".
//
// ── HYPOTHESES ARE ALREADY RANKED ──────────────────────────────────────────
//
// The server stores them in order. This component renders them in that order and
// never re-sorts: a local sort would make the list disagree with the
// `conclusion` sentence rendered above it, and the operator would have no way to
// tell which one to believe.
//
// ── AN OPEN INVESTIGATION WITH NO HYPOTHESES IS CORRECT ────────────────────
//
// Ranking runs in the worker. "Open, with evidence, no hypotheses yet" is a real
// state, not a half-loaded one, and it is labelled as such rather than shown as
// an empty list that reads like a failure.
//
// ── EVIDENCE KEYS ARE NOT ALLOW-LISTED ─────────────────────────────────────
//
// One key per evidence class, and extensions add their own. Rendering only the
// classes core knows about would make an extension's evidence invisible — the
// exact failure this plane's genericity is designed to avoid. Anything under
// `errors` could not be checked AT ALL and is shown as a gap, never omitted: a
// class that silently vanished looks identical to a class that found nothing.

const INVESTIGATE_PERMISSION = 'ai.autonomy.manage';

/** Keys of the evidence object that are metadata rather than an evidence class. */
const EVIDENCE_META_KEYS = new Set(['assembled_at', 'window_seconds', 'errors', 'ranking']);

// ── RANKING IS NOT AN EVIDENCE CLASS (A6 re-verification G2) ────────────────
//
// `evidence.ranking` records why no AGENT ranked this investigation: refused
// by the security gate, an automatic trigger without a spend grant, a provider
// error. Listing it under "these classes could not be checked at all" was the
// wrong heading, and "No hypotheses yet. Ranking runs in the worker" was a
// promise the worker was never going to keep once a refusal was recorded as
// non-retryable. So it is rendered in its own block, switched on the stable
// `reason` token, with the server's `message` as prose beside it.

type RankingRecord = NonNullable<InvestigationEvidence['ranking']>;

/**
 * The ranking record, wherever this row carries it. The top-level field is on
 * every row; `evidence.ranking` only on rows that carry evidence (open ones).
 */
const rankingOf = (investigation: Investigation): RankingRecord | undefined =>
  investigation.ranking ?? investigation.evidence?.ranking ?? undefined;

/**
 * `evidence.errors.ranking` — how servers before the structured record said
 * ranking failed, and rows they wrote keep it. No retry fact came with it, so
 * none is claimed; it is shown as what it is and kept out of the evidence gap.
 */
const legacyRankingErrorOf = (investigation: Investigation): string | undefined => {
  const value = investigation.evidence?.errors?.ranking;
  return typeof value === 'string' && value ? value : undefined;
};

const RANKING_LEAD: Record<string, string | undefined> = {
  AutomaticSpendNeedsGrant:
    'Ranking was not run: automatic investigations need an agent-scoped spend grant. These hypotheses are the platform\u2019s own, derived without an agent.',
  SecurityGateRefused: 'Ranking did not run: the security gate refused it.',
  RankerUnusable: 'Ranking did not produce usable hypotheses.',
  ProviderError: 'Ranking failed: the AI provider returned an error.',
  NoPrincipal: 'Ranking did not run: no agent was available to run it.',
};

const RankingOutcome: React.FC<{ ranking: RankingRecord }> = ({ ranking }) => {
  const lead = RANKING_LEAD[ranking.reason] ?? 'Ranking did not complete.';
  // The automatic-spend case has a fixed sentence the server's prose would only
  // repeat; every other reason shows the recorded message verbatim.
  const showMessage = ranking.reason !== 'AutomaticSpendNeedsGrant' && Boolean(ranking.message);
  return (
    <div
      data-ranking-outcome
      data-ranking-reason={ranking.reason}
      className="mt-2 rounded border border-theme px-2 py-1"
    >
      <p className="text-xs text-theme-secondary">{lead}</p>
      {showMessage && <p className="text-xs text-theme-tertiary">{ranking.message}</p>}
      <p className="text-xs text-theme-tertiary">
        {ranking.retryable
          ? `It will be retried (${ranking.attempts} attempt${ranking.attempts === 1 ? '' : 's'} so far).`
          : 'It will not be retried.'}
      </p>
    </div>
  );
};

/**
 * The "no hypotheses" line, which must never promise an outcome that is not
 * coming. Only an OPEN investigation with NO ranking record is still waiting on
 * the worker.
 */
const emptyHypothesesText = (investigation: Investigation): string => {
  const ranking = rankingOf(investigation);
  if (ranking) {
    return ranking.retryable && investigation.open
      ? 'No hypotheses yet. Ranking will be retried.'
      : 'No hypotheses were produced.';
  }
  if (legacyRankingErrorOf(investigation)) {
    return investigation.open ? 'No hypotheses yet.' : 'No hypotheses were produced.';
  }
  return investigation.open
    ? 'No hypotheses yet. Ranking runs in the worker, so an open investigation normally has none until it completes.'
    : 'This investigation produced no hypotheses.';
};

const Confidence: React.FC<{ hypothesis: InvestigationHypothesis }> = ({ hypothesis }) => {
  if (hypothesis.confidence_state === 'not_measured' || hypothesis.confidence === null) {
    return (
      <Badge
        variant="outline"
        size="xs"
        className="border-dashed"
      >
        <span title="The evidence set was empty, so no confidence could be computed. This is not a confidence of zero.">
          not measured
        </span>
      </Badge>
    );
  }

  return (
    <Badge variant="info" size="xs">
      <span title={`Confidence ${hypothesis.confidence}, computed from the evidence classes listed.`}>
        {Math.round(hypothesis.confidence * 100)}% confident
      </span>
    </Badge>
  );
};

const EvidenceSummary: React.FC<{ evidence: InvestigationEvidence }> = ({ evidence }) => {
  const classes = Object.entries(evidence).filter(([key]) => !EVIDENCE_META_KEYS.has(key));
  // `ranking` is not an evidence class; a legacy row's ranking error is shown by
  // RankingSection, never under the gap heading below.
  const errors = Object.fromEntries(
    Object.entries(evidence.errors ?? {}).filter(([name]) => name !== 'ranking')
  );

  return (
    <div className="mt-2">
      <h5 className="text-xs uppercase tracking-wide text-theme-tertiary">Evidence</h5>
      {evidence.window_seconds !== undefined && (
        <p className="text-xs text-theme-tertiary">
          Assembled over the last {Math.round(evidence.window_seconds / 60)} minutes
          {evidence.assembled_at ? `, ${formatRelativeTimeCompact(evidence.assembled_at)}` : ''}.
        </p>
      )}

      <dl className="mt-1 grid grid-cols-[minmax(0,auto)_minmax(0,1fr)] gap-x-3 gap-y-1 text-xs">
        {classes.map(([name, value]) => {
          const count = Array.isArray(value) ? value.length : value === null ? 0 : 1;
          return (
            <React.Fragment key={name}>
              <dt className="font-mono text-theme-tertiary">{name}</dt>
              <dd className="text-theme-secondary">
                {count === 0 ? (
                  <span title="This class was checked and found nothing. Not the same as a class that could not be checked.">
                    checked, nothing found
                  </span>
                ) : (
                  `${count} item${count === 1 ? '' : 's'}`
                )}
              </dd>
            </React.Fragment>
          );
        })}
      </dl>

      {Object.keys(errors).length > 0 && (
        <div className="mt-2" data-evidence-errors>
          <p className="text-xs text-theme-warning-fg">
            These classes could not be checked at all — the investigation is working with a gap,
            not with a clean absence:
          </p>
          <dl className="mt-1 grid grid-cols-[minmax(0,auto)_minmax(0,1fr)] gap-x-3 gap-y-1 text-xs">
            {Object.entries(errors).map(([name, message]) => (
              <React.Fragment key={name}>
                <dt className="font-mono text-theme-tertiary">{name}</dt>
                <dd className="text-theme-secondary break-all">{message}</dd>
              </React.Fragment>
            ))}
          </dl>
        </div>
      )}
    </div>
  );
};

const RankingSection: React.FC<{ investigation: Investigation }> = ({ investigation }) => {
  const ranking = rankingOf(investigation);
  if (ranking) return <RankingOutcome ranking={ranking} />;
  const legacy = legacyRankingErrorOf(investigation);
  if (!legacy) return null;
  return (
    <div
      data-ranking-outcome
      data-ranking-reason="legacy"
      className="mt-2 rounded border border-theme px-2 py-1"
    >
      <p className="text-xs text-theme-secondary">Ranking did not run: {legacy}</p>
    </div>
  );
};

const InvestigationCard: React.FC<{ investigation: Investigation }> = ({ investigation }) => (
  <li
    data-investigation-status={investigation.status}
    className="rounded-md border border-theme p-3"
  >
    <div className="flex flex-wrap items-center gap-2">
      <Badge variant={investigation.open ? 'primary' : 'secondary'} size="xs">
        {investigation.status}
      </Badge>
      <span className="text-xs text-theme-tertiary" title="What caused this investigation to start.">
        triggered by {investigation.trigger}
      </span>
      <span className="text-xs text-theme-tertiary" title={`Started at ${investigation.started_at}.`}>
        started {formatRelativeTimeCompact(investigation.started_at)}
      </span>
    </div>

    {investigation.conclusion && (
      <p className="mt-2 text-sm text-theme-primary">{investigation.conclusion}</p>
    )}

    <RankingSection investigation={investigation} />

    {investigation.hypotheses.length === 0 ? (
      <p className="mt-2 text-xs text-theme-secondary">{emptyHypothesesText(investigation)}</p>
    ) : (
      <ol className="mt-2 flex flex-col gap-2">
        {/* Rendered in the stored order. Do not sort. */}
        {investigation.hypotheses.map((hypothesis, index) => (
          <li key={`${hypothesis.cause}-${index}`} className="rounded border border-theme px-2 py-1">
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-sm text-theme-primary">{hypothesis.cause}</span>
              <Confidence hypothesis={hypothesis} />
            </div>
            {hypothesis.evidence_refs.length > 0 && (
              <p className="text-xs text-theme-tertiary">
                from {hypothesis.evidence_refs.join(', ')}
              </p>
            )}
            {hypothesis.recommended_action_category && (
              <p className="text-xs text-theme-tertiary">
                suggested lane <code>{hypothesis.recommended_action_category}</code>
              </p>
            )}
          </li>
        ))}
      </ol>
    )}

    {investigation.evidence && <EvidenceSummary evidence={investigation.evidence} />}
  </li>
);

export interface InvestigationsTabProps {
  data: InvestigationsData | null;
  loading: boolean;
  componentStatusId: string;
  /**
   * Called when the POST STARTS; returns the re-read to run once it lands. The
   * returned function is bound to this component, so a drawer that moved on in
   * between never shows this investigation under the next component's name
   * (C3p2 review R1).
   */
  beginRefresh?: () => () => void;
}

export const InvestigationsTab: React.FC<InvestigationsTabProps> = ({
  data,
  loading,
  componentStatusId,
  beginRefresh,
}) => {
  const { hasPermission } = usePermissions();
  const { showNotification } = useNotification();
  const [starting, setStarting] = useState(false);

  const mayInvestigate = hasPermission(INVESTIGATE_PERMISSION);

  const start = async () => {
    setStarting(true);
    // Taken BEFORE the POST, so the re-read is bound to this component.
    const refreshAfterOpen = beginRefresh?.();
    try {
      await openInvestigation(componentStatusId);
      showNotification('Investigation opened.', 'success');
      refreshAfterOpen?.();
    } catch (e) {
      if (e instanceof InvestigationRefusedError) {
        // A BOUND, not a failure — and the two refusals need different
        // sentences. Switched on the token, never on the message.
        const message =
          e.refused === 'DailyCapReached'
            ? `The daily investigation cap${e.dailyCap ? ` of ${e.dailyCap}` : ''} has been reached. Try again tomorrow.`
            : e.refused === 'AlreadyOpen'
              ? 'An investigation of this component is already open — see it above.'
              : e.message;
        showNotification(message, 'warning');
      } else {
        const message = e instanceof Error ? e.message : 'The investigation could not be started.';
        showNotification(`Investigation failed: ${message}`, 'error');
        logger.error('[PlatformStatus] investigation failed', e);
      }
    } finally {
      setStarting(false);
    }
  };

  if (loading && !data) {
    return <p className="text-sm text-theme-secondary">Loading investigations…</p>;
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-xs text-theme-tertiary">
          {data
            ? `${data.open.length} open, ${data.recent.length} recent. Daily cap ${data.daily_cap}.`
            : 'Investigations could not be read.'}
        </p>
        {mayInvestigate ? (
          <Button variant="secondary" size="sm" onClick={() => void start()} disabled={starting}>
            {starting ? 'Starting…' : 'Investigate'}
          </Button>
        ) : (
          // Said, not silently omitted: an operator who cannot start one should
          // know the capability exists and who to ask, rather than concluding
          // the platform has no such feature.
          <p className="text-xs text-theme-tertiary">
            Starting an investigation needs <code>{INVESTIGATE_PERMISSION}</code>.
          </p>
        )}
      </div>

      {data && data.open.length === 0 && data.recent.length === 0 && (
        <p className="text-sm text-theme-secondary">
          Nothing has been investigated. That means no investigation was run, not that nothing was
          found.
        </p>
      )}

      {data && data.open.length > 0 && (
        <section data-investigation-section="open">
          <h4 className="mb-1 text-xs uppercase tracking-wide text-theme-tertiary">Open</h4>
          <ul className="flex flex-col gap-2">
            {data.open.map((investigation) => (
              <InvestigationCard key={investigation.id} investigation={investigation} />
            ))}
          </ul>
        </section>
      )}

      {data && data.recent.length > 0 && (
        <section data-investigation-section="recent">
          <h4 className="mb-1 text-xs uppercase tracking-wide text-theme-tertiary">Recent</h4>
          <ul className="flex flex-col gap-2">
            {data.recent.map((investigation) => (
              <InvestigationCard key={investigation.id} investigation={investigation} />
            ))}
          </ul>
        </section>
      )}
    </div>
  );
};

export default InvestigationsTab;
