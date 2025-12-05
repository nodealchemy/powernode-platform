# frozen_string_literal: true

# Load spec helper
require 'spec_helper'

# Load Rails environment (worker uses standalone Sidekiq, minimal Rails)
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/application'
