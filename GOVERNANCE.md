# Governance

How decisions get made in Powernode, who makes them today, and how that is meant to change as the project grows. This document is deliberately short and honest about where the project actually is.

## Current model: BDFL-for-now

Powernode is, at the time of writing, a single-maintainer project. It is stewarded by **Node Alchemy LLC**, and in practice the founder (Everett) is the benevolent-dictator-for-now (BDFL): the final call on direction, scope, and what merges.

This is not an aspiration to keep things that way — it is a description of reality. A one-person project has a real bus-factor problem: if the maintainer is unavailable, reviews and releases stall. We would rather state that plainly than imply a committee that does not exist. The purpose of this document is to make the path *out* of single-maintainer governance concrete, so that as contributors show up, decision-making can spread to match.

## How decisions are made

Most decisions never need a process — someone opens a PR, it gets reviewed, it merges. The process below is for the decisions that are bigger than a single change.

1. **Open a discussion first for anything cross-cutting.** Architecture changes, new extensions, dependency additions, anything that affects the public API or the open-core boundary, and anything that would change conventions in [`CLAUDE.md`](CLAUDE.md) start as a thread in **[GitHub Discussions](https://github.com/nodealchemy/powernode-platform/discussions)** — the default venue for design questions, proposals, and "is this the right approach?" This is also where roadmap conversations happen.
2. **Default to lazy consensus.** If a proposal sits without sustained objection, it is considered accepted. Silence is assent. You do not need a vote to proceed on most things — you need to have surfaced the idea where others could weigh in.
3. **The maintainer breaks ties.** When there is genuine disagreement that discussion does not resolve, the maintainer decides, states the reasoning in the thread, and moves on. As more maintainers come on (see below), tie-breaking becomes a maintainer-group conversation rather than one person's call.
4. **Small changes skip all of this.** Bug fixes, docs, tests, and focused improvements just need a PR and a passing review. Don't open a discussion for a typo.

Decisions and their reasoning live in the open — in the Discussions thread, the issue, or the PR — so the record is reconstructable later. We don't keep a separate private decision log.

## Earning commit / maintainer status

There is a real path here, not just "be trusted." Maintainership is earned through a track record the existing maintainer(s) can see in public:

1. **Contribute consistently.** Land several non-trivial PRs over time — features, substantive bug fixes with regression tests, or real documentation work. One big PR is good; a sustained pattern is what counts.
2. **Review others' work.** Leave useful review comments on other contributors' PRs. Maintainership is mostly about reviewing and stewarding, not just writing code, so demonstrated good judgment reviewing matters as much as committing.
3. **Show judgment on scope and conventions.** Follow the patterns in [`CLAUDE.md`](CLAUDE.md), keep changes focused, and engage constructively in design discussions. We are looking for people who reliably make calls the way the project would want them made.
4. **Get nominated and accepted.** Any existing maintainer can propose a contributor for commit access in a Discussions thread (or privately, if the contributor prefers). With no sustained objection from existing maintainers, the contributor is granted commit rights and added to the maintainer list. Until there is more than one maintainer, this is the founder's call — and growing past that single point of failure is an explicit goal, not a reluctant concession.

New maintainers start with commit access to the open-source repositories. Administrative control of the GitHub organization and the commercial extension stays with Node Alchemy LLC (see below).

## Code of conduct

Participation is governed by our **[Code of Conduct](CODE_OF_CONDUCT.md)** (Contributor Covenant). Report unacceptable behavior **privately via a [GitHub security advisory](https://github.com/nodealchemy/powernode-platform/security/advisories/new)** (the maintainers' private-report channel), or for non-sensitive matters raise it in [GitHub Discussions](https://github.com/nodealchemy/powernode-platform/discussions). Maintainers are responsible for enforcing it fairly.

## Commercial stewardship and the open-core boundary

Powernode is **open core**. It is important that contributors understand where the line sits so governance expectations are clear:

- **The core platform and its public extensions stay MIT and community-governed.** The platform plus the public **system**, **supply-chain**, and **marketing** extensions are MIT-licensed and governed by the process in this document. We intend to keep them that way — [`CONTRIBUTING.md`](CONTRIBUTING.md) is explicit that the license is not changing. Community contributions land here, and over time community maintainers help steward this surface.
- **Node Alchemy LLC maintains the commercial extension.** The business extension — multi-tenant SaaS operation, billing, enterprise compliance, and SLAs — is a commercial offering maintained by Node Alchemy LLC. It is not part of the open-source release and is not governed by community consensus; the company sets its direction. The open-source platform runs fully in **core mode** (single-user, self-hosted, all platform features unlocked) without it.
- **The company holds the open-source project's administrative keys.** Trademark, the GitHub organization, the domains, and release signing belong to Node Alchemy LLC. Community governance covers technical direction and what merges; it does not transfer ownership of the marks or the org. As the maintainer group grows, the day-to-day technical authority is what spreads — not the legal stewardship.

This split is intentional: the open source is genuinely open and meant to be governed in the open, while the commercial work funds the maintainer's time on it. If the project ever outgrows a single steward, this document is expected to grow with it — toward a named maintainer group and a more formal decision process. That evolution happens in public.

## Where to find us

- **[GitHub Discussions](https://github.com/nodealchemy/powernode-platform/discussions)** — design questions, proposals, roadmap, and decisions in the open
- **[GitHub Issues](https://github.com/nodealchemy/powernode-platform/issues)** — bugs and concrete feature requests
- **X ([@nodealchemy](https://x.com/nodealchemy))** — updates and informal questions

Related: [`CONTRIBUTING.md`](CONTRIBUTING.md) · [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) · [`ROADMAP.md`](ROADMAP.md) · [`SECURITY.md`](SECURITY.md)
