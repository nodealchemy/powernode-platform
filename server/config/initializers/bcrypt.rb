# frozen_string_literal: true

# Test-env only: hash every bcrypt digest at the minimum cost. has_secure_password
# already does this via ActiveModel::SecurePassword.min_cost, but explicit
# BCrypt::Password.create(x) call sites read BCrypt::Engine.cost (default 12).
# Production and development keep BCrypt's default cost.
BCrypt::Engine.cost = BCrypt::Engine::MIN_COST if Rails.env.test?
