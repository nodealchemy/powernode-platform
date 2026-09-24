import { readFileSync, readdirSync, statSync } from 'fs';
import { join, relative, sep } from 'path';

/**
 * P16 guard: no hardcoded '/api/v1' prefix feeding an `api`/`apiClient`
 * request (double-prefix 404).
 *
 * `frontend/src/shared/services/api.ts`'s `APIClient` is constructed with
 * `baseURL` already set to '/api/v1' (getAPIBaseURL's default, and every
 * auto-detected branch also ends in that same path). Axios joins `baseURL` +
 * the request path, so a call like `api.post('/api/v1/invitations/...')`
 * actually requests `/api/v1/api/v1/invitations/...` and 404s.
 *
 * fc-01 found and fixed six live instances of this shape:
 *   - shared/services/account/invitationsApi.ts (broke invitation acceptance)
 *   - features/devops/pipelines/pages/ApprovalResponsePage.tsx (broke
 *     token-based pipeline approval)
 *   - shared/services/ai/AgentsApiService.ts's 7 "Global Conversations"
 *     methods (getGlobalConversations, getGlobalConversation,
 *     updateGlobalConversation, deleteGlobalConversation,
 *     archiveGlobalConversation, unarchiveGlobalConversation,
 *     duplicateGlobalConversation)
 *   - features/ai/components/AgentConversationComponent.tsx's mentionable-peers
 *     fetch (the literal was on its own line, split across a multi-line
 *     `apiClient\n  .get<...>(` chain, which is exactly why a call-site-only
 *     regex missed it — see below)
 *
 * features/delegations/services/delegationApi.ts has the identical defect
 * (21 methods, all hardcoding '/api/v1' through a local `apiRequest` helper
 * that forwards to `api.<verb>`) but is NOT fixed here: the operator has
 * decided to delete the whole delegations feature (frontend + server) in
 * fc-20, so it is allowlisted below rather than patched, same as the billing
 * orphans.
 *
 * SCOPE, widened from the fix's first pass: this guard does NOT require the
 * literal to appear directly inside an `api.<verb>(...)` /
 * `apiClient.<verb>(...)` call. It flags ANY string/template literal whose
 * value starts with '/api/v1', anywhere in application code. The first
 * version of this guard matched only the direct-call shape and missed
 * `delegationApi.ts` (the literal is built into an `endpoint` variable, then
 * threaded through a local `apiRequest` helper before reaching `api.<verb>`)
 * and `AgentConversationComponent.tsx` (the literal was call-site-adjacent
 * but on its own source line, defeating a same-line regex). A literal is far
 * more likely to be a live double-prefix bug than a legitimate need to spell
 * out '/api/v1' by hand, so this guard inverts the old default: every hit is
 * an offender UNLESS it is in the named ALLOWLIST below, and every allowlist
 * entry carries a reason tying it to what the literal actually feeds
 * (api/apiClient/BaseApiService => bug, fixed; fetch()/EventSource/a stored
 * full URL => the literal is correct because there is no axios baseURL to
 * double up against).
 *
 * Comments are stripped before matching (reused from
 * nav-link-reachability.test.ts): several files only MENTION '/api/v1' in a
 * JSDoc comment documenting the real backend route (e.g.
 * executionTracesApi.ts, platformStatusApi.ts, setupApi.ts,
 * A2aTasksApiService.ts's endpoint-structure header) — those are not live
 * literals and must not trip this guard.
 *
 * STILL NOT CAUGHT: a prefix assembled at RUNTIME rather than spelled out as
 * one literal — e.g. `'/api' + '/v1' + '/invitations'`, a template built
 * from a separately-declared `const PREFIX = '/api'` + `` `${PREFIX}/v1` ``,
 * or a value read from config/env. This guard is a literal-value regex, not
 * a dataflow analysis; a double-prefix bug that never spells '/api/v1' as
 * one contiguous string anywhere in the source is invisible to it.
 */

const FRONTEND_SRC = join(__dirname, '..', '..');
const REPO_ROOT = join(FRONTEND_SRC, '..', '..');
const EXTENSIONS_ROOT = join(REPO_ROOT, 'extensions');

// Discovered generically (whatever is checked out under extensions/* and
// extensions/private/*), never hardcoded by name — core must not reference a
// specific extension (public or private) by name (core-purity-check.sh).
function discoverExtensionDirs(): string[] {
  const candidateDirs: string[] = [];
  try {
    for (const e of readdirSync(EXTENSIONS_ROOT, { withFileTypes: true })) {
      if (!e.isDirectory()) continue;
      if (e.name === 'private') {
        const privateRoot = join(EXTENSIONS_ROOT, 'private');
        try {
          for (const pe of readdirSync(privateRoot, { withFileTypes: true })) {
            if (pe.isDirectory()) candidateDirs.push(join(privateRoot, pe.name));
          }
        } catch {
          // extensions/private/ not present — fine, nothing private installed
        }
      } else {
        candidateDirs.push(join(EXTENSIONS_ROOT, e.name));
      }
    }
  } catch {
    return [];
  }
  return candidateDirs;
}

function discoverExtensionSrcDirs(): { dir: string; isPrivate: boolean }[] {
  const dirs: { dir: string; isPrivate: boolean }[] = [];
  const privateRoot = join(EXTENSIONS_ROOT, 'private') + sep;
  for (const dir of discoverExtensionDirs()) {
    const candidate = join(dir, 'frontend/src');
    try {
      if (statSync(candidate).isDirectory()) {
        dirs.push({ dir: candidate, isPrivate: (candidate + sep).startsWith(privateRoot) });
      }
    } catch {
      // no frontend/src for this checked-out extension — skip
    }
  }
  return dirs;
}

function walkSourceFiles(dir: string, acc: string[] = []): string[] {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'node_modules' || entry.name.startsWith('.')) continue;
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      walkSourceFiles(full, acc);
    } else if (
      /\.(tsx|ts)$/.test(entry.name) &&
      !/\.(test|spec)\.(tsx|ts)$/.test(entry.name) &&
      !/\.d\.ts$/.test(entry.name)
    ) {
      acc.push(full);
    }
  }
  return acc;
}

// Strips `//...` line comments and `/*...*/` block comments (JSDoc
// included), string-aware so a `//`/`/*` inside a real string literal isn't
// mistaken for a comment start. See nav-link-reachability.test.ts, which
// this is copied from verbatim.
function stripComments(src: string): string {
  let out = '';
  let i = 0;
  const n = src.length;
  let inString: '"' | "'" | '`' | null = null;
  while (i < n) {
    const c = src[i];
    const c2 = src[i + 1];
    if (inString) {
      out += c;
      if (c === '\\') {
        if (i + 1 < n) out += src[i + 1];
        i += 2;
        continue;
      }
      if (c === inString) inString = null;
      i += 1;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') {
      inString = c;
      out += c;
      i += 1;
      continue;
    }
    if (c === '/' && c2 === '/') {
      while (i < n && src[i] !== '\n') i += 1;
      continue;
    }
    if (c === '/' && c2 === '*') {
      i += 2;
      while (i < n && !(src[i] === '*' && src[i + 1] === '/')) i += 1;
      i += 2;
      continue;
    }
    out += c;
    i += 1;
  }
  return out;
}

// A string/template literal whose VALUE starts with '/api/v1' (quote
// immediately followed by the prefix) — not merely containing it anywhere
// (e.g. a full `https://api.example.com/api/v1` URL does not start with the
// prefix and is not what this guard is for).
const OFFENDER_RE = /[`'"]\/api\/v1/;

// Named, itemized exceptions, keyed by repo-relative path, valued by the
// EXACT expected match count in that file — NOT a count-based BASELINE
// (there is no global budget to stay under), a per-file exact count. Each
// entry's comment ties its reason to what the literal actually feeds. A
// file dropping below its count means a fix landed (remove the entry or
// lower the count, whichever is true); a file going ABOVE its count means a
// NEW, unreviewed literal landed next to an old, reasoned-about one — both
// are failures, on purpose (see countOffenders' doc comment above it).
const ALLOWED_OFFENDER_COUNTS: Readonly<Record<string, number>> = {
  // The one file that legitimately OWNS '/api/v1': it's the default value
  // baked into the baseURL every other file must never repeat.
  'frontend/src/shared/services/api.ts': 2,

  // fc-13 orphans: same double-prefix defect, but these three have zero
  // non-test importers and are deleted (not fixed) by fc-13. They ARE
  // re-exported from a barrel (shared/services/services.ts,
  // shared/services/billing/index.ts) — that's what "zero non-test
  // importers" means here: nothing imports them THROUGH that barrel either,
  // not that the barrel itself was pruned. fc-13 removes both the files and
  // those barrel lines together.
  'frontend/src/shared/services/billing/invoicesApi.ts': 11,
  'frontend/src/shared/services/billing/paymentMethodsApi.ts': 6,
  'frontend/src/shared/services/billing/subscriptionHistoryApi.ts': 1,

  // fc-20 deletes the delegations feature (frontend + server) — same
  // double-prefix defect across all 21 methods, allowlisted rather than
  // fixed for the same reason as the billing orphans above.
  'frontend/src/features/delegations/services/delegationApi.ts': 21,

  // Feeds `new EventSource(url)` directly, never `api`/`apiClient` — an
  // EventSource has no axios baseURL to double up against, so the full
  // '/api/v1/...' path is required, not a bug. (This class ALSO calls
  // `this.get`/`this.post` like every other BaseApiService subclass, so a
  // per-FILE-only exemption would hide a real double-prefix bug added next
  // to this one — the exact count below is what actually guards that.)
  'frontend/src/shared/services/ai/A2aTasksApiService.ts': 1,

  // `endpoint: '/api/v1/setup/admin'` is DATA on a manifest-shaped step
  // descriptor, mirroring the backend's own full-path convention for
  // extension-provided setup steps. Its only consumer,
  // `setupApi.submitExtensionStep`, explicitly strips the '/api/v1' prefix
  // (`endpoint.replace(/^\/api\/v1/, '')`) before calling `apiClient.post` —
  // so the literal never reaches the client unprefixed.
  'frontend/src/features/setup/SetupWizard.tsx': 1,

  // `.replace('/api/v1', '')` REMOVES the prefix from a stored, already-full
  // provider API URL for display purposes — it never builds a request path.
  'frontend/src/pages/app/devops/GitProvidersPage.tsx': 1,

  // Reverse-proxy diagnostic UI: 'X-Forwarded-Path' header value/preset
  // text and example strings for a proxy-config tester, never a request
  // path built on `api`/`apiClient`.
  'frontend/src/features/admin/components/ProxyTestConnection.tsx': 5,
  'frontend/src/features/admin/components/ProxyDetectionStatus.tsx': 2,
  'frontend/src/features/admin/components/APIUrlPreview.tsx': 1,

  // Static developer-reference content (a hardcoded table of endpoint
  // paths shown on a docs page) — display strings, not live requests.
  'frontend/src/features/developer/pages/ApiDocs.tsx': 26,
};

// Per-file MATCH COUNT, not mere presence — a boolean-per-file allowlist
// only ever proves the file was already dirty; it can't see a SECOND,
// unrelated literal land in an already-allowlisted file (review-lane
// finding: A2aTasksApiService.ts also calls `this.get`/`this.post`, so a
// per-file exemption would hide a real double-prefix bug added right next
// to the legitimate EventSource one). Counting per file makes that a red,
// not a silent pass.
function countOffenders(files: string[]): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const file of files) {
    const text = stripComments(readFileSync(file, 'utf8'));
    const matches = text.match(new RegExp(OFFENDER_RE, 'g'));
    if (matches && matches.length > 0) {
      counts[relative(REPO_ROOT, file).split(sep).join('/')] = matches.length;
    }
  }
  return counts;
}

describe('P16 convention: no hardcoded /api/v1 prefix feeding an api/apiClient request (double-prefix 404)', () => {
  it('every offending file\'s match count exactly equals its named allowlist entry (equality ratchet, per-literal)', () => {
    const extensionSrcDirs = discoverExtensionSrcDirs();
    const publicExtensionSrcDirs = extensionSrcDirs.filter((d) => !d.isPrivate).map((d) => d.dir);
    const privateExtensionSrcDirs = extensionSrcDirs.filter((d) => d.isPrivate).map((d) => d.dir);

    const files = [FRONTEND_SRC, ...publicExtensionSrcDirs].flatMap((dir) => walkSourceFiles(dir));
    const counts = countOffenders(files);

    // Two sorted-key arrays compared, THEN a per-file count compared — a
    // dropped/added file shows up as a set mismatch, a same-file count
    // drift shows up as a value mismatch. Both fail the run.
    expect(Object.keys(counts).sort()).toEqual(Object.keys(ALLOWED_OFFENDER_COUNTS).sort());
    expect(counts).toEqual({ ...ALLOWED_OFFENDER_COUNTS });

    // Private extensions: walked, but never ratcheted — a private extension
    // is remote-only and absent from public clones (CLAUDE.md), so a finding
    // there is not portable into ALLOWED_OFFENDER_COUNTS without failing
    // every checkout that doesn't have it installed. (A checked-out private
    // extension may legitimately show up here too — e.g. a private
    // extension's fetch()-based panel feeding a raw `fetch()` the same way
    // A2aTasksApiService.ts feeds an EventSource, correct, not a bug — but
    // that can't be asserted from a checkout where the extension is absent,
    // and this file must not name which private extension or component it
    // is: core must not reference a private extension by name.)
    const privateFiles = privateExtensionSrcDirs.flatMap((dir) => walkSourceFiles(dir));
    if (privateFiles.length > 0) {
      const privateCounts = countOffenders(privateFiles);
      if (Object.keys(privateCounts).length > 0) {
        // eslint-disable-next-line no-console
        console.warn(
          "no-double-api-v1-prefix: a checked-out private extension has a '/api/v1'-prefixed " +
            'string/template literal (not enforced here — verify in that extension whether it ' +
            'feeds api/apiClient, which would be a bug, or fetch()/a full URL, which is fine):',
          privateCounts
        );
      }
    }
  });
});
