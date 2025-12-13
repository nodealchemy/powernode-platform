#!/bin/bash
# Security scanning script for Powernode Platform
# Includes container vulnerability scanning, dependency audit, and code analysis

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}       Powernode Platform Security Scanner                  ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Track overall status
SCAN_FAILED=0
WARNINGS=0
CRITICALS=0

# Function to check if a command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# Function to print section header
print_section() {
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Function to print result
print_result() {
  if [ "$1" -eq 0 ]; then
    echo -e "${GREEN}✅ $2${NC}"
  else
    echo -e "${RED}❌ $2${NC}"
    SCAN_FAILED=1
  fi
}

# ═══════════════════════════════════════════════════════════
# 1. SECRET SCANNING
# ═══════════════════════════════════════════════════════════
print_section "1. Secret Scanning (Gitleaks)"

if command_exists gitleaks; then
  echo "Running gitleaks secret scan..."

  GITLEAKS_REPORT="$PROJECT_ROOT/security-reports/gitleaks-report.json"
  mkdir -p "$(dirname "$GITLEAKS_REPORT")"

  if [ -f "$PROJECT_ROOT/.gitleaks.toml" ]; then
    GITLEAKS_CONFIG="--config=$PROJECT_ROOT/.gitleaks.toml"
  else
    GITLEAKS_CONFIG=""
  fi

  if gitleaks detect --source="$PROJECT_ROOT" $GITLEAKS_CONFIG --report-format=json --report-path="$GITLEAKS_REPORT" 2>&1; then
    print_result 0 "No secrets detected"
  else
    SECRETS_FOUND=$(cat "$GITLEAKS_REPORT" | jq 'length' 2>/dev/null || echo "unknown")
    print_result 1 "Found $SECRETS_FOUND potential secrets!"
    echo "  Report: $GITLEAKS_REPORT"
    ((CRITICALS++)) || true
  fi
else
  echo -e "${YELLOW}⚠️  Gitleaks not installed - skipping secret scan${NC}"
  echo "  Install: brew install gitleaks"
  ((WARNINGS++)) || true
fi

# ═══════════════════════════════════════════════════════════
# 2. CONTAINER VULNERABILITY SCANNING (TRIVY)
# ═══════════════════════════════════════════════════════════
print_section "2. Container Vulnerability Scanning (Trivy)"

if command_exists trivy; then
  TRIVY_REPORT_DIR="$PROJECT_ROOT/security-reports/trivy"
  mkdir -p "$TRIVY_REPORT_DIR"

  # Scan server Dockerfile
  if [ -f "$PROJECT_ROOT/server/Dockerfile" ]; then
    echo "Scanning server container..."
    if trivy config "$PROJECT_ROOT/server/Dockerfile" --severity HIGH,CRITICAL --format json -o "$TRIVY_REPORT_DIR/server-config.json" 2>&1; then
      VULNS=$(cat "$TRIVY_REPORT_DIR/server-config.json" | jq '[.Results[]? | .Misconfigurations[]?] | length' 2>/dev/null || echo "0")
      if [ "$VULNS" -gt 0 ]; then
        print_result 1 "Server Dockerfile: $VULNS high/critical issues"
        ((CRITICALS++)) || true
      else
        print_result 0 "Server Dockerfile: No high/critical issues"
      fi
    fi
  fi

  # Scan worker Dockerfile
  if [ -f "$PROJECT_ROOT/worker/Dockerfile" ]; then
    echo "Scanning worker container..."
    if trivy config "$PROJECT_ROOT/worker/Dockerfile" --severity HIGH,CRITICAL --format json -o "$TRIVY_REPORT_DIR/worker-config.json" 2>&1; then
      VULNS=$(cat "$TRIVY_REPORT_DIR/worker-config.json" | jq '[.Results[]? | .Misconfigurations[]?] | length' 2>/dev/null || echo "0")
      if [ "$VULNS" -gt 0 ]; then
        print_result 1 "Worker Dockerfile: $VULNS high/critical issues"
        ((CRITICALS++)) || true
      else
        print_result 0 "Worker Dockerfile: No high/critical issues"
      fi
    fi
  fi

  # Scan frontend Dockerfile
  if [ -f "$PROJECT_ROOT/frontend/Dockerfile" ]; then
    echo "Scanning frontend container..."
    if trivy config "$PROJECT_ROOT/frontend/Dockerfile" --severity HIGH,CRITICAL --format json -o "$TRIVY_REPORT_DIR/frontend-config.json" 2>&1; then
      VULNS=$(cat "$TRIVY_REPORT_DIR/frontend-config.json" | jq '[.Results[]? | .Misconfigurations[]?] | length' 2>/dev/null || echo "0")
      if [ "$VULNS" -gt 0 ]; then
        print_result 1 "Frontend Dockerfile: $VULNS high/critical issues"
        ((CRITICALS++)) || true
      else
        print_result 0 "Frontend Dockerfile: No high/critical issues"
      fi
    fi
  fi

  # Scan filesystem for vulnerabilities in dependencies
  echo "Scanning project dependencies..."
  if trivy fs "$PROJECT_ROOT" --severity HIGH,CRITICAL --scanners vuln --format json -o "$TRIVY_REPORT_DIR/dependencies.json" 2>&1; then
    VULNS=$(cat "$TRIVY_REPORT_DIR/dependencies.json" | jq '[.Results[]? | .Vulnerabilities[]?] | length' 2>/dev/null || echo "0")
    if [ "$VULNS" -gt 0 ]; then
      print_result 1 "Dependencies: $VULNS high/critical vulnerabilities"
      ((CRITICALS++)) || true
    else
      print_result 0 "Dependencies: No high/critical vulnerabilities"
    fi
  fi
else
  echo -e "${YELLOW}⚠️  Trivy not installed - skipping container scan${NC}"
  echo "  Install: brew install trivy"
  ((WARNINGS++)) || true
fi

# ═══════════════════════════════════════════════════════════
# 3. RUBY DEPENDENCY AUDIT (BUNDLER-AUDIT)
# ═══════════════════════════════════════════════════════════
print_section "3. Ruby Dependency Audit"

if [ -f "$PROJECT_ROOT/server/Gemfile.lock" ]; then
  cd "$PROJECT_ROOT/server"

  if command_exists bundle-audit || gem list bundle-audit -i > /dev/null 2>&1; then
    echo "Running bundler-audit..."

    # Update vulnerability database
    bundle-audit update 2>/dev/null || true

    AUDIT_REPORT="$PROJECT_ROOT/security-reports/bundler-audit.txt"
    mkdir -p "$(dirname "$AUDIT_REPORT")"

    if bundle-audit check --format plain > "$AUDIT_REPORT" 2>&1; then
      print_result 0 "No vulnerable Ruby gems found"
    else
      VULNS=$(grep -c "^Name:" "$AUDIT_REPORT" 2>/dev/null || echo "unknown")
      print_result 1 "Found $VULNS vulnerable Ruby gems"
      echo "  Report: $AUDIT_REPORT"
      ((CRITICALS++)) || true
    fi
  else
    echo -e "${YELLOW}⚠️  bundler-audit not installed - skipping Ruby audit${NC}"
    echo "  Install: gem install bundler-audit"
    ((WARNINGS++)) || true
  fi

  cd "$PROJECT_ROOT"
fi

# ═══════════════════════════════════════════════════════════
# 4. NPM DEPENDENCY AUDIT
# ═══════════════════════════════════════════════════════════
print_section "4. NPM Dependency Audit"

if [ -f "$PROJECT_ROOT/frontend/package-lock.json" ]; then
  cd "$PROJECT_ROOT/frontend"

  echo "Running npm audit..."

  AUDIT_REPORT="$PROJECT_ROOT/security-reports/npm-audit.json"
  mkdir -p "$(dirname "$AUDIT_REPORT")"

  if npm audit --json > "$AUDIT_REPORT" 2>&1; then
    print_result 0 "No vulnerable npm packages found"
  else
    HIGH_VULNS=$(cat "$AUDIT_REPORT" | jq '.metadata.vulnerabilities.high // 0' 2>/dev/null || echo "0")
    CRITICAL_VULNS=$(cat "$AUDIT_REPORT" | jq '.metadata.vulnerabilities.critical // 0' 2>/dev/null || echo "0")

    if [ "$HIGH_VULNS" -gt 0 ] || [ "$CRITICAL_VULNS" -gt 0 ]; then
      print_result 1 "Found $HIGH_VULNS high, $CRITICAL_VULNS critical npm vulnerabilities"
      echo "  Report: $AUDIT_REPORT"
      ((CRITICALS++)) || true
    else
      print_result 0 "No high/critical npm vulnerabilities"
    fi
  fi

  cd "$PROJECT_ROOT"
fi

# ═══════════════════════════════════════════════════════════
# 5. BRAKEMAN (RAILS SECURITY SCANNER)
# ═══════════════════════════════════════════════════════════
print_section "5. Rails Security Scan (Brakeman)"

if [ -f "$PROJECT_ROOT/server/Gemfile" ]; then
  cd "$PROJECT_ROOT/server"

  if command_exists brakeman || gem list brakeman -i > /dev/null 2>&1; then
    echo "Running Brakeman..."

    BRAKEMAN_REPORT="$PROJECT_ROOT/security-reports/brakeman.json"
    mkdir -p "$(dirname "$BRAKEMAN_REPORT")"

    if brakeman -q --format json -o "$BRAKEMAN_REPORT" 2>&1; then
      HIGH_WARNINGS=$(cat "$BRAKEMAN_REPORT" | jq '[.warnings[] | select(.confidence == "High")] | length' 2>/dev/null || echo "0")
      MEDIUM_WARNINGS=$(cat "$BRAKEMAN_REPORT" | jq '[.warnings[] | select(.confidence == "Medium")] | length' 2>/dev/null || echo "0")

      if [ "$HIGH_WARNINGS" -gt 0 ]; then
        print_result 1 "Found $HIGH_WARNINGS high-confidence security warnings"
        echo "  Report: $BRAKEMAN_REPORT"
        ((CRITICALS++)) || true
      elif [ "$MEDIUM_WARNINGS" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Found $MEDIUM_WARNINGS medium-confidence warnings${NC}"
        ((WARNINGS++)) || true
      else
        print_result 0 "No significant security warnings"
      fi
    fi
  else
    echo -e "${YELLOW}⚠️  Brakeman not installed - skipping Rails scan${NC}"
    echo "  Install: gem install brakeman"
    ((WARNINGS++)) || true
  fi

  cd "$PROJECT_ROOT"
fi

# ═══════════════════════════════════════════════════════════
# 6. DOCKER SECURITY BEST PRACTICES
# ═══════════════════════════════════════════════════════════
print_section "6. Docker Security Best Practices"

check_dockerfile() {
  local dockerfile=$1
  local name=$2
  local issues=0

  if [ ! -f "$dockerfile" ]; then
    return
  fi

  echo "Checking $name..."

  # Check for non-root user
  if ! grep -q "USER " "$dockerfile" || grep -q "USER root" "$dockerfile"; then
    echo -e "  ${YELLOW}⚠️  No non-root USER specified${NC}"
    ((issues++)) || true
  fi

  # Check for HEALTHCHECK
  if ! grep -q "HEALTHCHECK" "$dockerfile"; then
    echo -e "  ${YELLOW}⚠️  No HEALTHCHECK defined${NC}"
    ((issues++)) || true
  fi

  # Check for pinned base image versions
  if grep -q "FROM.*:latest" "$dockerfile"; then
    echo -e "  ${YELLOW}⚠️  Using :latest tag (unpinned version)${NC}"
    ((issues++)) || true
  fi

  # Check for secrets in build args
  if grep -qi "ARG.*\(password\|secret\|key\|token\)" "$dockerfile"; then
    echo -e "  ${RED}❌ Potential secrets in ARG${NC}"
    ((CRITICALS++)) || true
    ((issues++)) || true
  fi

  if [ "$issues" -eq 0 ]; then
    print_result 0 "$name follows best practices"
  else
    ((WARNINGS++)) || true
  fi
}

check_dockerfile "$PROJECT_ROOT/server/Dockerfile" "Server Dockerfile"
check_dockerfile "$PROJECT_ROOT/worker/Dockerfile" "Worker Dockerfile"
check_dockerfile "$PROJECT_ROOT/frontend/Dockerfile" "Frontend Dockerfile"

# ═══════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    SCAN SUMMARY                           ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

if [ "$CRITICALS" -gt 0 ]; then
  echo -e "${RED}❌ CRITICAL ISSUES: $CRITICALS${NC}"
fi

if [ "$WARNINGS" -gt 0 ]; then
  echo -e "${YELLOW}⚠️  WARNINGS: $WARNINGS${NC}"
fi

if [ "$SCAN_FAILED" -eq 0 ] && [ "$CRITICALS" -eq 0 ]; then
  echo -e "${GREEN}✅ All security scans passed!${NC}"
  exit 0
else
  echo ""
  echo "Reports saved to: $PROJECT_ROOT/security-reports/"
  echo ""
  echo -e "${RED}Security issues detected. Please review and fix before deployment.${NC}"
  exit 1
fi
