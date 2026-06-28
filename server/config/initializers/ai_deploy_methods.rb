# frozen_string_literal: true

# Register the CORE deploy methods into Ai::Deploy::MethodRegistry at boot. Extension-
# provided methods (e.g. the Kubernetes method in the system extension) register
# themselves via Powernode::ExtensionRegistry providers (:deploy_method_providers) and
# are resolved dynamically — never listed here, so core stays extension-agnostic.
Rails.application.config.after_initialize do
  %w[
    Ai::Deploy::Methods::SudoBridge
    Ai::Deploy::Methods::Docker
    Ai::Deploy::Methods::Workload
  ].each do |const_name|
    klass = const_name.safe_constantize
    Ai::Deploy::MethodRegistry.register(klass) if klass
  end
end
