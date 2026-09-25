import { render, screen } from '@testing-library/react';
import { PhaseCard } from './PhaseCard';
import type { Mission } from '../../types/mission';

// fc-46 review, item 7: the "View in Execution Dashboard" link pointed at
// `/app/ai/execution?ralph_loop=<id>` — a query param nothing ever reads
// (RalphLoopsContent resolves the selected loop from the URL PATH, per its
// own `/app/ai/execution/loop/:loopId/:tab` scheme). Clicking it landed on
// the bare Ralph Loops list with no loop selected.
const MISSION: Mission = {
  id: 'mission-1',
  account_id: 'acct-1',
  name: 'Test Mission',
  description: null,
  mission_type: 'development',
  status: 'active',
  objective: null,
  current_phase: 'executing',
  phase_progress: 50,
  phases: ['analyzing', 'planning', 'executing'],
  phase_config: {},
  analysis_result: {},
  feature_suggestions: [],
  selected_feature: {},
  prd_json: {},
  test_result: {},
  review_result: {},
  phase_history: [],
  configuration: {},
  metadata: {},
  branch_name: null,
  base_branch: 'develop',
  pr_number: null,
  pr_url: null,
  deployed_port: null,
  deployed_url: null,
  deployed_container_id: null,
  error_message: null,
  error_details: {},
  repository_id: null,
  team_id: null,
  conversation_id: null,
  ralph_loop_id: 'loop-42',
  risk_contract_id: null,
  review_state_id: null,
  mission_template_id: null,
  custom_phases: null,
  approval_gate_phases: [],
} as unknown as Mission;

describe('PhaseCard "View in Execution Dashboard" link', () => {
  it('points at the loop\'s own path, not an unread ?ralph_loop= query param', () => {
    render(<PhaseCard mission={MISSION} events={[]} />);

    const link = screen.getByText('View in Execution Dashboard');
    expect(link).toHaveAttribute('href', '/app/ai/execution/loop/loop-42/tasks');
  });
});
