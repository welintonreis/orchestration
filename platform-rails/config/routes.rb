Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :setup, only: [ :show, :create ]

  # ── Edge agent API (own token auth, no session/cookies) ──
  namespace :api do
    post "edge/enroll",           to: "edge#enroll"
    post "edge/heartbeat",        to: "edge#heartbeat"
    post "edge/commands/:id/ack", to: "edge#ack", as: :edge_command_ack
    get  "edge/tunnel",           to: "edge_tunnels#connect", as: :edge_tunnel
  end

  # ── Kubernetes (environment endpoint_type: kubernetes) ──
  namespace :kube do
    get "fleet",      to: "fleet#index", as: :fleet
    get "fleet/rows", to: "fleet#rows",  as: :rows_fleet

    get    "workloads",                  to: "workloads#index",   as: :workloads
    get    "workloads/rows",             to: "workloads#rows",    as: :rows_workloads
    post   "workloads/:kind/:name/scale",   to: "workloads#scale",   as: :workload_scale
    post   "workloads/:kind/:name/restart", to: "workloads#restart", as: :workload_restart
    delete "workloads/:kind/:name",         to: "workloads#destroy", as: :workload

    get    "pods",                to: "pods#index",    as: :pods
    get    "pods/rows",           to: "pods#rows",     as: :rows_pods
    get    "pods/:name/logs",     to: "pods#logs",      as: :pod_logs
    get    "pods/:name/terminal", to: "pods#terminal",  as: :pod_terminal
    get    "pods/:name/ttyd-ws",  to: "pods#ttyd_ws",   as: :pod_ttyd_ws
    delete "pods/:name",          to: "pods#destroy",   as: :pod

    get    "services",       to: "services#index",   as: :services
    get    "services/rows",  to: "services#rows",    as: :rows_services
    delete "services/:name", to: "services#destroy",  as: :service

    get    "configmaps",       to: "config_maps#index",  as: :config_maps
    get    "configmaps/rows",  to: "config_maps#rows",   as: :rows_config_maps
    delete "configmaps/:name", to: "config_maps#destroy", as: :config_map

    get    "secrets",       to: "secrets#index",   as: :secrets
    get    "secrets/rows",  to: "secrets#rows",    as: :rows_secrets
    delete "secrets/:name", to: "secrets#destroy",  as: :secret

    get "nodes",      to: "nodes#index", as: :nodes
    get "nodes/rows", to: "nodes#rows",  as: :rows_nodes

    get  "apply", to: "apply#new", as: :apply
    post "apply", to: "apply#create"
  end

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
  get "containers/:id/logs",          to: "containers#logs",          as: :container_logs
  get "containers/:id/terminal",      to: "containers#terminal",      as: :container_terminal
  get "containers/:id/ttyd-ws",       to: "containers#ttyd_ws",       as: :container_ttyd_ws
  get    "containers/:id/files",         to: "containers#files",         as: :container_files
  get    "containers/:id/files/download", to: "containers#files_download", as: :container_files_download
  post   "containers/:id/files/upload",  to: "containers#files_upload",  as: :container_files_upload
  delete "containers/:id/files",         to: "containers#files_delete",  as: :container_files_delete
  post   "containers/:id/files/mkdir",   to: "containers#files_mkdir",   as: :container_files_mkdir
  patch  "containers/:id/files/rename",  to: "containers#files_rename",  as: :container_files_rename
  # ── VPS hosts: real SSH terminal + SFTP file explorer on the host itself
  # (not a container/pod exec) — ported from redhusky-remote-ssh.
  resources :vps_hosts do
    resources :terminal_sessions, controller: "vps_terminal_sessions", only: %i[index create destroy] do
      member do
        get  :terminal
        post :reconnect
      end
    end
    resources :files, controller: "vps_files", only: [:index] do
      collection do
        get    :download
        get    :archive
        get    :raw
        get    :content
        post   :upload
        post   :mkdir
        post   :move
        post   :copy
        patch  :rename
        patch  :permissions
        patch  :update_content
        delete :destroy
      end
    end
  end

  resources :images, only: %i[index show] do
    member { delete :remove }
    collection do
      get    :rows
      get    :search
      post   :pull
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
      get :rows
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
    collection do
      get :rows
    end
    member do
      post :activate
    end
  end

  get  "swarm",                    to: "swarm/dashboard#index", as: :swarm
  get  "swarm/rows",               to: "swarm/dashboard#rows",  as: :rows_swarm
  get  "swarm/nodes",              to: "swarm/nodes#index",     as: :swarm_nodes
  get  "swarm/nodes/rows",         to: "swarm/nodes#rows",      as: :rows_swarm_nodes
  get    "swarm/topology",                    to: "swarm/topology#index",          as: :swarm_topology
  get    "swarm/topology/rows",               to: "swarm/topology#rows",           as: :rows_swarm_topology
  delete "swarm/topology/prune_services",    to: "swarm/topology#prune_services",  as: :prune_services_swarm_topology
  delete "swarm/topology/system_prune",      to: "swarm/topology#system_prune",    as: :system_prune_swarm_topology
  get  "swarm/services",           to: "swarm/services#index",  as: :swarm_services
  get  "swarm/services/rows",      to: "swarm/services#rows",   as: :rows_swarm_services
  get  "swarm/services/:id",       to: "swarm/services#show",   as: :swarm_service
  get  "swarm/services/:id/body",  to: "swarm/services#body",   as: :body_swarm_service
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
      post :deploy_fleet
      post :sync
      post :rollback
      post :refresh_drift
    end
    collection { post :files }
  end
  resources :app_templates do
    member { post :deploy }
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

  get "security",      to: "security#index", as: :security
  get "security/rows", to: "security#rows",  as: :rows_security

  # ── Teams & Roles ──
  resources :teams do
    member do
      post :add_member
      delete :remove_member
      post :add_environment_permission
      delete :remove_environment_permission
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
  get "swarm/policies",        to: "swarm/policies#index",     as: :swarm_policies
  get "swarm/policies/rows",   to: "swarm/policies#rows",      as: :rows_swarm_policies

  # ── Ambiente extras ──
  namespace :ambiente do
    resources :groups, except: [ :show ] do
      member do
        post   :add_environment
        delete :remove_environment
      end
    end
    resources :policies, only: %i[index edit update]
    resources :tags,     except: [ :show ]
    resources :registries, except: [ :show ]
    get "licenses", to: "licenses#index", as: :licenses
  end

  # ── Notifications ──
  get  "notifications",               to: "notifications#index",         as: :notifications
  post "notifications/mark_all_read", to: "notifications#mark_all_read", as: :mark_all_read_notifications
  post "notifications/:id/read",      to: "notifications#mark_read",     as: :mark_read_notification

  # ── Quotas de IA ──
  get  "ai_quota",                 to: "ai_quota#index",       as: :ai_quota
  get  "ai_quota/summary",         to: "ai_quota#summary",     as: :summary_ai_quota
  post "ai_quota/bulk_toggle",     to: "ai_quota#bulk_toggle", as: :bulk_toggle_ai_quota
  post "ai_quota/import_local",    to: "ai_quota#import_local", as: :import_local_ai_quota
  get  "ai_quota/claude/login",    to: "ai_quota#new_claude_login",    as: :new_claude_login_ai_quota
  post "ai_quota/claude/login",    to: "ai_quota#create_claude_login", as: :create_claude_login_ai_quota
  get  "ai_quota/ollama/key",      to: "ai_quota#new_ollama_key",      as: :new_ollama_key_ai_quota
  post "ai_quota/ollama/key",      to: "ai_quota#create_ollama_key",   as: :create_ollama_key_ai_quota
  get    "ai_quota/:id/card",      to: "ai_quota#card",        as: :card_ai_quota
  post   "ai_quota/:id/toggle",    to: "ai_quota#toggle",      as: :toggle_ai_quota
  post   "ai_quota/:id/refresh",   to: "ai_quota#refresh",     as: :refresh_ai_quota
  delete "ai_quota/:id",           to: "ai_quota#destroy",     as: :destroy_ai_quota

  # ── SeaweedFS S3 Storage ──
  get    "seaweedfs",                     to: "seaweedfs#index",              as: :seaweedfs
  get    "seaweedfs/rows",                to: "seaweedfs#rows",               as: :rows_seaweedfs
  post   "seaweedfs/buckets",             to: "seaweedfs#create_bucket",      as: :create_seaweedfs_bucket
  post   "seaweedfs/upload",              to: "seaweedfs#upload_file",        as: :upload_seaweedfs_file
  get    "seaweedfs/download",            to: "seaweedfs#download_object",    as: :download_seaweedfs_object
  delete "seaweedfs/object",              to: "seaweedfs#destroy_object",     as: :destroy_seaweedfs_object
  post   "seaweedfs/identities",          to: "seaweedfs#create_identity",    as: :create_seaweedfs_identity
  delete "seaweedfs/identities/:name",    to: "seaweedfs#destroy_identity",   as: :delete_seaweedfs_identity

  # ── Cloudflare DNS, Email Routing & Turnstile ──
  get    "cloudflare/dns",                    to: "cloudflare_dns#index",                as: :cloudflare_dns
  get    "cloudflare/dns/rows",               to: "cloudflare_dns#rows",                 as: :rows_cloudflare_dns
  post   "cloudflare/dns",                    to: "cloudflare_dns#create"
  patch  "cloudflare/dns/:id",                to: "cloudflare_dns#update",               as: :update_cloudflare_dns_record
  delete "cloudflare/dns/:id",                to: "cloudflare_dns#destroy",              as: :delete_cloudflare_dns_record
  post   "cloudflare/dns/forward",            to: "cloudflare_dns#create_forward",       as: :create_cloudflare_dns_forward
  post   "cloudflare/dns/email_rules",        to: "cloudflare_dns#create_email_rule",    as: :create_cloudflare_email_rule
  patch  "cloudflare/dns/email_rules/:id",    to: "cloudflare_dns#update_email_rule",    as: :update_cloudflare_email_rule
  delete "cloudflare/dns/email_rules/:id",    to: "cloudflare_dns#destroy_email_rule",   as: :delete_cloudflare_email_rule
  post   "cloudflare/dns/turnstile",          to: "cloudflare_dns#create_turnstile",     as: :create_cloudflare_turnstile
  patch  "cloudflare/dns/turnstile/:id",      to: "cloudflare_dns#update_turnstile",     as: :update_cloudflare_turnstile
  delete "cloudflare/dns/turnstile/:id",      to: "cloudflare_dns#destroy_turnstile",    as: :delete_cloudflare_turnstile
  post   "cloudflare/dns/turnstile/:id/rotate", to: "cloudflare_dns#rotate_turnstile_secret", as: :rotate_cloudflare_turnstile_secret

  # ── Settings ──
  namespace :settings do
    get  "general",   to: "general#index",  as: :general
    post "general",   to: "general#update"
    get  "auth",      to: "auth#index",     as: :auth
    post "auth",      to: "auth#update"
    resources :credentials, except: [ :show ]
    get  "kubeconfig_import", to: "kubeconfig_imports#new",    as: :kubeconfig_import
    post "kubeconfig_import", to: "kubeconfig_imports#create"
    get  "edge",      to: "edge#index",     as: :edge
    post "edge",      to: "edge#update"
    post "edge/regenerate_key",     to: "edge#regenerate_key",     as: :edge_regenerate_key
    post "edge/generate_enrollment", to: "edge#generate_enrollment", as: :edge_generate_enrollment
    post "edge/nodes/:id/revoke",   to: "edge#revoke_node",        as: :edge_revoke_node
    get  "help",      to: "help#index",     as: :help
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
  get "app-assets/:key", to: "app_assets#show", as: :app_asset
end
