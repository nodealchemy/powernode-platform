#!/usr/bin/env bash
# bootstrap-remotes.sh — enforce the git remote convention on a dev-cell checkout.
#
# Convention (mirrors the maintainer dev box):
#   core (.) + extensions/system : origin = the private Gitea, github = GitHub mirror
#   extensions/private/*         : Gitea ONLY — a github remote here is a leak and fails loudly
#
# dev-cell-clone.sh creates single-`origin` clones from Gitea; this script adds the
# GitHub mirror remotes and asserts the private-extension guard. Idempotent; safe to
# re-run after every dev-cell-clone. Never touches keys: pushing to GitHub requires the
# operator to add this host's SSH public key to the GitHub account themselves.
#
# Usage: bootstrap-remotes.sh [checkout-base]   (default: ~/work)
#
# The Gitea host is deployment configuration, never hard-coded: $POWERNODE_GITEA_HOST
# when set, else the host of the core checkout's `origin` (dev-cell-clone clones
# core from Gitea, so that origin IS the Gitea upstream).
set -euo pipefail

BASE="${1:-${HOME}/work}"
# host of a git URL: scp-style user@host:path, or scheme://[user@]host[:port]/path
url_host() {
    local u="$1"
    u="${u#*://}"; u="${u#*@}"
    u="${u%%/*}"; u="${u%%:*}"
    printf '%s' "$u"
}
GITEA_HOST="${POWERNODE_GITEA_HOST:-$(url_host "$(git -C "${BASE}" remote get-url origin 2>/dev/null || true)")}"
GITHUB_REMOTE_BASE="git@github.com:nodealchemy"

declare -A MIRRORS=(
    ["."]="powernode-platform"
    ["extensions/system"]="powernode-system"
)

fail() { echo "ERROR: $*" >&2; exit 1; }

[[ -n "${GITEA_HOST}" ]] \
    || fail "cannot determine the Gitea host: set POWERNODE_GITEA_HOST or clone core from Gitea into ${BASE}"
[[ "${GITEA_HOST}" != "github.com" ]] \
    || fail "${BASE}: origin is GitHub, not the Gitea upstream (set POWERNODE_GITEA_HOST to override)"

for path in "${!MIRRORS[@]}"; do
    repo="${BASE}/${path}"
    if ! git -C "${repo}" rev-parse --git-dir &>/dev/null; then
        echo "skip: ${repo} is not a git checkout"
        continue
    fi

    origin_url="$(git -C "${repo}" remote get-url origin 2>/dev/null || true)"
    [[ "${origin_url}" == *"${GITEA_HOST}"* ]] \
        || fail "${repo}: origin is not ${GITEA_HOST} (got '${origin_url:-none}')"

    mirror_url="${GITHUB_REMOTE_BASE}/${MIRRORS[${path}]}.git"
    if existing="$(git -C "${repo}" remote get-url github 2>/dev/null)"; then
        [[ "${existing}" == "${mirror_url}" ]] \
            || fail "${repo}: github remote is '${existing}', expected '${mirror_url}'"
        echo "ok:   ${path} github remote already set"
    else
        git -C "${repo}" remote add github "${mirror_url}"
        echo "ok:   ${path} github remote added (${mirror_url})"
    fi
done

# Leak guard: private extensions must never grow a non-Gitea remote.
for priv in "${BASE}"/extensions/private/*/; do
    [[ -d "${priv}" ]] || continue
    git -C "${priv}" rev-parse --git-dir &>/dev/null || continue
    while IFS= read -r remote; do
        url="$(git -C "${priv}" remote get-url "${remote}")"
        [[ "${url}" == *"${GITEA_HOST}"* ]] \
            || fail "private extension ${priv}: remote '${remote}' points off-Gitea (${url}) — remove it"
    done < <(git -C "${priv}" remote)
    echo "ok:   $(basename "${priv}") private remotes are Gitea-only"
done

echo "remotes OK"
echo "note: GitHub pushes need this host's SSH public key on the '${GITHUB_REMOTE_BASE#git@github.com:}' account (operator adds it via the GitHub UI)."
