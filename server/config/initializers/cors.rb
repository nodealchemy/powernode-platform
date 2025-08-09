# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    if Rails.env.development?
      # Allow localhost and powernode.dev domains for development
      origins(
        "http://localhost:3000",
        "http://localhost:3001",
        "https://localhost:3000",
        "https://localhost:3001",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:3001",
        "http://powernode.dev:3000",
        "http://powernode.dev:3001",
        "https://powernode.dev:3000",
        "https://powernode.dev:3001",
        /\Ahttp:\/\/powernode\.dev:300[0-9]\z/,
        /\Ahttps:\/\/powernode\.dev:300[0-9]\z/
      )
    else
      # Restrict origins in production
      origins "https://powernode.dev", "https://www.powernode.dev"
    end

    resource "*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
      credentials: true
  end
end
