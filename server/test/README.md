# Test Directory

This directory contains Rails' default Minitest framework structure, but **this project uses RSpec for testing**.

## Running Tests

- **Use `bundle exec rspec`** to run RSpec tests (recommended)
- **Use `rake test`** - now configured to run RSpec tests via custom rake task
- All actual tests are located in the `spec/` directory

## Test Framework Details

- **Testing Framework**: RSpec
- **Test Location**: `spec/` directory  
- **Test Count**: 107 model tests + 31 request tests + 23 security tests = 189 total tests
- **Configuration**: Custom rake task in `lib/tasks/rspec.rake` redirects `rake test` to RSpec

## Why Both Directories Exist

Rails generates the `test/` directory by default, but this project was configured to use RSpec instead of Minitest. The empty `test/` directory structure is preserved for compatibility but unused.