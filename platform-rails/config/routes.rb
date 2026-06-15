Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :setup, only: [ :show, :create ]

  # ── Main app routes ──
  root "dashboard#index"

  resources :containers, only: %i[index show] do
    member do
      post :start
      post :stop
      post :restart
      post :kill
      post :pause
      post :unpause
      delete :remove
    end
  end
  get "containers/:id/logs", to: "containers#logs", as: :container_logs
  resources :images, only: %i[index show] do
    member { delete :remove }
  end
  resources :volumes, only: %i[index show] do
    member { delete :remove }
  end
  resources :networks, only: %i[index show] do
    member { delete :remove }
  end
  resources :environments do
    member do
      post :activate
    end
  end

  get "swarm",          to: "swarm/services#index", as: :swarm
  get "swarm/nodes",    to: "swarm/nodes#index",    as: :swarm_nodes
  get "swarm/services", to: "swarm/services#index", as: :swarm_services
  resources :git_connections
  resources :git_stacks do
    member { post :deploy }
  end
  namespace :webhooks do
    post ":token/deploy", to: "deploys#create", as: :deploy
  end
  get  "alerts",               to: "alerts#index",         as: :alerts
  post "alerts/mark_all_read", to: "alerts#mark_all_read", as: :mark_all_read_alerts

  resources :users do
    member { post :toggle_active }
  end
  resources :audit_logs, only: %i[index]
  get "metrics/latest", to: "metrics#latest", as: :metrics_latest

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
