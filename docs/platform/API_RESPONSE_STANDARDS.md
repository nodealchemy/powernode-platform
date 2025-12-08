# API Response Standards

Unified API response format documentation for the Powernode platform.

## Response Structure

All API endpoints MUST return responses using the ApiResponse concern methods. NEVER use manual `render json:` calls.

### Success Response

```ruby
# Controller usage
render_success(data, status: :ok)
render_success(data, message: "Operation completed")
```

```json
{
  "success": true,
  "data": { ... },
  "message": "Optional message"
}
```

### Error Response

```ruby
# Controller usage
render_error("Error message", status: :bad_request)
render_error("Not found", status: :not_found)
```

```json
{
  "success": false,
  "error": "Error message",
  "code": "error_code"
}
```

### Validation Error Response

```ruby
# Controller usage
render_validation_error(record.errors)
```

```json
{
  "success": false,
  "error": "Validation failed",
  "errors": {
    "field_name": ["error message"]
  }
}
```

### Paginated Response

```ruby
# Controller usage
render_paginated(collection, serializer: ItemSerializer)
```

```json
{
  "success": true,
  "data": [ ... ],
  "meta": {
    "current_page": 1,
    "total_pages": 10,
    "total_count": 100,
    "per_page": 10
  }
}
```

## ApiResponse Concern

The `ApiResponse` concern is automatically included in `ApplicationController`. All controllers that inherit from `ApplicationController` have access to these methods.

### Available Methods

| Method | Purpose | Status Code |
|--------|---------|-------------|
| `render_success(data, opts)` | Successful response | 200 (default) |
| `render_created(data, opts)` | Resource created | 201 |
| `render_error(message, opts)` | Error response | 400 (default) |
| `render_not_found(message)` | Resource not found | 404 |
| `render_unauthorized(message)` | Authentication failed | 401 |
| `render_forbidden(message)` | Authorization failed | 403 |
| `render_validation_error(errors)` | Validation errors | 422 |
| `render_paginated(collection, opts)` | Paginated list | 200 |

## FORBIDDEN Patterns

```ruby
# NEVER do this - manual JSON responses
render json: { success: true, data: user }
render json: { error: "Not found" }, status: :not_found

# NEVER include ApiResponse in controllers (already inherited)
class MyController < ApplicationController
  include ApiResponse  # WRONG - already included via inheritance
end
```

## Controller Example

```ruby
# frozen_string_literal: true

module Api
  module V1
    class UsersController < ApplicationController
      before_action :authenticate_user!
      before_action :set_user, only: [:show, :update, :destroy]

      def index
        users = current_account.users
        render_paginated(users, serializer: UserSerializer)
      end

      def show
        render_success(UserSerializer.new(@user))
      end

      def create
        user = current_account.users.build(user_params)
        if user.save
          render_created(UserSerializer.new(user))
        else
          render_validation_error(user.errors)
        end
      end

      def update
        if @user.update(user_params)
          render_success(UserSerializer.new(@user))
        else
          render_validation_error(@user.errors)
        end
      end

      def destroy
        @user.destroy
        render_success(nil, message: "User deleted")
      end

      private

      def set_user
        @user = current_account.users.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_not_found("User not found")
      end

      def user_params
        params.require(:user).permit(:email, :name, :role_id)
      end
    end
  end
end
```

## Frontend Handling

```typescript
interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
}

interface PaginatedResponse<T> extends ApiResponse<T[]> {
  meta: {
    current_page: number;
    total_pages: number;
    total_count: number;
    per_page: number;
  };
}

// Example API call
const response = await apiClient.get<User>('/api/v1/users/1');
if (response.success) {
  setUser(response.data);
} else {
  showError(response.error);
}
```

## See Also

- [Rails Architect Specialist](../backend/RAILS_ARCHITECT_SPECIALIST.md)
- [API Developer Specialist](../backend/API_DEVELOPER_SPECIALIST.md)
