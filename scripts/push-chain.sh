#!/usr/bin/env bash
# push-chain.sh — push commits through the crengine → koreader-base → koreader chain.
#
# Usage:
#   ./scripts/push-chain.sh [crengine|base|koreader] [--dry-run]
#
#   crengine  (default) push crengine, then base, then koreader
#   base                push base, then koreader  (skip crengine)
#   koreader            push koreader only
#   --dry-run           show what would be pushed without doing anything

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CRENGINE_DIR="${ROOT}/base/thirdparty/kpvcrlib/crengine"
BASE_DIR="${ROOT}/base"

GRN='\033[0;32m'
YLW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
# All status messages go to stderr so that the captured stdout from
# push_onto_remote_master() contains only the resulting SHA.
info() { echo -e "${GRN}▶${NC} $*" >&2; }
warn() { echo -e "${YLW}⚠${NC} $*" >&2; }
die() {
    echo -e "${RED}✗${NC} $*" >&2
    exit 1
}

DRY=false
START="crengine"

for arg in "$@"; do
    case "${arg}" in
        --dry-run | -n) DRY=true ;;
        crengine | base | koreader) START="${arg}" ;;
        *) die "Unknown argument: ${arg}" ;;
    esac
done

${DRY} && warn "Dry run — no changes will be made."

# ── helpers ──────────────────────────────────────────────────────────────────

# Print commits ahead of remote/master.
show_ahead() {
    local dir="$1" remote="$2"
    git -C "${dir}" fetch "${remote}" master -q 2>/dev/null || true
    local ahead
    ahead=$(git -C "${dir}" log --oneline "${remote}/master..HEAD" 2>/dev/null || true)
    if [[ -z "${ahead}" ]]; then
        echo "  (nothing to push)"
    else
        printf '  %s\n' "${ahead//$'\n'/$'\n  '}"
    fi
}

# Push all commits ahead of remote/master onto that remote's master.
# If needed, cherry-pick (handles detached HEAD / diverged branches).
# After cherry-picking, if $sub_path is set, ensure the submodule at that path
# points to $sub_sha (adds a fixup commit if the cherry-pick brought a stale SHA).
# Prints the pushed SHA on stdout — all other output is routed to stderr so
# the caller's `$(...)` capture only sees the SHA.
push_onto_remote_master() {
    local dir="$1" remote="$2" sub_path="${3:-}" sub_sha="${4:-}"

    # Run internal commands with stdout silenced (>/dev/null) where the
    # output would otherwise leak into our `echo "$pushed_sha"` return.
    # cherry-pick, branch -D, etc. write commit info / branch deletion
    # notices to stdout that pollute the captured value.
    git -C "${dir}" fetch "${remote}" master -q 2>/dev/null || true
    local remote_tip
    remote_tip=$(git -C "${dir}" rev-parse "${remote}/master")

    local ahead
    ahead=$(git -C "${dir}" log --reverse --format="%H" "${remote_tip}..HEAD" 2>/dev/null || true)

    # Nothing ahead and no submodule to fix → already done.
    if [[ -z "${ahead}" && -z "${sub_path}" ]]; then
        info "  already up to date"
        echo "${remote_tip}"
        return
    fi

    # Build on top of remote master in a temp branch.
    git -C "${dir}" checkout -q -b _push_tmp "${remote_tip}" >/dev/null 2>&1

    # Cherry-pick each commit.
    # On conflict, auto-resolve if every conflicted file is a submodule pointer
    # (mode 160000) — the sub_sha fixup below will set the correct pointer anyway.
    # Skip commits that become empty (already applied upstream).
    for sha in ${ahead}; do
        if git -C "${dir}" cherry-pick "${sha}" >/dev/null 2>&1; then
            continue
        fi

        local -a conflicts non_submod
        mapfile -t conflicts < <(git -C "${dir}" diff --name-only --diff-filter=U 2>/dev/null)

        if [[ ${#conflicts[@]} -eq 0 ]]; then
            # No unmerged files — commit is empty (content already on remote).
            git -C "${dir}" cherry-pick --skip >/dev/null 2>&1 || true
            warn "  skipped already-applied commit ${sha}"
            continue
        fi

        non_submod=()
        for f in "${conflicts[@]}"; do
            local mode
            mode=$(git -C "${dir}" ls-files --stage -- "${f}" 2>/dev/null | awk 'NR==1{print $1}')
            if [[ "${mode}" == "160000" ]]; then
                # Submodule pointer conflict: keep HEAD version (fixed later).
                git -C "${dir}" checkout HEAD -- "${f}" >/dev/null 2>&1
                git -C "${dir}" add -- "${f}" >/dev/null 2>&1
            else
                non_submod+=("${f}")
            fi
        done

        if [[ ${#non_submod[@]} -gt 0 ]]; then
            git -C "${dir}" cherry-pick --abort >/dev/null 2>&1 || true
            git -C "${dir}" checkout -q - >/dev/null 2>&1
            git -C "${dir}" branch -D _push_tmp >/dev/null 2>&1 || true
            die "Cherry-pick of ${sha} failed (non-submodule conflicts). Resolve manually."
        fi

        warn "  submodule conflict in ${sha} auto-resolved (pointer updated after loop)"
        if ! git -C "${dir}" cherry-pick --continue --no-edit >/dev/null 2>&1; then
            # Check if the commit is now empty (all changes already on remote).
            # Use git rev-parse --git-dir because .git may be a file pointing
            # elsewhere (e.g. submodule worktrees stored in ../.git/modules/).
            local git_dir still_conflicted
            git_dir=$(git -C "${dir}" rev-parse --git-dir)
            [[ "${git_dir}" != /* ]] && git_dir="${dir}/${git_dir}"
            mapfile -t still_conflicted < <(git -C "${dir}" diff --name-only --diff-filter=U 2>/dev/null)
            if [[ ${#still_conflicted[@]} -eq 0 && -f "${git_dir}/CHERRY_PICK_HEAD" ]]; then
                git -C "${dir}" cherry-pick --skip >/dev/null 2>&1 || true
                warn "  commit ${sha} became empty after auto-resolve — skipped"
            else
                git -C "${dir}" cherry-pick --abort >/dev/null 2>&1 || true
                git -C "${dir}" checkout -q - >/dev/null 2>&1
                git -C "${dir}" branch -D _push_tmp >/dev/null 2>&1 || true
                die "Cherry-pick of ${sha} failed after auto-resolve. Resolve manually."
            fi
        fi
    done

    # Fix submodule pointer if needed.
    if [[ -n "${sub_path}" && -n "${sub_sha}" ]]; then
        local cur_sha
        cur_sha=$(git -C "${dir}" ls-tree HEAD "${sub_path}" 2>/dev/null | awk '{print $3}')
        if [[ "${cur_sha}" != "${sub_sha}" ]]; then
            git -C "${dir}/${sub_path}" checkout -q "${sub_sha}" >/dev/null 2>&1 ||
                die "Cannot checkout ${sub_sha} in ${sub_path}"
            git -C "${dir}" add "${sub_path}" >/dev/null 2>&1
            local sub_name
            sub_name=$(basename "${sub_path}")
            git -C "${dir}" commit -q -m "${sub_name}: bump to ${sub_sha:0:8}" >/dev/null 2>&1
            warn "  submodule ${sub_path} was stale → bumped to ${sub_sha:0:8}"
        fi
    fi

    git -C "${dir}" push -q "${remote}" "_push_tmp:master" >/dev/null 2>&1
    local pushed_sha
    pushed_sha=$(git -C "${dir}" rev-parse HEAD)

    git -C "${dir}" checkout -q - >/dev/null 2>&1
    git -C "${dir}" branch -D _push_tmp >/dev/null 2>&1 || true

    echo "${pushed_sha}"
}

# ── dry-run mode ─────────────────────────────────────────────────────────────

if ${DRY}; then
    if [[ "${START}" == "crengine" ]]; then
        info "crengine (mytky → master):"
        show_ahead "${CRENGINE_DIR}" mytky
    fi
    if [[ "${START}" != "koreader" ]]; then
        info "koreader-base (mytky → master):"
        show_ahead "${BASE_DIR}" mytky
    fi
    info "koreader-tategumi (origin → master):"
    show_ahead "${ROOT}" origin
    exit 0
fi

# ── push ─────────────────────────────────────────────────────────────────────

crengine_sha=""
base_sha=""

if [[ "${START}" == "crengine" ]]; then
    info "Pushing crengine…"
    crengine_sha=$(push_onto_remote_master "${CRENGINE_DIR}" mytky)
    info "  → ${crengine_sha}"
fi

if [[ "${START}" != "koreader" ]]; then
    info "Pushing koreader-base…"
    base_sha=$(push_onto_remote_master "${BASE_DIR}" mytky \
        "thirdparty/kpvcrlib/crengine" "${crengine_sha}")
    info "  → ${base_sha}"
fi

info "Pushing koreader-tategumi…"
push_onto_remote_master "${ROOT}" origin "base" "${base_sha}" >/dev/null
local_sha=$(git -C "${ROOT}" rev-parse origin/master)
info "  → ${local_sha}"

info "Done."
