Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # API Routes
  namespace :api do
    namespace :v1 do
      # Health check endpoint for load balancers
      get :health, to: proc { [200, {}, [{status: 'ok'}.to_json]] }
      # Authentication and registration endpoints
      namespace :auth do
        post :register, to: "registrations#create"
        post :login, to: "sessions#create"
        post :logout, to: "sessions#destroy"
        post :refresh, to: "sessions#refresh"
        get :me, to: "sessions#current"
        post "forgot-password", to: "passwords#forgot"
        post "reset-password", to: "passwords#reset"
        put "change-password", to: "passwords#change"
      end

      # Protected resources (will be added later)
      resources :accounts, only: [ :show, :update ]
      resources :users
      resources :roles
      resources :permissions, only: [ :index, :show ]

      # Payment-related endpoints
      resources :payment_methods, except: [ :show ]
      resources :subscriptions
      resources :invoices, only: [ :index, :show ]
      resources :payments, only: [ :index, :show ]

      # Analytics endpoints
      namespace :analytics do
        get :revenue
        get :growth
        get :churn
        get :cohorts
        get :customers
        match :export, via: [ :get, :post ]
      end
    end
  end

  # Webhook endpoints (outside of API versioning and auth)
  namespace :webhooks do
    post "stripe", to: "stripe#handle"
    post "paypal", to: "paypal#handle"
  end

  # ActionCable WebSocket endpoint
  mount ActionCable.server => '/cable'

  # Root route for API
  root to: proc { [ 200, {}, [ "Powernode API - Version 1.0" ] ] }
end
