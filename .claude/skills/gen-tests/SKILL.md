# /gen-tests — Generate Missing Test Specs

Generate RSpec request specs for untested controllers and service specs for untested services.

## Usage

```
/gen-tests                    # List untested files, prompt for selection
/gen-tests controller         # Generate specs for untested controllers
/gen-tests service            # Generate specs for untested services
/gen-tests path/to/file.rb    # Generate spec for a specific file
```

## Workflow

### Step 1: Identify Untested Files

Find controllers/services without corresponding specs:

```bash
# Untested controllers
cd server && for f in $(find app/controllers/api/v1 -name '*_controller.rb'); do
  spec="spec/requests/api/v1/$(basename "$f" .rb)_spec.rb"
  [[ ! -f "$spec" ]] && echo "UNTESTED: $f"
done

# Untested services
cd server && for f in $(find app/services -name '*.rb' | grep -v concerns); do
  spec="spec/services/$(echo "$f" | sed 's|app/services/||; s|\.rb$|_spec.rb|')"
  [[ ! -f "$spec" ]] && echo "UNTESTED: $f"
done
```

### Step 2: Read Source & Context

For each file to test, read:
1. The source file itself (understand methods, params, permissions)
2. The routes file (`config/routes.rb`) for endpoint paths
3. Existing factories in `spec/factories/` relevant to the models used
4. Similar existing specs for pattern reference

### Step 2b: Query MCP for Test Patterns (if available)

Before generating specs, query MCP for relevant learnings that may improve spec quality:

1. `platform.query_learnings` — query: `"<model/service name> test"` (e.g., `"ai agent test"`, `"subscription service test"`)
2. `platform.query_learnings` — query: `"factory <model name>"` (e.g., `"factory ai_agent"`, `"factory account"`)

Apply any relevant findings (required factory traits, tricky setup, known assertion patterns) to the spec generation approach.

**Graceful degradation**: If MCP tools are unavailable or return errors, skip this step and proceed with standard spec generation. MCP is additive, not required.

### Step 3: Generate Spec

Use these mandatory patterns from the project:

**Request specs (controllers):**
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Api::V1::ResourceName", type: :request do
  include_examples 'requires authentication'

  let(:user) { user_with_permissions('resource.read', 'resource.manage') }
  let(:headers) { auth_headers_for(user) }
  let(:account) { user.account }

  describe "GET /api/v1/resources" do
    it "returns resources for current account" do
      resource = create(:resource, account: account)
      get "/api/v1/resources", headers: headers
      expect_success_response(json_response_data)
    end
  end

  describe "POST /api/v1/resources" do
    let(:valid_params) { { resource: { name: "Test" } } }

    it "creates a resource" do
      post "/api/v1/resources", params: valid_params, headers: headers
      expect_success_response(json_response_data)
    end
  end
end
```

**Service specs:**
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ServiceName, type: :service do
  let(:account) { create(:account) }
  let(:user) { user_with_permissions('relevant.permission') }

  describe '#method_name' do
    it 'does the expected behavior' do
      result = described_class.new(account).method_name
      expect(result).to be_present
    end
  end
end
```

**Key helpers to use:**
- `user_with_permissions('perm.name')` — creates user with permissions
- `auth_headers_for(user)` — returns auth headers
- `json_response` / `json_response_data` — parse response body
- `expect_success_response(data)` / `expect_error_response(msg, status)` — response assertions
- `include_examples 'requires authentication'` — shared auth check
- `include_examples 'requires permission'` — shared permission check
- AI specs: use factories from `spec/factories/ai/` and helpers from `spec/support/ai_test_helpers.rb`

### Step 4: Run & Fix

```bash
cd server && bundle exec rspec spec/path/to/new_spec.rb --format progress
```

If tests fail, fix up to 3 times. After 3 failures, stop and report what needs manual attention.

### Step 5: Report

Output a summary:
- Files tested
- Specs generated (with paths)
- Pass/fail status
- Any specs that need manual attention

### Step 5b: Contribute Learning (conditional)

If spec generation revealed a **non-obvious pattern** worth capturing for future test generation, create a learning:

```
platform.create_learning(
  title: "Test pattern: <concise description>",
  content: "<what was non-obvious and how to handle it>",
  category: "pattern"
)
```

**Create a learning when**: required factory setup was non-trivial, mocking/stubbing required unusual configuration, assertions needed specific structure due to serializer behavior, or account-scoping had edge cases.

**Skip for**: straightforward CRUD controller specs, standard factory usage, obvious permission checks.
