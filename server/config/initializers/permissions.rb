# frozen_string_literal: true

# Eager-load the permission catalog (config/permissions.rb) at boot.
#
# Extensions register their permissions + role grants through the
# Permissions.register_catalog / register_permissions seam from their engine
# `config.after_initialize` hooks, which are guarded by
# `::Permissions.respond_to?(:register_permissions)`. That method lives in
# config/permissions.rb, which is otherwise required lazily (via the Permission
# model). In development (eager_load = false) the model may not be referenced
# before those hooks run, so the guard fails and extension permissions silently
# never register. Loading it here — during :load_config_initializers, before any
# after_initialize hook — makes the registration seam reliable in every
# environment. Names no extension; purely a load-order guarantee.
require Rails.root.join("config", "permissions").to_s
