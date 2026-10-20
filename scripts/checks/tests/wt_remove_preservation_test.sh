#!/bin/bash
# Red/green test: scripts/wt.sh remove preserves work (IMP-132f6b15a5fc).
#
# Rule under test: a removal never discards an extension commit that is not on develop. An extension
# checkout inside a worktree may be a SEPARATE CLONE (its own object store) instead of a linked worktree
# of the main checkout's submodule; its commits then exist nowhere else. wt.sh must fetch them into the
# main submodule store, judge them against that store's origin/develop at patch level, and either refuse
# or (with --strand-ok) pin them under refs/keep/ before anything is deleted.
#
#   a  remove on a worktree whose server/.env.test.local is missing     -> succeeds, or fails WITH a message
#   b  --strand-ok, separate-clone extension whose head (and a side branch) the main store lacks
#                                                                       -> fetched into the main store and pinned
#   c  non-strand remove, separate clone holding a commit not on develop -> refused, nothing removed
#      c2  the commit is only on a side branch of the clone            -> refused
#      c3  the clone's own origin (a fork) has the commit on ITS develop -> refused (judged against main's origin)
#   e  separate clone, but no submodule store to fetch it into         -> refused even with --strand-ok
#   f  an unexpected failure (a command failing under set -e)            -> still prints an error line
#      f2 a child that already reported (prepare-worktree.sh die)      -> no second "stopped unexpectedly" line
#   g  separate clone whose only unlanded work is a STASH               -> refused; --strand-ok pins each entry
#   h  separate clone with a TAG on a commit no branch holds            -> refused; a tag on a landed commit is fine
#   i  a private extension that is a git repo (generic slug sample-ext) -> judged like a separate clone, in
#      <main>/extensions/private/<slug>; refused (even with --discard-dirty); --strand-ok pins it there
#      i2 main's private dir is not a repo                             -> refused even with --strand-ok
#      i3 a private dir main does not have                             -> flagged, not silently deleted
#   j  pins are create-only and their stamp carries the pid (static)
#   k  remove --dry-run                                                 -> verdict only: nothing removed, no refs left
#   l  audit on a separate clone                                        -> "separate clone: run remove --dry-run", no fetch
#   n  a submodule develop added after main's checkout (absent from main's .gitmodules), initialised in the
#      worktree with a commit                                          -> refused even with --strand-ok
#   o  a separate clone with a worktree of its own                     -> refused even with --strand-ok
#   p  a merge commit not on develop (git cherry skips merges)          -> counted, refused
#   q  a judged checkout changes between judging and removal           -> refused, nothing dropped
#   m  a refusal keeps refs/keep/<wt>/refused-<stamp> on the imported objects, so gc cannot prune them
#   d  a fully merged worktree removes cleanly (linked extension, and a separate clone whose commit landed),
#      with no "could not remove extensions/<name>" warning for the clone
#
# SAFETY: wt.sh deletes worktrees. Every repository, worktree, ledger and lane here lives in one mktemp -d
# directory. The scripts under test are COPIED into a throwaway main checkout there, so wt.sh resolves
# MAIN to that copy (it derives MAIN from its own location), and every run goes through `env -i` with
# WT_ROOT, WT_LANE_LEDGER, WT_DROPDB_CMD (a stub that only records), HOME and the git config pointed into
# the temp directory; nothing from the caller's environment (PG*, DATABASE_URL, TEST_ENV_NUMBER, GIT_DIR...)
# reaches it. Each remove target is asserted to be inside the temp directory before the script runs.
#
# WT_SCRIPTS_UNDER_TEST overrides the directory holding wt.sh, prepare-worktree.sh and lib/landing-common.sh
# (for red-first runs against an older copy).
#
# Usage: bash scripts/checks/tests/wt_remove_preservation_test.sh
# Exits 0 if all assertions pass, 1 otherwise.
set -u

REPO="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)" || exit 1
SRC="${WT_SCRIPTS_UNDER_TEST:-$REPO/scripts}"
for f in wt.sh prepare-worktree.sh lib/landing-common.sh; do
    [ -f "$SRC/$f" ] || { echo "FAIL: $SRC/$f not found"; exit 1; }
done

fail=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/wt-remove-test.XXXXXX")" || exit 1
TMP="$(cd "$TMP" && pwd -P)"
case "$TMP" in */wt-remove-test.*) ;; *) echo "FAIL: unexpected temp dir $TMP"; exit 1 ;; esac
trap 'rm -rf -- "${TMP:?}"' EXIT

check() { # check NAME CONDITION-EXIT-CODE
    if [[ "$2" -eq 0 ]]; then echo "PASS: $1"; else
        echo "FAIL: $1"; fail=1
        [ -z "${ERR:-}" ] || printf '%s\n' "$ERR" | tail -n 3 | sed 's/^/      | /'
    fi
}

mkdir -p "$TMP/home" "$TMP/bin"
printf '[protocol "file"]\n\tallow = always\n[init]\n\tdefaultBranch = develop\n[advice]\n\tdetachedHead = false\n' > "$TMP/gitconfig"
CLEAN_PATH="/usr/local/bin:/usr/bin:/bin"
# Sanitised environment for EVERY command here (fixture git and wt.sh alike).
E() {
    env -i PATH="$CLEAN_PATH" HOME="$TMP/home" TMPDIR="$TMP" LANG=C \
        GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/gitconfig" \
        GIT_AUTHOR_NAME=T GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=T GIT_COMMITTER_EMAIL=t@example.invalid \
        "$@"
}
g() { E git "$@"; }
commit_file() { # repo name msg -> prints sha
    printf '%s-%s\n' "$2" "$RANDOM$RANDOM" > "$1/$2"
    g -C "$1" add "$2" && g -C "$1" commit -q -m "$3" && g -C "$1" rev-parse HEAD
}

# fixture NAME: a world of its own under $TMP/NAME — bare core + extension origins, a main checkout with
# the scripts under test and one public submodule (extensions/widgets). Sets W (world dir) and MAIN.
fixture() {
    W="$TMP/$1"; MAIN="$W/main"
    mkdir -p "$W"
    g init -q --bare -b develop "$W/origin.git" && g init -q --bare -b develop "$W/ext.git" || return 1
    g clone -q "$W/ext.git" "$W/seed-ext" 2>/dev/null && g -C "$W/seed-ext" checkout -q -b develop &&
        commit_file "$W/seed-ext" e0.txt "ext base" >/dev/null && g -C "$W/seed-ext" push -q origin develop || return 1
    g clone -q "$W/origin.git" "$MAIN" 2>/dev/null && g -C "$MAIN" checkout -q -b develop || return 1
    mkdir -p "$MAIN/scripts/lib" "$MAIN/server/config" "$MAIN/worker"
    cp "$SRC/wt.sh" "$SRC/prepare-worktree.sh" "$MAIN/scripts/" && cp "$SRC/lib/landing-common.sh" "$MAIN/scripts/lib/"
    chmod +x "$MAIN/scripts/wt.sh" "$MAIN/scripts/prepare-worktree.sh"
    : > "$MAIN/server/.keep"; : > "$MAIN/worker/.keep"
    printf 'default: {}\n' > "$MAIN/server/config/database.yml"
    printf '/scripts/local/\n/extensions/private/\n.env.*\n.bundle/\n' > "$MAIN/.gitignore"
    g -C "$MAIN" add . && g -C "$MAIN" commit -q -m "core base" &&
        g -C "$MAIN" submodule add -q "$W/ext.git" extensions/widgets >/dev/null 2>&1 &&
        g -C "$MAIN" commit -q -m "add ext" && g -C "$MAIN" push -q origin develop &&
        g -C "$MAIN/extensions/widgets" fetch -q origin || return 1
    printf '#!/bin/sh\necho "$TEST_DB_NAME" >> "%s/drops.log"\n' "$W" > "$W/dropdb.sh"; chmod +x "$W/dropdb.sh"
}

# wt ARGS...: run the copied wt.sh in the sanitised env; sets RC, OUT, ERR.
wt() {
    if [ "${1:-}" = remove ]; then
        case "$2" in "$TMP"/*) ;; *) echo "FAIL: refusing to run remove outside the temp dir: $2"; exit 1 ;; esac
    fi
    E WT_ROOT="$W/wts" WT_LANE_LEDGER="${LEDGER_OVERRIDE:-$W/ledger}" WT_DROPDB_CMD="$W/dropdb.sh" WORKTREE_MAX=9 \
        "${EXTRA_ENV[@]}" bash "$MAIN/scripts/wt.sh" "$@" >"$W/out" 2>"$W/err"
    RC=$?; OUT="$(cat "$W/out")"; ERR="$(cat "$W/err")"
}
EXTRA_ENV=()
create() { # key -> sets WT
    wt create "$1" --no-db --no-fetch
    WT="$W/wts/$1"
    [ "$RC" -eq 0 ] && [ -d "$WT" ] || { echo "FAIL: fixture create $1 (rc=$RC): $ERR"; fail=1; return 1; }
}
# Replace the linked extension worktree with a separate clone of <origin> on branch <key>.
separate_clone() { # origin key
    g -C "$MAIN/extensions/widgets" worktree remove --force "$WT/extensions/widgets" &&
        rm -rf -- "${WT:?}/extensions/widgets" &&
        g clone -q "$1" "$WT/extensions/widgets" 2>/dev/null &&
        g -C "$WT/extensions/widgets" checkout -q -B "$2" origin/develop
}
in_main_store() { g -C "$MAIN/extensions/widgets" cat-file -e "$1^{commit}" 2>/dev/null; }
last_err_line() { printf '%s\n' "$ERR" | grep -v '^$' | tail -n 1; }

echo "=== wt.sh remove: work preservation ==="

# ---- a: missing server/.env.test.local --------------------------------------------------------------
fixture a && create imp-a && {
    rm -f -- "$WT/server/.env.test.local"
    wt remove "$WT"
    if [ "$RC" -eq 0 ]; then
        [ ! -e "$WT" ]; check "a: remove without .env.test.local succeeds and removes the worktree" $?
        printf '%s\n' "$ERR" | grep -q 'no isolated test database recorded'
        check "a: it says no lane database was dropped" $?
    else
        last_err_line | grep -q 'error:'
        check "a: remove without .env.test.local fails WITH a message" $?
    fi
    [ "$RC" -eq 0 ] || [ -n "$ERR" ]; check "a: never exits non-zero silently (rc=$RC)" $?
}

# ---- b: --strand-ok fetches and pins a separate clone's head and unlanded side branch ---------------
fixture b && create imp-b && separate_clone "$W/ext.git" imp-b && {
    ext="$WT/extensions/widgets"
    head_sha="$(commit_file "$ext" b.txt "separate-clone work")"
    g -C "$ext" checkout -q -b side origin/develop
    side_sha="$(commit_file "$ext" side.txt "side-branch work")"
    g -C "$ext" checkout -q imp-b
    ! in_main_store "$head_sha" && ! in_main_store "$side_sha"
    check "b: precondition: the main submodule store lacks both clone commits" $?
    wt remove "$WT" --strand-ok
    [ "$RC" -eq 0 ] && [ ! -e "$WT" ]; check "b: --strand-ok removes the worktree (rc=$RC)" $?
    in_main_store "$head_sha" && in_main_store "$side_sha"; check "b: both clone commits are now in the main submodule store" $?
    keep="$(g -C "$MAIN/extensions/widgets" for-each-ref --format='%(objectname) %(refname)' refs/keep/ 2>/dev/null)"
    printf '%s\n' "$keep" | grep -qE "^$head_sha refs/keep/imp-b/[0-9]{8}T[0-9]{6}-[0-9]+\$"
    check "b: the clone's head is pinned under refs/keep/imp-b/<stamp>" $?
    printf '%s\n' "$keep" | grep -qE "^$side_sha refs/keep/imp-b/.*side"
    check "b: the clone's unlanded side branch is pinned too" $?
    [ -z "$(g -C "$MAIN/extensions/widgets" for-each-ref refs/wt-import/ 2>/dev/null)" ]
    check "b: no temporary import refs are left behind" $?
}

# ---- c: non-strand removal refuses while a separate clone holds unlanded work ----------------------
fixture c && create imp-c && separate_clone "$W/ext.git" imp-c && {
    ext="$WT/extensions/widgets"
    sha="$(commit_file "$ext" c.txt "separate-clone work")"
    wt remove "$WT"
    [ "$RC" -eq 1 ] && [ -d "$WT" ] && [ ! -e "$W/drops.log" ]
    check "c: refused with rc 1, worktree kept, nothing dropped (rc=$RC)" $?
    printf '%s\n' "$ERR" | grep -qE 'STRANDED:.*extensions/widgets: 1 commit'
    check "c: the refusal names extensions/widgets" $?
    g -C "$ext" cat-file -e "$sha^{commit}"; check "c: the clone's commit is intact" $?
    # m: the refusal pins what it imported, so the copy in the main store survives gc
    g -C "$MAIN/extensions/widgets" for-each-ref --format='%(objectname) %(refname)' refs/keep/ |
        grep -qE "^$sha refs/keep/imp-c/refused-[0-9]{8}T[0-9]{6}-[0-9]+"
    check "m: the refusal keeps refs/keep/imp-c/refused-<stamp> on the imported commit" $?
    [ -z "$(g -C "$MAIN/extensions/widgets" for-each-ref refs/wt-import/)" ]; check "m: no temporary import refs left" $?
}

fixture c2 && create imp-c2 && separate_clone "$W/ext.git" imp-c2 && {
    ext="$WT/extensions/widgets"
    g -C "$ext" checkout -q -b side origin/develop
    commit_file "$ext" side.txt "work only on a side branch" >/dev/null
    g -C "$ext" checkout -q imp-c2
    wt remove "$WT"
    [ "$RC" -eq 1 ] && [ -d "$WT" ]
    check "c2: refused while only a side branch of the clone holds unlanded work (rc=$RC)" $?
    printf '%s\n' "$ERR" | grep -qE 'STRANDED:.*extensions/widgets'
    check "c2: the refusal names extensions/widgets" $?
}

fixture c3 && create imp-c3 && {
    g clone -q --bare "$W/ext.git" "$W/fork.git" 2>/dev/null
    separate_clone "$W/fork.git" imp-c3
    ext="$WT/extensions/widgets"
    commit_file "$ext" c3.txt "work pushed only to a fork's develop" >/dev/null
    g -C "$ext" push -q origin HEAD:develop
    wt remove "$WT"
    [ "$RC" -eq 1 ] && [ -d "$WT" ]
    check "c3: judged against the MAIN submodule's origin/develop, not the clone's own origin (rc=$RC)" $?
}

# ---- d: fully merged worktrees remove cleanly ------------------------------------------------------
fixture d && create imp-d && {
    wt remove "$WT"
    [ "$RC" -eq 0 ] && [ ! -e "$WT" ]; check "d: a merged worktree (linked extension) removes cleanly (rc=$RC)" $?
    [ -z "$(g -C "$MAIN" branch --list imp-d)" ] && [ -z "$(g -C "$MAIN/extensions/widgets" branch --list imp-d)" ]
    check "d: its merged branches are deleted" $?
    [ ! -s "$W/ledger" ]; check "d: its lane is released" $?
}

fixture d2 && create imp-d2 && separate_clone "$W/ext.git" imp-d2 && {
    ext="$WT/extensions/widgets"
    sha="$(commit_file "$ext" d2.txt "landed work")"
    g -C "$ext" push -q origin HEAD:develop
    g -C "$ext" tag landed-tag "$sha"
    wt remove "$WT"
    [ "$RC" -eq 0 ] && [ ! -e "$WT" ]; check "d2: a separate clone whose work landed removes cleanly (rc=$RC)" $?
    ! printf '%s\n' "$ERR" | grep -q 'could not remove extensions/widgets'
    check "d2: no 'could not remove extensions/widgets' warning for a separate clone" $?
    printf '%s\n' "$ERR" | grep -q 'separate clone'
    check "d2: the teardown says the clone went with its parent directory" $?
}

# ---- e: no store to preserve a separate clone in -> refuse, even with --strand-ok -------------------
fixture e && create imp-e && separate_clone "$W/ext.git" imp-e && {
    commit_file "$WT/extensions/widgets" e.txt "separate-clone work" >/dev/null
    mv "$MAIN/extensions/widgets/.git" "$W/widgets.gitfile"
    wt remove "$WT" --strand-ok
    [ "$RC" -eq 1 ] && [ -d "$WT/extensions/widgets/.git" ] && [ ! -e "$W/drops.log" ]
    check "e: refused with --strand-ok when the clone cannot be copied anywhere (rc=$RC)" $?
    printf '%s\n' "$ERR" | grep -q 'no submodule store'; check "e: the refusal says why" $?
    mv "$W/widgets.gitfile" "$MAIN/extensions/widgets/.git"
}

# ---- f: an unexpected failure is reported, not silent ----------------------------------------------
fixture f && create imp-f && {
    : > "$W/not-a-dir"
    LEDGER_OVERRIDE="$W/not-a-dir/ledger" wt remove "$WT"
    [ "$RC" -ne 0 ] && last_err_line | grep -q 'error:.*stopped unexpectedly'
    check "f: a command failing under set -e ends with an error line naming it (rc=$RC)" $?
}

# ---- j: pins are create-only (a same-name collision stops the removal instead of overwriting) -------
code="$(grep -vE '^[[:space:]]*#' "$SRC/wt.sh")"
printf '%s\n' "$code" | grep -qF 'update-ref "$2" "$3" ""' && ! printf '%s\n' "$code" | grep -E 'update-ref "\$keep' >/dev/null
check "j: every refs/keep pin goes through the create-only pin_ref" $?
printf '%s\n' "$code" | grep -qF 'stamp="$(date +%Y%m%dT%H%M%S)-$$"'; check "j: the pin stamp carries the pid" $?

# ---- f2: a child that already printed its error gets no second "stopped unexpectedly" line ----------
fixture f2 && create imp-f2a && {
    EXTRA_ENV=(WORKTREE_MAX=1)
    wt create imp-f2b --no-db --no-fetch
    EXTRA_ENV=()
    n="$(printf '%s\n' "$ERR" | grep -c 'error:')"
    [ "$RC" -ne 0 ] && [ "$n" -eq 1 ]
    check "f2: prepare-worktree.sh's own error is the only error line (rc=$RC, $n error lines)" $?
}

# ---- g: a stash is work ----------------------------------------------------------------------------
fixture g && create imp-g && separate_clone "$W/ext.git" imp-g && {
    ext="$WT/extensions/widgets"
    printf 'stashed\n' >> "$ext/e0.txt"; g -C "$ext" stash -q
    stash_sha="$(g -C "$ext" rev-parse 'stash@{0}')"
    [ -z "$(g -C "$ext" status --porcelain)" ]; check "g: precondition: the clone looks clean (only a stash)" $?
    wt remove "$WT"
    [ "$RC" -eq 1 ] && [ -d "$WT" ]; check "g: refused while the clone holds a stash (rc=$RC)" $?
    printf '%s\n' "$ERR" | grep -qE 'STRANDED:.*extensions/widgets.*stash'; check "g: the refusal names the stash" $?
    wt remove "$WT" --strand-ok
    [ "$RC" -eq 0 ] && [ ! -e "$WT" ]; check "g: --strand-ok removes it (rc=$RC)" $?
    g -C "$MAIN/extensions/widgets" for-each-ref --format='%(objectname) %(refname)' refs/keep/ |
        grep -qE "^$stash_sha refs/keep/imp-g/[0-9T-]+-stash/0\$"
    check "g: the stash entry is pinned in the main submodule store" $?
}

# ---- h: a tag on an unlanded commit is work --------------------------------------------------------
fixture h && create imp-h && separate_clone "$W/ext.git" imp-h && {
    ext="$WT/extensions/widgets"
    tsha="$(commit_file "$ext" h.txt "tagged, then the branch moved back")"
    g -C "$ext" tag -a -m "a tag" only-here "$tsha"; g -C "$ext" reset -q --hard origin/develop
    wt remove "$WT"
    [ "$RC" -eq 1 ] && [ -d "$WT" ]; check "h: refused while a tag holds an unlanded commit (rc=$RC)" $?
    printf '%s\n' "$ERR" | grep -qE 'STRANDED:.*extensions/widgets: 1 commit'; check "h: the refusal counts the tagged commit" $?
}

# ---- i: private extension repositories --------------------------------------------------------------
private_fixture() { # make <main>/extensions/private/sample-ext a repo with an origin
    g init -q --bare -b develop "$W/priv.git"
    g clone -q "$W/priv.git" "$W/priv-seed" 2>/dev/null && g -C "$W/priv-seed" checkout -q -b develop &&
        commit_file "$W/priv-seed" p0.txt "private base" >/dev/null && g -C "$W/priv-seed" push -q origin develop
    g clone -q -b develop "$W/priv.git" "$MAIN/extensions/private/sample-ext" 2>/dev/null
}
fixture i && private_fixture && create imp-i && {
    pext="$WT/extensions/private/sample-ext"
    rm -rf -- "${pext:?}" && g clone -q -b develop "$W/priv.git" "$pext" 2>/dev/null
    psha="$(commit_file "$pext" p1.txt "private work")"
    wt remove "$WT"
    [ "$RC" -eq 1 ] && [ -d "$pext/.git" ]; check "i: refused while a private extension repo holds an unlanded commit (rc=$RC)" $?
    printf '%s\n' "$ERR" | grep -qE 'STRANDED:.*extensions/private/sample-ext: 1 commit'; check "i: the refusal names it" $?
    wt remove "$WT" --discard-dirty
    [ "$RC" -eq 1 ] && [ -d "$pext/.git" ]; check "i: --discard-dirty does not discard its committed history (rc=$RC)" $?
    wt remove "$WT" --strand-ok
    [ "$RC" -eq 0 ] && [ ! -e "$WT" ]; check "i: --strand-ok removes it (rc=$RC)" $?
    g -C "$MAIN/extensions/private/sample-ext" for-each-ref --format='%(objectname) %(refname)' refs/keep/imp-i/ |
        grep -qE "^$psha refs/keep/imp-i/[0-9]{8}T[0-9]{6}-[0-9]+\$"
    check "i: its head is pinned in <main>/extensions/private/sample-ext" $?
}

fixture i2 && create imp-i2 && {
    mkdir -p "$MAIN/extensions/private/sample-ext"; : > "$MAIN/extensions/private/sample-ext/README"
    pext="$WT/extensions/private/sample-ext"
    g init -q -b develop "$pext" && commit_file "$pext" p.txt "private work, no main repo" >/dev/null
    wt remove "$WT" --strand-ok --discard-dirty
    [ "$RC" -eq 1 ] && [ -d "$pext/.git" ]; check "i2: refused even with --strand-ok when main's private dir is no repo (rc=$RC)" $?
}

fixture i3 && create imp-i3 && {
    mkdir -p "$WT/extensions/private/only-here"; printf 'x\n' > "$WT/extensions/private/only-here/f.rb"
    wt remove "$WT"
    [ "$RC" -eq 1 ] && [ -d "$WT/extensions/private/only-here" ]; check "i3: refused while a private dir main lacks exists (rc=$RC)" $?
    printf '%s\n' "$ERR" | grep -q 'extensions/private/only-here'; check "i3: the refusal names it" $?
}

# ---- k: remove --dry-run ----------------------------------------------------------------------------
fixture k && create imp-k && separate_clone "$W/ext.git" imp-k && {
    commit_file "$WT/extensions/widgets" k.txt "work" >/dev/null
    wt remove "$WT" --dry-run
    [ "$RC" -eq 1 ] && [ -d "$WT" ] && [ ! -e "$W/drops.log" ]; check "k: dry run reports the refusal, removes nothing (rc=$RC)" $?
    printf '%s\n' "$ERR" | grep -q 'dry run'; check "k: it says it is a dry run" $?
    [ -z "$(g -C "$MAIN/extensions/widgets" for-each-ref refs/wt-import/ refs/keep/)" ]
    check "k: no import or keep refs are left by a dry run" $?
    g -C "$WT/extensions/widgets" reset -q --hard origin/develop
    wt remove "$WT" --dry-run
    [ "$RC" -eq 0 ] && [ -d "$WT" ] && [ -s "$W/ledger" ] && [ ! -e "$W/drops.log" ]
    check "k: a clean dry run exits 0 and changes nothing (rc=$RC)" $?
}

# ---- l: audit does not guess about a separate clone -------------------------------------------------
fixture l && create imp-l && separate_clone "$W/ext.git" imp-l && {
    commit_file "$WT/extensions/widgets" l.txt "work" >/dev/null
    before="$(g -C "$MAIN/extensions/widgets" for-each-ref)"
    wt audit --json --no-liveness --no-fetch
    [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q 'separate clone: run remove --dry-run'
    check "l: audit marks the separate clone instead of printing a count (rc=$RC)" $?
    [ "$before" = "$(g -C "$MAIN/extensions/widgets" for-each-ref)" ]; check "l: audit fetched nothing into the main store" $?
}

# ---- n: a submodule main's .gitmodules does not know about ----------------------------------------
fixture n && {
    g init -q --bare -b develop "$W/gadgets.git"
    g clone -q "$W/gadgets.git" "$W/seed-gadgets" 2>/dev/null && g -C "$W/seed-gadgets" checkout -q -b develop &&
        commit_file "$W/seed-gadgets" g0.txt "gadgets base" >/dev/null && g -C "$W/seed-gadgets" push -q origin develop
    # develop gains a new public submodule; main's own checkout stays on the old develop.
    g clone -q -b develop "$W/origin.git" "$W/other" 2>/dev/null
    g -C "$W/other" submodule add -q "$W/gadgets.git" extensions/gadgets >/dev/null 2>&1 &&
        g -C "$W/other" commit -q -m "add gadgets" && g -C "$W/other" push -q origin develop
    g -C "$MAIN" fetch -q origin
} && create imp-n && {
    g -C "$WT" submodule update -q --init extensions/gadgets >/dev/null 2>&1
    gsha="$(commit_file "$WT/extensions/gadgets" g1.txt "work in the new submodule")"
    [ -n "$gsha" ] && [ ! -e "$MAIN/extensions/gadgets/.git" ]; check "n: precondition: initialised in the worktree, absent from main" $?
    wt remove "$WT" --strand-ok
    [ "$RC" -eq 1 ] && [ -d "$WT/extensions/gadgets" ]; check "n: refused even with --strand-ok (rc=$RC)" $?
    printf '%s\n' "$ERR" | grep -q 'extensions/gadgets'; check "n: the refusal names extensions/gadgets" $?
}

# ---- o: a separate clone with worktrees of its own --------------------------------------------------
fixture o && create imp-o && separate_clone "$W/ext.git" imp-o && {
    g -C "$WT/extensions/widgets" worktree add -q --detach "$W/clone-wt" origin/develop 2>/dev/null
    commit_file "$W/clone-wt" o.txt "detached work in the clone's own worktree" >/dev/null
    wt remove "$WT" --strand-ok
    [ "$RC" -eq 1 ] && [ -d "$WT/extensions/widgets/.git" ]; check "o: refused even with --strand-ok (rc=$RC)" $?
    printf '%s\n' "$ERR" | grep -q 'worktrees of its own'; check "o: the refusal says why" $?
}

# ---- p: a merge commit not on develop ---------------------------------------------------------------
fixture p && create imp-p && {
    g -C "$WT" checkout -q -b side-p
    printf 'A\n' > "$WT/a.txt"; g -C "$WT" add a.txt; g -C "$WT" commit -q -m "A"
    g -C "$WT" checkout -q imp-p
    g -C "$WT" merge -q --no-ff --no-commit side-p >/dev/null 2>&1
    printf 'resolution\n' > "$WT/evil.txt"; g -C "$WT" add evil.txt; g -C "$WT" commit -q -m "merge side-p, with extra work"
    # A's patch lands on develop under another sha; only the merge's own work is left
    g clone -q -b develop "$W/origin.git" "$W/other" 2>/dev/null
    printf 'A\n' > "$W/other/a.txt"; g -C "$W/other" add a.txt; g -C "$W/other" commit -q -m "A (landed)"; g -C "$W/other" push -q origin develop
    g -C "$WT" branch -q -D side-p
    wt remove "$WT"
    [ "$RC" -eq 1 ] && [ -d "$WT" ]; check "p: refused while a merge commit not on develop holds work (rc=$RC)" $?
    printf '%s\n' "$ERR" | grep -qE 'STRANDED: core: [1-9]'; check "p: the merge is counted" $?
}

# ---- q: a change between judging and removal --------------------------------------------------------
fixture q && create imp-q && separate_clone "$W/ext.git" imp-q && {
    EXTRA_ENV=("WT_TEST_HOOK_AFTER_JUDGE=git -C '$WT/extensions/widgets' commit -q --allow-empty -m late")
    wt remove "$WT"
    EXTRA_ENV=()
    [ "$RC" -eq 1 ] && [ -d "$WT" ] && [ ! -e "$W/drops.log" ]; check "q: refused, nothing dropped (rc=$RC)" $?
    printf '%s\n' "$ERR" | grep -q 'changed'; check "q: the refusal says it changed" $?
}

echo
if [[ "$fail" -eq 0 ]]; then echo "ALL ASSERTIONS PASSED"; else echo "SOME ASSERTIONS FAILED"; fi
exit "$fail"
