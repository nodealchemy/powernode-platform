# Multi-stage production Dockerfile for Rails API backend
FROM ruby:3.2.8-slim AS base

# Install system dependencies + tini for proper PID 1 init
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    curl \
    tini \
    libjemalloc2 \
    libpq5 \
    libvips42 \
    imagemagick \
    && rm -rf /var/lib/apt/lists/*

# Set environment
ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test

WORKDIR /app

# Build stage for compiling gems
FROM base AS build

# Allow Gemfile.lock drift when extension gems are absent from the Docker context
ENV BUNDLE_FROZEN=false

# Install build dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    git \
    libpq-dev \
    libyaml-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Create stub for extensions_loader_helper (lives at project root, outside Docker context)
# The real helper returns [] when no extensions/ directory exists; this stub does the same.
RUN printf '# frozen_string_literal: true\ndef discover_extension_gems; []; end\n' > /extensions_loader_helper.rb

# Install gems (unfreeze bundle to allow lock drift when extension gems are absent)
COPY Gemfile Gemfile.lock ./
RUN BUNDLE_FROZEN=false bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile --gemfile app/ lib/

# Production stage
FROM base AS production

# Copy built gems and application
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /app /app
# Copy extensions_loader_helper stub (Gemfile require_relative resolves to /)
COPY --from=build /extensions_loader_helper.rb /extensions_loader_helper.rb

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash rails && \
    chown -R rails:rails /app
USER rails

# Configure runtime
ENV MALLOC_CONF="dirty_decay_ms:1000,narenas:2,background_thread:true" \
    LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2

EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Use tini as init system for proper signal handling and zombie reaping
ENTRYPOINT ["tini", "--"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
