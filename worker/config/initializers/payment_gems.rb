# frozen_string_literal: true

# Conditionally require payment provider gems
# These gems are only needed when enterprise billing jobs are loaded
enterprise_billing = File.expand_path("../../../../extensions/enterprise/worker/app/jobs/billing", __dir__)

if Dir.exist?(enterprise_billing)
  begin
    require "stripe"
  rescue LoadError
    # Stripe gem not available — billing reconciliation will be limited
  end

  begin
    require "paypal-sdk-rest"
  rescue LoadError
    # PayPal gem not available — PayPal reconciliation will be limited
  end
end
