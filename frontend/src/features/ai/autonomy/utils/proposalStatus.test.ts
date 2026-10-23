import {
  PROPOSAL_STATUS_OPTIONS, proposalStatusLabel, proposalOutcomeNote, proposalHandoffLabel,
} from './proposalStatus';

describe('proposal status vocabulary', () => {
  it('offers expired in the status filter, distinct from withdrawn', () => {
    const values = PROPOSAL_STATUS_OPTIONS.map((o) => o.value);
    expect(values).toContain('expired');
    expect(values).toContain('withdrawn');
  });

  it('labels expired and withdrawn differently', () => {
    expect(proposalStatusLabel('expired')).toBe('Expired');
    expect(proposalStatusLabel('withdrawn')).toBe('Withdrawn');
    expect(proposalStatusLabel('pending_review')).toBe('Pending Review');
  });

  it('explains a lapse as a lapse, not a withdrawal', () => {
    expect(proposalOutcomeNote('expired')).toMatch(/deadline passed/);
    expect(proposalOutcomeNote('withdrawn')).toMatch(/filing agent withdrew/);
  });
});

describe('proposalHandoffLabel', () => {
  it('is null before approval hands anything off', () => {
    expect(proposalHandoffLabel(null)).toBeNull();
    expect(proposalHandoffLabel(undefined)).toBeNull();
  });

  it('marks an acknowledgement-only approval as having started nothing', () => {
    expect(
      proposalHandoffLabel({ kind: 'acknowledged', id: null, label: 'Acknowledged only: nothing was started', acknowledged_only: true })
    ).toMatch(/nothing was started/);
  });

  it('uses the server label for a real handoff', () => {
    expect(
      proposalHandoffLabel({ kind: 'dev_task', id: 't1', label: 'Queued as a dev-improve task', acknowledged_only: false })
    ).toBe('Queued as a dev-improve task');
  });
});
