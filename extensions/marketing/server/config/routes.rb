# frozen_string_literal: true

Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      namespace :marketing do
        # Public-facing endpoints (no authentication required).
        # First in the namespace so explicit routes here win over any wildcard matches below.
        namespace :public do
          post "leads/waitlist", to: "leads#waitlist"
          get "blog/posts", to: "blog#index"
          get "blog/posts/:slug", to: "blog#show"
        end

        resources :campaigns do
          member do
            post :execute
            post :pause
            post :resume
            post :archive
            post :clone
          end
          collection do
            get :statistics
          end
          resources :contents, controller: "campaign_contents" do
            collection do
              post :generate
            end
            member do
              post :approve
              post :reject
            end
          end
        end
        resources :calendar, controller: "content_calendar", except: [:show] do
          collection do
            get :conflicts
          end
        end
        resources :email_lists do
          member do
            post :import
            get :subscribers
            post :add_subscriber
            delete :remove_subscriber
          end
        end
        resources :social_accounts, controller: "social_media_accounts" do
          member do
            post :test
            post :refresh_token
          end
        end
        namespace :analytics do
          get :overview
          get "campaigns/:id", action: :campaign_detail, as: :campaign_detail
          get :channels
          get :roi
          get :top_performers
        end
      end
    end
  end
end
