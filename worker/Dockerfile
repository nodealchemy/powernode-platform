# Multi-stage build for Sidekiq worker
# Production-optimized standalone worker service

# Stage 1: Build stage
FROM ruby:3.2.0-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    postgresql-dev \
    git \
    tzdata

# Set working directory
WORKDIR /app

# Copy Gemfile and install gems
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3

# Copy application code
COPY . .

# Precompile bootsnap cache
RUN bundle exec bootsnap precompile app/ lib/ && \
    rm -rf /usr/local/bundle/cache/*.gem && \
    find /usr/local/bundle/gems/ -name "*.c" -delete && \
    find /usr/local/bundle/gems/ -name "*.o" -delete

# Stage 2: Runtime stage
FROM ruby:3.2.0-alpine AS runtime

# Install runtime dependencies
RUN apk add --no-cache \
    postgresql-client \
    redis \
    tzdata \
    curl \
    bash

# Create non-root user
RUN addgroup -g 1000 -S worker && \
    adduser -u 1000 -S worker -G worker

# Set working directory
WORKDIR /app

# Copy installed gems from builder stage
COPY --from=builder /usr/local/bundle /usr/local/bundle

# Copy application code and set ownership
COPY --from=builder --chown=worker:worker /app /app

# Create necessary directories
RUN mkdir -p tmp/pids tmp/cache log && \
    chown -R worker:worker tmp log

# Switch to non-root user
USER worker

# Health check - check if Sidekiq is responding
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:4567/health || exit 1

# Expose Sidekiq web interface port
EXPOSE 4567

# Default command
CMD ["bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml"]