import type { Verdict } from '@/shared/types/platformStatus';
import { VERDICT_PRESENTATION, type VerdictPresentation } from '@/shared/components/ui/VerdictBadge';

// Compile-time coverage for the closed six-verdict union (design §8 row C1).
//
// THIS FILE IS DELIBERATELY NOT A `.test.ts`. Stated precisely, because the
// usual one-line version of this rule is half wrong here (C1 review F1):
//
//   - Jest never checks it. Jest strips types without checking them, so a
//     type-level assertion in a spec contributes NOTHING to the spec run: it
//     "passes" whether or not it is true, and it passes even when the module it
//     imports does not exist. That is what happened to the system extension's
//     `StatusBadge.coverage.ts` before a review moved it to a plain `.ts`.
//   - Whether TSC checks it depends on the config, and the two configs in this
//     repo disagree. Core's `frontend/tsconfig.json` is `include: ["src"]` with
//     no `exclude`, so core specs ARE in the tsc program and an assertion left
//     in one would in fact be caught here. The extension's
//     `tsconfig.check.json` excludes `**/*.test.ts(x)`, so the same file there
//     is checked by nothing at all.
//
// So the plain `.ts` is the PORTABLE placement, not the only working one in
// core. It behaves the same on both sides of the seam, and a reader does not
// have to know which tsconfig governs the file they are looking at to know
// whether the guard is live. Do not read "specs are unchecked" as a general
// rule of this repo — it is not true of core.
//
// WHAT THIS ADDS OVER `VerdictBadge.tsx` ITSELF. The component already fails to
// compile on an unmapped verdict: it indexes an `as const` table with a
// `Verdict`, so a seventh verdict with no entry is an error at the lookup. That
// error names an index signature, not the missing verdict. The `satisfies`
// below names the verdict, at the table, which is where the fix goes. Both
// arms fire; this one is the readable half, not the only half.
//
// A failure here reads as:
//   Property 'the_new_verdict' is missing in type '{ ok: ...; held: ...; }'
//   but required in type 'Record<Verdict, VerdictPresentation>'.
// Add the verdict to VERDICT_PRESENTATION with a DELIBERATE variant, and to the
// CASES table in VerdictBadge.test.tsx.

/**
 * Every verdict has a presentation, and no presentation names a verdict that
 * is not in the union.
 *
 * `satisfies` rather than a type annotation: an annotation would widen the
 * table and give away the literal key union that makes the component's own
 * lookup strict. This checks the shape while leaving the data's type alone.
 */
export const VERDICT_COVERAGE = VERDICT_PRESENTATION satisfies Record<Verdict, VerdictPresentation>;

/**
 * The other direction, asserted separately: no key of the table falls outside
 * the union. `satisfies Record<Verdict, …>` alone would not catch a stray
 * `'sruspended'` typo added beside a real entry, because an excess key on a
 * value assigned through a variable is not an excess-property error.
 *
 * A failure here reads as: Type '"sruspended"' is not assignable to type
 * 'Verdict'.
 */
export type MappedVerdict = keyof typeof VERDICT_PRESENTATION;
const _noStrayVerdicts: Verdict = null as unknown as MappedVerdict;

// Referenced so the declaration is not flagged as unused; the assertion is the
// type annotation, not the value.
export const VERDICT_COVERAGE_ASSERTIONS = [_noStrayVerdicts] as const;
