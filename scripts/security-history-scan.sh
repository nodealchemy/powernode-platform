#!/bin/bash
# Full git history secret scan for Powernode Platform
# Scans main repo + all submodules for leaked secrets across all branches
# Run on-demand when needed (e.g., after contributor changes, security reviews)
#
# Usage: ./scripts/security-history-scan.sh [--report-dir DIR]

set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
REPORT_DIR="$PROJECT_ROOT/security-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

for arg in "$@"; do
  case "$arg" in
    --report-dir=*) REPORT_DIR="${arg#*=}" ;;
    --help)
      echo "Usage: ./scripts/security-history-scan.sh [--report-dir DIR]"
      echo ""
      echo "Scans full git history of main repo and submodules for secrets."
      echo "Uses .gitleaks.toml config for rules and allowlists."
      echo ""
      echo "Options:"
      echo "  --report-dir DIR  Directory for JSON reports (default: security-reports/)"
      exit 0
      ;;
  esac
done

# Verify gitleaks is installed
if ! command -v gitleaks &> /dev/null; then
  echo -e "${RED}Error: gitleaks is not installed${NC}"
  echo "Install: https://github.com/gitleaks/gitleaks#installing"
  exit 1
fi

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}  Powernode Platform — Full History Secret Scan${NC}"
echo -e "${BLUE}  $(date)${NC}"
echo -e "${BLUE}  gitleaks $(gitleaks version 2>/dev/null)${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""

mkdir -p "$REPORT_DIR"

TOTAL_FINDINGS=0
REPOS_SCANNED=0
REPOS_CLEAN=0
REPOS_DIRTY=0

scan_repo() {
  local repo_path="$1"
  local repo_name="$2"
  local config_path="$3"
  local report_path="$REPORT_DIR/gitleaks-${repo_name}-${TIMESTAMP}.json"

  if [[ ! -d "$repo_path/.git" ]]; then
    echo -e "${YELLOW}  Skipping $repo_name — not a git repository${NC}"
    return
  fi

  local commit_count
  commit_count=$(cd "$repo_path" && git rev-list --all --count 2>/dev/null || echo "?")
  echo -e "${BLUE}Scanning: $repo_name ($commit_count commits, all branches)${NC}"

  local gitleaks_args=(
    detect
    "--source=$repo_path"
    "--log-opts=--all"
    "--report-format=json"
    "--report-path=$report_path"
    "--verbose"
  )

  if [[ -n "$config_path" && -f "$config_path" ]]; then
    gitleaks_args+=("--config=$config_path")
  fi

  ((REPOS_SCANNED++)) || true

  if gitleaks "${gitleaks_args[@]}" 2>&1; then
    echo -e "${GREEN}  Clean — no secrets found${NC}"
    ((REPOS_CLEAN++)) || true
    rm -f "$report_path"
  else
    if [[ -f "$report_path" ]]; then
      local findings
      findings=$(python3 -c "import json; print(len(json.load(open('$report_path'))))" 2>/dev/null || echo "0")
      if [[ "$findings" -gt 0 ]]; then
        echo -e "${RED}  $findings findings — report: $report_path${NC}"
        TOTAL_FINDINGS=$((TOTAL_FINDINGS + findings))
        ((REPOS_DIRTY++)) || true
        return
      fi
    fi
    echo -e "${GREEN}  Clean — no secrets found${NC}"
    ((REPOS_CLEAN++)) || true
    rm -f "$report_path"
  fi
}

# Main repository
scan_repo "$PROJECT_ROOT" "main" "$PROJECT_ROOT/.gitleaks.toml"
echo ""

# Submodules
if [[ -f "$PROJECT_ROOT/.gitmodules" ]]; then
  while IFS= read -r submodule_path; do
    submodule_name=$(basename "$submodule_path")
    scan_repo "$PROJECT_ROOT/$submodule_path" "$submodule_name" "$PROJECT_ROOT/.gitleaks.toml"
    echo ""
  done < <(git -C "$PROJECT_ROOT" config --file .gitmodules --get-regexp path | awk '{print $2}')
fi

# Summary
echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}  SCAN SUMMARY${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""
echo "  Repositories scanned: $REPOS_SCANNED"
echo -e "  Clean:                ${GREEN}$REPOS_CLEAN${NC}"

if [[ "$REPOS_DIRTY" -gt 0 ]]; then
  echo -e "  With findings:        ${RED}$REPOS_DIRTY${NC}"
  echo -e "  Total findings:       ${RED}$TOTAL_FINDINGS${NC}"
  echo ""
  echo "  Reports saved to: $REPORT_DIR/"
  echo ""
  echo -e "${RED}Review findings and triage: true positive vs false positive.${NC}"
  echo "  - True positive: remove secret, rotate credentials, update .gitleaks.toml"
  echo "  - False positive: add to .gitleaks.toml allowlist (paths, regexes, or stopwords)"
  exit 1
else
  echo ""
  echo -e "${GREEN}All repositories clean — no secrets found in git history.${NC}"
  exit 0
fi
