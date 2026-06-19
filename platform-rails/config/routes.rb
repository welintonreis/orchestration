Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :setup, only: [ :show, :create ]

  # ── Main app routes ──
  root "dashboard#index"

  resources :containers, only: %i[index show] do
    collection do
      get  :rows
      post :bulk_action
      delete :prune
    end
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
  get "containers/:id/logs",     to: "containers#logs",     as: :container_logs
  get "containers/:id/terminal", to: "containers#terminal", as: :container_terminal
  get "containers/:id/ttyd-ws",  to: "containers#ttyd_ws",  as: :container_ttyd_ws
  resources :images, only: %i[index show] do
    member { delete :remove }
    collection do
      get  :rows
      delete :batch_remove
      delete :prune_orphans
    end
  end
  resources :volumes, only: %i[index show] do
    member do
      delete :remove
      get    :browse
      get    :download
      post   :upload
      delete :file_delete
      post   :file_mkdir
      post   :file_rename
    end
    collection do
      get  :rows
      delete :batch_remove
    end
  end
  resources :networks, only: %i[index show] do
    member { delete :remove }
    collection do
      get  :rows
      post :create
    end
  end
  resources :environments do
    member do
      post :activate
    end
  end

  get  "swarm",                    to: "swarm/dashboard#index", as: :swarm
  get  "swarm/nodes",              to: "swarm/nodes#index",     as: :swarm_nodes
  get    "swarm/topology",                    to: "swarm/topology#index",          as: :swarm_topology
  delete "swarm/topology/prune_services",    to: "swarm/topology#prune_services",  as: :prune_services_swarm_topology
  delete "swarm/topology/system_prune",      to: "swarm/topology#system_prune",    as: :system_prune_swarm_topology
  get  "swarm/services",           to: "swarm/services#index",  as: :swarm_services
  get  "swarm/services/rows",      to: "swarm/services#rows",   as: :rows_swarm_services
  get  "swarm/services/:id",       to: "swarm/services#show",   as: :swarm_service
  post "swarm/services/:id/scale",    to: "swarm/services#scale",       as: :scale_swarm_service
  post "swarm/services/:id/drain",            to: "swarm/services#drain",              as: :drain_swarm_service
  post "swarm/services/:id/update_resources", to: "swarm/services#update_resources",   as: :update_resources_swarm_service
  post "swarm/services/:id/update_config",    to: "swarm/services#update_update_config", as: :update_config_swarm_service
  post "swarm/services/:id/update_logging",   to: "swarm/services#update_logging",     as: :update_logging_swarm_service
  post "swarm/services/:id/update_image",     to: "swarm/services#update_image",       as: :update_image_swarm_service
  post "swarm/services/:id/rollback",         to: "swarm/services#rollback",           as: :rollback_swarm_service
  post "swarm/services/:id/force_update",    to: "swarm/services#force_update",       as: :force_update_swarm_service
  post "swarm/services/bulk_scale",           to: "swarm/services#bulk_scale",         as: :bulk_scale_swarm_services
  resources :git_credentials
  resources :git_stacks do
    member do
      post :deploy
      post :sync
      post :rollback
      post :refresh_drift
    end
    collection { post :files }
  end
  namespace :webhooks do
    post ":token/deploy", to: "deploys#create", as: :deploy
  end
  get  "alerts",               to: "alerts#index",         as: :alerts
  post "alerts/mark_all_read", to: "alerts#mark_all_read", as: :mark_all_read_alerts

  resources :stacks, only: %i[index] do
    collection do
      get  :rows
      post "services/:service_id/scale", action: :scale_service,  as: :scale_stack_service
      post "services/:service_id/drain", action: :drain_stack_service, as: :drain_stack_service
    end
  end
  resources :configs, only: %i[index] do
    member { delete :remove }
  end
  resources :secrets, only: %i[index] do
    member { delete :remove }
    collection do
      get  :rows
      delete :batch_remove
    end
  end

  resources :users do
    member { post :toggle_active }
  end
  resources :audit_logs, only: %i[index]
  get "metrics/latest",    to: "metrics#latest",    as: :metrics_latest
  get "metrics/processes", to: "metrics#processes", as: :metrics_processes

  # ── Teams & Roles ──
  resources :teams do
    member do
      post  :add_member
      delete :remove_member
    end
  end
  get "roles", to: "roles#index", as: :roles

  # ── Swarm extras ──
  get  "swarm/registries",      to: "swarm/registries#index",   as: :swarm_registries
  get  "swarm/registries/new",  to: "swarm/registries#new",     as: :new_swarm_registry
  post "swarm/registries",      to: "swarm/registries#create"
  get  "swarm/registries/:id/edit", to: "swarm/registries#edit", as: :edit_swarm_registry
  patch "swarm/registries/:id",     to: "swarm/registries#update", as: :swarm_registry
  delete "swarm/registries/:id",    to: "swarm/registries#destroy"
  get  "swarm/policies",        to: "swarm/policies#index",     as: :swarm_policies

  # ── Ambiente extras ──
  namespace :ambiente do
    resources :groups, except: [:show] do
      member do
        post   :add_environment
        delete :remove_environment
      end
    end
    resources :policies, only: %i[index edit update]
    resources :tags,     except: [:show]
    resources :registries, except: [:show]
    get "licenses", to: "licenses#index", as: :licenses
  end

  # ── Notifications ──
  get  "notifications",               to: "notifications#index",         as: :notifications
  post "notifications/mark_all_read", to: "notifications#mark_all_read", as: :mark_all_read_notifications
  post "notifications/:id/read",      to: "notifications#mark_read",     as: :mark_read_notification

  # ── Settings ──
  namespace :settings do
    get  "general",   to: "general#index",  as: :general
    post "general",   to: "general#update"
    get  "auth",      to: "auth#index",     as: :auth
    post "auth",      to: "auth#update"
    resources :credentials, except: [:show]
    get  "edge",      to: "edge#index",     as: :edge
    post "edge",      to: "edge#update"
    post "edge/regenerate_key", to: "edge#regenerate_key", as: :edge_regenerate_key
    get  "help",      to: "help#index",     as: :help
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  get "app-assets/:key", to: "app_assets#show", as: :app_asset

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
