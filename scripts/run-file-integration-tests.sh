#!/bin/bash
# File Management Integration Test Runner
# Runs all integration tests for the file management system

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_header() {
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}========================================${NC}"
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
  echo -e "${RED}✗ $1${NC}"
}

print_info() {
  echo -e "${YELLOW}ℹ $1${NC}"
}

# Main script
print_header "File Management Integration Test Suite"

# Check if we're in the right directory
if [ ! -d "$PROJECT_ROOT/server" ] || [ ! -d "$PROJECT_ROOT/frontend" ]; then
  print_error "Error: Must run from project root directory"
  exit 1
fi

# Parse arguments
BACKEND_ONLY=false
FRONTEND_ONLY=false
VERBOSE=false
COVERAGE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --backend)
      BACKEND_ONLY=true
      shift
      ;;
    --frontend)
      FRONTEND_ONLY=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --coverage)
      COVERAGE=true
      shift
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --backend     Run only backend integration tests"
      echo "  --frontend    Run only frontend integration tests"
      echo "  --verbose     Run tests with detailed output"
      echo "  --coverage    Run tests with coverage reporting"
      echo "  --help        Show this help message"
      exit 0
      ;;
    *)
      print_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Run backend tests
if [ "$FRONTEND_ONLY" = false ]; then
  print_header "Backend Integration Tests"
  cd "$PROJECT_ROOT/server"

  if [ "$VERBOSE" = true ]; then
    RSPEC_FORMAT="--format documentation"
  else
    RSPEC_FORMAT="--format progress"
  fi

  if [ "$COVERAGE" = true ]; then
    export COVERAGE=true
  fi

  print_info "Running file management flow tests..."
  bundle exec rspec spec/integration/file_management_flow_spec.rb $RSPEC_FORMAT || {
    print_error "File management flow tests failed"
    exit 1
  }
  print_success "File management flow tests passed"

  print_info "Running API endpoint tests..."
  bundle exec rspec spec/requests/api/v1/file_objects_spec.rb $RSPEC_FORMAT || {
    print_error "API endpoint tests failed"
    exit 1
  }
  print_success "API endpoint tests passed"

  print_info "Running storage provider integration tests..."
  bundle exec rspec spec/integration/storage_providers/local_storage_integration_spec.rb $RSPEC_FORMAT || {
    print_error "Storage provider tests failed"
    exit 1
  }
  print_success "Storage provider tests passed"

  print_info "Running permission access tests..."
  bundle exec rspec spec/integration/file_permission_access_spec.rb $RSPEC_FORMAT || {
    print_error "Permission access tests failed"
    exit 1
  }
  print_success "Permission access tests passed"

  print_info "Running end-to-end lifecycle tests..."
  bundle exec rspec spec/integration/file_lifecycle_e2e_spec.rb $RSPEC_FORMAT || {
    print_error "End-to-end lifecycle tests failed"
    exit 1
  }
  print_success "End-to-end lifecycle tests passed"

  print_success "All backend integration tests passed!"
fi

# Run frontend tests
if [ "$BACKEND_ONLY" = false ]; then
  print_header "Frontend Integration Tests"
  cd "$PROJECT_ROOT/frontend"

  JEST_ARGS="--testPathPattern=integration.test"

  if [ "$VERBOSE" = true ]; then
    JEST_ARGS="$JEST_ARGS --verbose"
  fi

  if [ "$COVERAGE" = true ]; then
    JEST_ARGS="$JEST_ARGS --coverage"
  fi

  print_info "Running FileUpload component integration tests..."
  npm test -- FileUpload.integration.test.tsx --passWithNoTests || {
    print_error "FileUpload integration tests failed"
    exit 1
  }
  print_success "FileUpload integration tests passed"

  print_info "Running FileBrowser component integration tests..."
  npm test -- FileBrowser.integration.test.tsx --passWithNoTests || {
    print_error "FileBrowser integration tests failed"
    exit 1
  }
  print_success "FileBrowser integration tests passed"

  print_success "All frontend integration tests passed!"
fi

# Summary
print_header "Integration Test Summary"
if [ "$BACKEND_ONLY" = false ] && [ "$FRONTEND_ONLY" = false ]; then
  print_success "✓ Backend Integration Tests: 5 suites passed"
  print_success "✓ Frontend Integration Tests: 2 suites passed"
  print_success "✓ Total: 7 integration test suites passed"
elif [ "$BACKEND_ONLY" = true ]; then
  print_success "✓ Backend Integration Tests: 5 suites passed"
elif [ "$FRONTEND_ONLY" = true ]; then
  print_success "✓ Frontend Integration Tests: 2 suites passed"
fi

print_success "All file management integration tests completed successfully! 🎉"

exit 0
