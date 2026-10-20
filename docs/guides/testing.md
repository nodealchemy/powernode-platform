# Testing Guide

> How to write and run automated and manual tests across the Powernode platform's backend, frontend, and AI surfaces.

> Status: active

## Table of Contents

- [What this guide covers](#what-this-guide-covers)
- [Prerequisites](#prerequisites)
- [Test pyramid](#test-pyramid)
- [Running tests](#running-tests)
- [Backend testing (RSpec)](#backend-testing-rspec)
- [Worker job specs](#worker-job-specs)
- [Frontend testing (Jest + RTL)](#frontend-testing-jest--rtl)
- [Manual AI testing playbooks](#manual-ai-testing-playbooks)
- [Concurrency and isolation](#concurrency-and-isolation)
- [CI integration](#ci-integration)
- [Related guides](#related-guides)
- [Materials previously at](#materials-previously-at)

## What this guide covers

This guide is for engineers writing or running automated tests (RSpec, Jest, Testing Library) and operators running manual AI smoke tests against a live platform. It covers the canonical patterns: factories, request specs, worker job specs, component tests, mocking strategies, and the AI-functionality manual test playbooks.

For end-to-end browser tests, see the separate [`docs/guides/e2e-testing.md`](e2e-testing.md). For test patterns specific to a feature area, see the relevant area guide.

## Prerequisites

- Local dev environment per [`docs/getting-started/01-quickstart.md`](../getting-started/01-quickstart.md)
- All systemd services healthy (`sudo scripts/systemd/powernode-installer.sh status`)
- For AI manual playbooks: at least one configured provider (Ollama or remote) and an agent
- Familiarity with backend ([`docs/guides/backend.md`](backend.md)) and frontend ([`docs/guides/frontend.md`](frontend.md)) conventions

## Test pyramid

```mermaid
flowchart TB
    E2E[E2E Tests Playwright - slow, full system]
    Manual[Manual AI Playbooks live exploratory]
    Int[Integration / Request Specs RSpec + axios mocks]
    Unit[Unit Tests RSpec models, Jest components, hooks]
    Static[Static Checks tsc --noEmit, rubocop, lint]

    Static --> Unit
    Unit --> Int
    Int --> E2E
    Int -.-> Manual
```

Run thousands of unit tests cheaply, hundreds of request/component tests, dozens of E2E flows, and a small number of manual AI playbook walkthroughs per release. Static checks (TypeScript, Ruby syntax) gate every commit.

## Running tests

### Backend RSpec

> **Never run rspec in a shell that sourced the unit env** (`~/.config/powernode/backend-default.conf`, `/etc/powernode/*.conf`, or anything exporting `RAILS_ENV=development` / `DATABASE_*`). The suite's `before(:suite)` deletes every row of the database it is connected to. `spec/rails_helper.rb` fails closed: it aborts before Rails loads if `RAILS_ENV`/`RACK_ENV` is set to anything but `test`, and after Rails loads aborts unless `Rails.env.test?` and the database name contains `test` (parallel lanes `powernode_test__p<N>` and `powernode_test_<suffix>` qualify). If you hit that abort, open a clean shell; do not work around it. Covered by `spec/scripts/rails_helper_env_guard_spec.rb`.

```bash
cd server

# Full suite — use --format json for parseable output, never tail
bundle exec rspec --format json > /tmp/rspec.json 2>&1

# Single file
bundle exec rspec spec/models/account_spec.rb

# Single example
bundle exec rspec spec/models/account_spec.rb:42

# By tag
bundle exec rspec --tag focus
```

**Never** pipe `rspec` through `tail` — output is lost and you miss the structured failure data.

### Frontend Jest

```bash
cd frontend
CI=true npm test                                            # full suite
CI=true npm test -- src/features/widgets/__tests__/Widget.test.tsx
CI=true npm test -- --watch                                 # interactive
```

`CI=true` disables watch mode and ensures deterministic output.

### TypeScript check

```bash
cd frontend && npx tsc --noEmit
```

Run this **before every commit** that touches TypeScript.

### Ruby syntax check

```bash
cd server && bundle exec ruby -c app/path/to/file.rb
```

### Fast test database (optional tmpfs cluster)

By default test databases live on the shared system Postgres (port 5432), which fsyncs every
commit; several worktrees preparing or running at once contend for the same disk. An optional,
unprivileged, test-only PG16 cluster keeps its data directory in RAM (`/dev/shm`) with
`fsync`, `synchronous_commit` and `full_page_writes` off. Nothing changes for a checkout that
does not opt in.

```bash
scripts/test-pg-tmpfs.sh start     # once per boot; idempotent (initdb on first run, port 5433)
scripts/test-pg-tmpfs.sh status    # exit 0 running, 3 stopped
scripts/test-pg-tmpfs.sh stop      # keeps the data; `destroy` deletes it
```

Opt a worktree in with `scripts/prepare-worktree.sh <path> --tmpfs-pg` (or `TEST_PG_TMPFS=1` in the environment; it writes
`DATABASE_PORT=5433` to `server/.env.test.local` only when the cluster is running), or add that
line by hand. `database.yml` reads `DATABASE_PORT`, then `PGPORT`, then defaults to 5432. Then build the lane DB
as usual: `scripts/prepare-extension-test-db.sh`. It asks Rails which database and port it will use
(the source of truth), aborts if a `DATABASE_PORT` in the environment or dotenv disagrees, and points its
`psql`/`createdb`/`dropdb` calls at the same cluster. Tmpfs mode is detected from the cluster's live
unix socket, not from the port number. The global prep I/O lock is kept but is per cluster (a separate
lock file for the tmpfs port), so tmpfs preps serialise among themselves without queueing behind the
shared cluster's preps.

- **Data is disposable.** The cluster is crash-unsafe by design and is gone after a reboot (or if
  `/dev/shm` is cleaned): run `start` again, then re-run `prepare-extension-test-db.sh` for each lane.
- **Settings** (override with `TEST_PG_DIR`, `TEST_PG_PORT`, `TEST_PG_BIN`): `shared_buffers=256MB`,
  `max_connections=200`, `max_locks_per_transaction=256` (the suite's cleanup touches hundreds of tables).
- **RAM:** roughly 100 MB per lane DB plus WAL; four lanes fit well under 4 GB. `start` refuses
  to initialise with under 3 GB free.
- **Role.** `powernode` is created as a superuser, matching the shared cluster: the suite needs it
  (`session_replication_role` in specs, `DISABLE TRIGGER ALL` in DatabaseCleaner). The cluster listens
  on loopback only, but on a multi-user host any local user can reach that port with the well-known
  default password, so set `POWERNODE_DATABASE_PASSWORD` there. The prep script connects its own
  `psql`/`createdb` as `powernode` too (`PGUSER`), so the databases it builds are owned by the app role.
- **Cleanup.** `prepare-worktree.sh --remove` / `wt.sh` drop the worktree's lane database on port 5432
  only (they do not read `DATABASE_PORT`), so a tmpfs-opted worktree leaves its lane DB in RAM. Drop it
  with `dropdb -h "${TEST_PG_DIR:-/dev/shm/powernode-test-pg16}" -p 5433 powernode_test_<lane>`, or `scripts/test-pg-tmpfs.sh destroy`
  to drop everything.
- A worktree made with `--isolated-db` copies `database.yml` at creation; one copied before the `port:`
  line existed needs `port: <%= ENV.fetch("DATABASE_PORT") { ENV.fetch("PGPORT", 5432) } %>` added by hand.
- `status`, `stop` and `destroy` never touch port 5432. `stop` refuses while a prep script holds
  its lock unless `--force`.

### Parallel runs (opt-in)

`scripts/parallel-rspec.sh` runs `server/spec` plus the public extensions' specs
(`extensions/{system,marketing,supply-chain}/server/spec`) in N processes. **Every process owns a Postgres
database (`powernode_test__p1`..`__pN`) and a Redis lane**, which is what makes it safe where "two rspec
processes at once" is not: nothing is shared but the filesystem. A plain `bundle exec rspec`, a worktree
lane and CI never see any of it.

```bash
scripts/test-pg-tmpfs.sh start                 # the parallel run refuses the shared 5432 cluster
DATABASE_PORT=5433 scripts/parallel-rspec.sh   # starts the test Redis, preps lanes, runs, then the serial tail
DATABASE_PORT=5433 scripts/parallel-rspec.sh --check          # guard + the N it would use; starts nothing (it prunes dead entries in, and may create, the lane ledger)
DATABASE_PORT=5433 scripts/parallel-rspec.sh -n 4 -- spec/models   # fixed N, chosen paths
DATABASE_PORT=5433 VALIDATE_PARALLEL=auto scripts/validate.sh      # platform spec pass of the gate (extensions stay serial)
```

- **Lanes.** `parallel_tests` numbers its processes `""`, `2`, `3`...; those would land on the worktrees'
  `powernode_test2/3/4`. `spec/parallel_lane_env.rb` (loaded by `server/.rspec_parallel` before Rails)
  renames each process to `TEST_ENV_NUMBER=__pK` and `TEST_REDIS_LANE=TEST_REDIS_LANE_BASE+K-1`. It does nothing unless
  `parallel_tests` started the process, and it refuses a missing or `5432` `DATABASE_PORT` and a missing
  `TEST_REDIS_PORT`.
- **Redis.** The shared daemon has 16 databases = 6 lanes, which worktrees hold. `scripts/test-redis.sh`
  runs a second, loopback-only, no-persistence daemon (default port 6380, 64 databases = 30 lanes;
  `start|stop|status`, data under `/dev/shm/powernode-test-redis`). The suite finds it through
  `TEST_REDIS_PORT` / `TEST_REDIS_DATABASES` (`config/initializers/redis.rb`); unset, nothing changes.
  The shared Redis is never touched. The test daemon's default user is ACL-guarded: FLUSHALL, CONFIG SET,
  SHUTDOWN, DEBUG, MONITOR, ACL and similar instance-wide commands answer NOPERM (FLUSHDB, INFO, CONFIG GET stay
  allowed), `stop` sends SIGTERM to the verified pid, and a daemon started before the guard needs `stop` then
  `start` to pick it up (`start` warns when it finds one).
- **DB prep.** `prepare-extension-test-db.sh --lanes "__p1 __p2 ..."` resolves the cluster once, builds a
  golden template if its fingerprint is stale (`--lanes` in core mode has its own golden, `powernode_test_golden_core`, tmpfs cluster only; the serial core default is unchanged; two preps racing to rebuild one golden is a pre-existing property of the design), then every
  lane is a `CREATE DATABASE ... TEMPLATE` clone under the per-cluster lock: about 5 s for 8 lanes, versus
  8-10 s per lane before. Lane names are validated as `__p<N>` or `__w<6 hex>p<N>` before anything reaches `dropdb`.
- **How many processes.** Computed live, no fixed cap: `N = min(cores, (MemAvailable - reserve) / per-process
  memory, free Redis lanes, (max_connections - 3 - in use) / connections per process)`; the limiting factor
  is printed. Defaults (all overridable): `PARALLEL_RSS_MB=2000` (measured steady peak ~1 GB per process after ~8k examples, growing ~65 MB per 1k examples; a one-off transient of 6.8 GB was seen in a single process, so this is a planning figure, not a ceiling),
  `PARALLEL_DB_MB=80` (per-process memory in the formula is RSS + DB MB), `PARALLEL_MEM_RESERVE_MB=2048` (the effective reserve is at least 7000 + the test Redis maxmemory: one process's observed transient spike plus Redis), `PARALLEL_PG_CONNS=4` (measured: 14 connections for 8 processes, ~1.75 each). `-n N` / `PARALLEL_N`
  overrides (still capped by Redis lanes). `MemAvailable` is read at start, so more RAM raises N. A bound that computes to 0 (memory below the reserve, Postgres unreachable) is a refusal, never one process anyway.
- **Worktrees.** Each checkout has its own lane namespace: the main checkout `__p` (databases
  `powernode_test__p1..N`), any other git worktree `__w<6 hex of sha1(path)>p`; `PARALLEL_LANE_PREFIX` overrides
  (only those two shapes are accepted, since lane names reach `dropdb`). Redis lanes are claimed as a contiguous
  range from a ledger (`<TEST_REDIS_DIR>/lanes.ledger`, released on exit, dead pids pruned). A 64-database
  daemon has 30 lanes, shared by every concurrent run: a second run is sized to the lanes still free (N shrinks,
  "redis" becomes the limiting factor) and refuses to start at 0, so two full-width runs cannot overlap (30 lanes
  = two 15-process runs, or sixteen plus fourteen). Raise `TEST_REDIS_DATABASES` for more. One prefix runs once at
  a time. `--check` prints the namespace and the Redis range.
- **Redis memory.** `scripts/test-redis.sh` sets `maxmemory` to ~10% of RAM (min 2 GB, `TEST_REDIS_MAXMEMORY_MB`),
  `noeviction`: a full run peaks near 1.5 GB (embedding-cache keys), and an OOM error must stay loud.
- **Serial tail.** `scripts/parallel-serial-tail.txt` lists specs that share state across processes
  (`truncation: true`, fixed names under `Rails.root/tmp`, the real `config/extensions_state.json`). They run
  afterwards in one process on lane `__p1`. `spec/lint/parallel_serial_tail_spec.rb` fails when a new spec
  matching those shapes is not listed.
- **Signals.** The wrapper runs each phase as its own process group (`setsid`) and traps INT, TERM, HUP and QUIT:
  it TERMs the whole group, waits for it, escalates to KILL if the group ignores TERM for `PARALLEL_KILL_AFTER`
  seconds (default 30), and only then releases the Redis ledger. `setsid` is required.
- **Balancing and output.** Files are balanced by recorded runtimes (`server/tmp/parallel_runtime_rspec.log`,
  rewritten by each full run; the first run balances by file size. A subset run (explicit paths) keeps and restores the full log, and files missing from a log are tolerated via `--allowed-missing 100`). Failures are collected in
  `server/tmp/parallel_failures.log` and `server/tmp/serial_tail_failures.log`; exit status is non-zero when
  either phase failed. CI keeps its own 6 file-balanced shards and is unchanged.
- **After a reboot** `/dev/shm` is empty: `scripts/test-pg-tmpfs.sh start`; the wrapper restarts the test Redis
  and rebuilds the lanes itself.
- **Tuning knobs** `PARALLEL_STATS=<file>` samples per-process RSS, `MemAvailable` and PG connections every 5 s.

### Targeted vs. full suite

The full backend suite is slow. Run only the specs touching the files you changed during development. The full suite runs in CI on every PR.

## Backend testing (RSpec)

### Project layout

```
server/spec/
├── factories/                          # FactoryBot
│   ├── accounts.rb
│   ├── users.rb
│   ├── ai/                             # namespaced factories
│   └── ...
├── models/                             # model specs
├── requests/                           # request specs (per-controller)
│   └── api/v1/
├── services/                           # service object specs
├── support/                            # shared examples, helpers, matchers
│   ├── shared_examples/
│   ├── ai_matchers.rb
│   ├── ai_test_helpers.rb
│   └── permission_test_helpers.rb
├── spec_helper.rb
└── rails_helper.rb
```

### Factories

Use FactoryBot for all test data. Each factory should support traits for common state variants:

```ruby
# spec/factories/widgets.rb
FactoryBot.define do
  factory :widget do
    account
    user
    sequence(:name) { |n| "Widget #{n}" }
    status { 'active' }

    trait :archived  do; status { 'archived' };  end
    trait :paused    do; status { 'paused' };    end
    trait :with_logs do
      after(:create) { |w| create_list(:widget_log, 3, widget: w) }
    end
  end
end

# Usage
let(:widget) { create(:widget, :archived, account: account) }
```

### User and permission setup

Use `permission_test_helpers.rb`:

```ruby
let(:user)    { user_with_permissions('widgets.view', 'widgets.create') }
let(:headers) { auth_headers_for(user) }
```

Never create users manually in specs — the helpers ensure permissions are properly assigned through roles, which exercises the full access-control chain.

### Request specs

```ruby
require 'rails_helper'

RSpec.describe 'Widgets API', type: :request do
  let(:account) { create(:account) }
  let(:user)    { user_with_permissions('widgets.view', 'widgets.create', account: account) }
  let(:headers) { auth_headers_for(user) }

  describe 'GET /api/v1/widgets' do
    let!(:widget) { create(:widget, account: account) }

    it 'returns widgets scoped to the user account' do
      get '/api/v1/widgets', headers: headers

      expect_success_response
      expect(json_response_data.size).to eq(1)
      expect(json_response_data.first['id']).to eq(widget.id)
    end

    include_examples 'requires authentication'
    include_examples 'requires permission', 'widgets.view'
    include_examples 'scopes to current account'
  end

  describe 'POST /api/v1/widgets' do
    let(:params) { { widget: { name: 'New Widget' } } }

    it 'creates a widget' do
      expect { post '/api/v1/widgets', params: params, headers: headers }
        .to change(Widget, :count).by(1)
      expect(response).to have_http_status(:created)
    end

    it 'returns validation errors on invalid input' do
      post '/api/v1/widgets', params: { widget: { name: '' } }, headers: headers
      expect_error_response('Validation failed', :unprocessable_entity)
    end
  end
end
```

### Shared examples

| Example | Verifies |
|---|---|
| `'requires authentication'` | Endpoint returns 401 without a valid JWT |
| `'requires permission', 'foo.bar'` | Endpoint returns 403 when user lacks the named permission |
| `'scopes to current account'` | Endpoint never returns rows from another account |
| `'paginated'` | Endpoint accepts `?page=` and `?per_page=` and returns `meta.pagination` |
| `'returns standard envelope'` | Response is `{ success: bool, data?, error?, meta? }` |

Include the examples after your endpoint-specific tests. They are zero-cost coverage — the chronic regressions they catch (auth bypass, cross-account leak) are catastrophic.

### Response helpers

| Helper | Purpose |
|---|---|
| `json_response` | Parsed response body |
| `json_response_data` | `json_response['data']` |
| `expect_success_response(data = nil)` | Asserts `success: true` and optional data |
| `expect_error_response(msg, status)` | Asserts `success: false`, message, and status |

### Model specs

Test the public surface: validations, scopes, instance methods, callback side effects. Don't test ActiveRecord internals.

```ruby
RSpec.describe Widget, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[active archived paused]) }
  end

  describe '.active scope' do
    let!(:active)   { create(:widget) }
    let!(:archived) { create(:widget, :archived) }

    it 'returns only active widgets' do
      expect(Widget.active).to contain_exactly(active)
    end
  end

  describe '#archive!' do
    let(:widget) { create(:widget) }

    it 'flips status and stamps archived_at' do
      expect { widget.archive! }.to change(widget, :status).from('active').to('archived')
      expect(widget.archived_at).to be_within(1.second).of(Time.current)
    end
  end
end
```

### Service specs

Test the success and failure paths of your service object:

```ruby
RSpec.describe Widgets::CreateService do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }

  context 'with valid params' do
    let(:result) { described_class.call(account: account, user: user, name: 'Foo') }

    it { expect(result).to be_success }
    it { expect(result.data[:widget]).to be_a(Widget) }
  end

  context 'with invalid params' do
    let(:result) { described_class.call(account: account, user: user, name: '') }

    it { expect(result).to be_failure }
    it { expect(result.error).to eq('Validation failed') }
  end
end
```

### AI matchers and helpers

For specs touching the AI subsystem:

| Matcher / Helper | Use |
|---|---|
| `be_a_valid_ai_response` | Asserts response shape (data, citations, finish_reason) |
| `have_execution_status(:status)` | Asserts agent execution status |
| `create_audit_log(:action)` | Asserts an `AuditLog` entry was created (optionally matching `action`) |
| `ProviderHelpers`, `AgentHelpers`, `ConversationHelpers`, `SecurityHelpers` | Setup helpers — see `spec/support/ai_test_helpers.rb` |

## Worker job specs

The worker is a separate process. Its specs live in `worker/spec/` and use Sidekiq's test mode:

```ruby
# worker/spec/jobs/widget_dispatch_job_spec.rb
require 'spec_helper'

RSpec.describe WidgetDispatchJob do
  subject { described_class }  # required for shared examples
  let(:job_args) { { 'widget_id' => 'widget-uuid' } }

  it_behaves_like 'a base job'

  describe '#execute' do
    before do
      stub_backend_api_success(:post, '/widgets/widget-uuid/dispatch', { 'dispatched' => true })
    end

    it 'calls the dispatch endpoint via api_client' do
      described_class.new.execute(job_args)
      expect_api_request(:post, '/widgets/widget-uuid/dispatch')
    end

    it 'raises on api failure to trigger retry' do
      stub_backend_api_error(:post, '/widgets/widget-uuid/dispatch', status: 500, error_message: 'boom')
      expect { described_class.new.execute(job_args) }.to raise_error(BackendApiClient::ApiError)
    end
  end
end
```

Notes:

- `subject { described_class }` and `let(:job_args)` are required by the shared examples.
- Never reach into ActiveRecord in worker specs — stub the API surface instead.

## Frontend testing (Jest + RTL)

### Setup

```javascript
// jest.config.js
/** @type {import('jest').Config} */
module.exports = {
  testEnvironment: 'jsdom',
  setupFilesAfterEnv: ['<rootDir>/src/setupTests.ts'],
  // Transforms via babel-jest (NOT ts-jest):
  transform: {
    '^.+\\.(js|jsx|ts|tsx)$': ['babel-jest', {
      presets: ['@babel/preset-env', '@babel/preset-react', '@babel/preset-typescript'],
    }],
  },
  moduleNameMapper: {
    '^@/shared/(.*)$': '<rootDir>/src/shared/$1',
    '\\.(css|scss)$': 'identity-obj-proxy',
  },
};
```

### Component testing pattern

```typescript
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Provider } from 'react-redux';
import { WidgetCard } from '../components/WidgetCard';
import { makeStore } from '@/app/store';

const renderWithProviders = (ui: React.ReactElement) => {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <Provider store={makeStore()}>
      <QueryClientProvider client={qc}>{ui}</QueryClientProvider>
    </Provider>,
  );
};

describe('WidgetCard', () => {
  const widget = { id: '1', name: 'Foo', status: 'active' };

  it('renders the widget name', () => {
    renderWithProviders(<WidgetCard widget={widget} />);
    expect(screen.getByText('Foo')).toBeInTheDocument();
  });

  it('hides Edit button when user lacks widgets.update permission', () => {
    renderWithProviders(<WidgetCard widget={widget} />);
    expect(screen.queryByRole('button', { name: /edit/i })).not.toBeInTheDocument();
  });

  it('shows Edit button when user has permission', async () => {
    // Set permissions via the Redux store helper
    renderWithProviders(<WidgetCard widget={widget} />, { permissions: ['widgets.update'] });
    expect(screen.getByRole('button', { name: /edit/i })).toBeInTheDocument();
  });
});
```

### Test rules

- **Query by role first**, then by label, then by test-id. Avoid querying by class or by raw text when accessible alternatives exist.
- **Use `userEvent`**, not `fireEvent`, for interactions — it triggers the events a real user would in the correct order.
- **Wrap with providers** that match production — the test fails to surface React Query, Redux, or Theme-related bugs otherwise.
- **Mock API calls** through MSW or by stubbing `axios` directly; don't hit real endpoints.
- **No snapshot soup**. Targeted assertions beat 500-line snapshots — they describe intent.

### Hook testing

```typescript
import { renderHook, waitFor } from '@testing-library/react';
import { useWidget } from '../hooks/useWidget';

describe('useWidget', () => {
  it('returns the widget when fetched', async () => {
    const { result } = renderHook(() => useWidget('widget-1'), {
      wrapper: ({ children }) => <QueryClientProvider client={new QueryClient()}>{children}</QueryClientProvider>,
    });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data?.name).toBe('Foo');
  });
});
```

### Accessibility tests

Use `@axe-core/react` or `jest-axe` for automated a11y checks:

```typescript
import { axe, toHaveNoViolations } from 'jest-axe';
expect.extend(toHaveNoViolations);

it('has no a11y violations', async () => {
  const { container } = renderWithProviders(<WidgetForm />);
  expect(await axe(container)).toHaveNoViolations();
});
```

See [`docs/guides/accessibility.md`](accessibility.md) for the full standards.

## Manual AI testing playbooks

Some AI surfaces are too dynamic or too costly to fully automate. The platform maintains two living manual test playbooks for them:

### Backend playbook

Comprehensive backend coverage across the AI subsystem — providers, agents, missions, teams, ralph loops, memory, autonomy, RAG, knowledge graph, model routing.

**Prerequisites:**

- Dev environment running (`sudo systemctl start powernode.target`)
- Ollama (or remote) provider configured and healthy
- At least one configured agent

**Scope summary:**

| Area | Covers |
|---|---|
| Agent system | Agent lifecycle, trust scores, performance, budget |
| Missions | Mission creation, decomposition, approval, execution |
| Teams | Team composition, member roles, execution orchestration |
| Ralph loops | Recurring task loops, iteration tracking, pause/resume |
| Memory/context | STM/LTM, shared pools, consolidation, search |
| Providers | Provider health, credential rotation, model sync |
| A2A protocol | Agent-to-agent messaging, conversation continuity |
| Data sources | DataSource configuration, credential rotation, rate limits |
| Daily summaries | Auto-generated summary delivery and content |
| Autonomy/governance | Goals, observations, proposals, escalations, kill switch, intervention policies |
| RAG/knowledge | KB ingestion, chunking, embedding, retrieval |
| Knowledge graph | Node/edge creation, multi-hop reasoning |
| Monitoring | Health endpoints, alert thresholds |
| Sandboxes | Sandbox provisioning, resource limits |
| Model routing | Empirical feedback, supported_models JSONB, AgentExecution after_update hook |

Each phase contains numbered tests with expected outcomes. Walk through them in order during release qualification.

### Frontend playbook

UI-driven counterpart to the backend playbook. Every test is executable through the UI at `/app/ai/*` routes with real AI execution against the configured provider.

**Test format:**

| Test | Steps | Expected |
|---|---|---|
| 1.1 Verify provider | Navigate to providers → locate configured provider | Provider card visible with configured URL |
| 1.2 Check credentials | Click provider → Credentials tab | Credential configured, default checkmark visible |
| 1.3 Test connection | Click "Test Connection" | Green success, response time shown |
| 1.4 Sync models | Click "Sync Models" | Model list populated |

The frontend playbook walks through Providers → Agents → Teams → Conversations → Missions → Ralph Loops → Autonomy → Knowledge Graph → Monitoring. Each section has a table of tests with steps and expected outcomes.

### When to run the manual playbooks

- Before every release-candidate tag (`release/x.y.z`)
- After any architectural change to providers, model routing, or autonomy
- After any new agent or skill is added
- When automated suite is green but you suspect a high-level integration issue

Failing tests get filed as platform issues with the test number prefixed (e.g., `[AI-MANUAL-Backend-3.2]`).

## Concurrency and isolation

The test database uses `DatabaseCleaner` with the `:deletion` strategy — this avoids `TRUNCATE` deadlocks between concurrent processes. Consequences:

- **You can** run frontend tests (`CI=true npm test`) and TypeScript checks concurrently with backend specs.
- **You cannot** run multiple rspec processes simultaneously on the SAME database (`TRUNCATE`/`DELETE` deadlocks, and a transient `role_permissions` FK violation in `before(:suite)`). One process per database is fine: see [Parallel runs](#parallel-runs-opt-in) for N processes that each own a database and a Redis lane.
- **Worker job specs** run in Sidekiq test mode and don't touch the real database — safe to parallelize.

### Test data hygiene

- Every test creates the data it needs. No globally-seeded fixtures.
- Use `let!` only when the data must exist before the example runs. Otherwise use `let` to lazy-evaluate.
- Use `before(:each)` for setup; `before(:all)` is forbidden — leaks state.
- Time-sensitive tests use `travel_to` (ActiveSupport::Testing::TimeHelpers).

## CI integration

CI runs:

1. Ruby syntax check + `rubocop`
2. `tsc --noEmit`
3. Backend RSpec full suite
4. Frontend Jest full suite
5. Pattern validation scripts (see `scripts/pattern-validation.sh`)
6. (Conditionally) Playwright E2E suite on flagged PRs

Pull requests are gated on all of the above being green. Manual playbooks are not gated by CI — they're release qualification.

## Related guides

- [E2E Testing](e2e-testing.md) — Playwright
- [Backend](backend.md) — Rails patterns being tested
- [Frontend](frontend.md) — React patterns being tested
- [Accessibility](accessibility.md) — a11y test standards
- [`docs/concepts/agents-and-autonomy.md`](../concepts/agents-and-autonomy.md) — what the manual AI playbooks exercise

## Materials previously at

This guide consolidates content from these legacy paths (preserved in git history for one release cycle):

- `docs/testing/BACKEND_TEST_ENGINEER_SPECIALIST.md`
- `docs/testing/FRONTEND_TEST_ENGINEER_SPECIALIST.md`
- `docs/testing/AI_FUNCTIONALITY_MANUAL_TESTING_BACKEND.md`
- `docs/testing/AI_FUNCTIONALITY_MANUAL_TESTING_FRONTEND.md`

E2E testing moved to its own guide: [`docs/guides/e2e-testing.md`](e2e-testing.md).

_Last verified: 2026-06-04_
