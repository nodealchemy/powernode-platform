import type { Verdict } from '@/shared/types/platformStatus';
import { VERDICT_PRESENTATION, type VerdictPresentation } from '@/shared/components/ui/VerdictBadge';

// Compile-time coverage for the closed six-verdict union (design §8 row C1).
//
// THIS FILE IS DELIBERATELY NOT A `.test.ts`. Jest strips types without
// checking them, and `tsconfig` excludes spec files from the type check, so a
// type-level assertion written in a spec is checked by NOTHING — it passes
// whether or not it is true, and it passes even when the module it imports
// does not exist. The system extension's `StatusBadge.coverage.ts` was written
// as a plain `.ts` for exactly this reason after a review found the spec-shaped
// version of it inert while importing three module paths that did not exist. A
// plain `.ts` under `src` is compiled whether or not anything imports it, which
// is what makes these fail.
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
