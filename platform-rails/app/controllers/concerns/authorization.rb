module Authorization
  extend ActiveSupport::Concern

  ROLE_RANK = { "readonly" => 0, "operator" => 1, "admin" => 2 }.freeze

  # ---------------------------------------------------------------------------
  # SINGLE SOURCE OF TRUTH for the whole app's authorization policy.
  #
  # A maintainer reads THIS map to know who can do what — enforcement is one
  # `before_action` (authorize_action!) in ApplicationController, not scattered
  # `require_*!` calls copy-pasted across ~25 controllers.
  #
  # Resolution order (most specific wins):
  #   1. "controller_path#action" => role   (per-action override)
  #   2. "controller_path"         => role   (whole controller, GETs included —
  #                                            used for admin-only areas whose
  #                                            listings are themselves sensitive)
  #   3. fail-closed default: any WRITE (POST/PUT/PATCH/DELETE) needs :operator,
  #      so a viewer can never mutate anything — including controllers/actions
  #      added later that nobody remembered to gate. Reads (GET/HEAD) are open
  #      to any authenticated user (viewer+).
  #
  # Machine endpoints (Api::EdgeController, Webhooks::DeploysController) are
  # ActionController::Base, not ApplicationController — this concern never runs
  # for them; their token auth is their whole story.
  # ---------------------------------------------------------------------------
  POLICY = {
    # --- admin-only areas (settings, user/team/role admin, credentials) ------
    "users"                       => :admin,
    "teams"                       => :admin,
    "roles"                       => :admin,
    "git_credentials"             => :admin,
    "audit_logs"                  => :admin,
    "security"                    => :admin,
    "swarm/registries"            => :admin,
    "settings/general"            => :admin,
    "settings/auth"               => :admin,
    "settings/edge"               => :admin,
    "settings/credentials"        => :admin,
    "settings/kubeconfig_imports" => :admin,
    "ambiente/licenses"           => :admin,
    "ambiente/registries"         => :admin,
    "ambiente/policies"           => :admin,
    "ambiente/groups"             => :admin,
    "ambiente/tags"               => :admin,

    # app_templates: gallery (index/show) is open for browsing; editing the
    # template itself is admin (it's an admin-editable compose YAML — see
    # AppTemplate::ALLOWED_HOST_PATH_PREFIXES). `deploy` is NOT listed here —
    # it's a POST with no override, so it falls through to the fail-closed
    # default (operator+), matching the spec's "1-click deploy used by
    # operator, template editing is admin" split.
    "app_templates#new"           => :admin,
    "app_templates#create"        => :admin,
    "app_templates#edit"          => :admin,
    "app_templates#update"        => :admin,
    "app_templates#destroy"       => :admin,

    # environments: listing + switching the active env is open; managing the
    # env registry (create/destroy) is admin.
    "environments#new"            => :admin,
    "environments#create"        => :admin,
    "environments#destroy"        => :admin,
    "environments#activate"       => :readonly, # switches the active-env cookie

    # --- viewer-safe writes (self-service / navigation, not infra mutation) --
    "sessions#destroy"            => :readonly, # logout
    "passwords#create"            => :readonly, # forgot-password (usually anon)
    "passwords#update"            => :readonly,
    "notifications#mark_all_read" => :readonly,
    "notifications#mark_read"     => :readonly,
    "alerts#mark_all_read"        => :readonly

    # Everything else follows the fail-closed default: reads open, writes need
    # operator+ (containers/images/volumes/networks/secrets/configs/stacks,
    # swarm services & topology, git_stacks deploy/sync/rollback, kube/*, ...).
  }.freeze

  included do
    helper_method :can?
    before_action :authorize_action!
  end

  # Minimum role for a request, or nil when open (authenticated read). Pure
  # function of controller/action/verb — exposed so the policy can be swept in
  # tests without booting every controller.
  def self.min_role_for(controller_path, action, verb)
    key = "#{controller_path}##{action}"
    return POLICY[key] if POLICY.key?(key)
    return POLICY[controller_path] if POLICY.key?(controller_path)
    return :operator unless %w[GET HEAD].include?(verb.to_s.upcase) # fail-closed
    nil
  end

  private

  def authorize_action!
    return unless Current.user # anonymous flows / machine callers: not our job
    min = Authorization.min_role_for(controller_path, action_name, request.request_method)
    return if min.nil? || can?(min)

    deny_access!
  end

  def deny_access!
    if request.format.json?
      head :forbidden
    else
      redirect_to root_path, alert: "You don't have permission to do that."
    end
  end

  # Kept for the handful of views/controllers that assert a role inline; the
  # blanket enforcement above is what actually gates every request.
  def require_admin!
    deny_access! unless can?(:admin)
  end

  def require_operator!
    deny_access! unless can?(:operator)
  end

  # environment: defaults to the request's active environment, but callers
  # scoped to a specific one (e.g. fleet actions iterating N clusters) can
  # pass it explicitly.
  def can?(min_role, environment = (respond_to?(:active_environment, true) ? active_environment : nil))
    role = effective_role(environment)
    ROLE_RANK.fetch(role.to_s, -1) >= ROLE_RANK.fetch(min_role.to_s, 0)
  end

  # Global role, UNLESS the user belongs to a team that has opted into
  # per-environment scoping (Team#environment_scoped?) — teams that have
  # never added a TeamEnvironmentPermission row behave exactly as before
  # (global role governs everywhere). The instant a team gets even one row,
  # every environment without an explicit row for that team is denied to
  # its members, not just capped at readonly — that's the "restricted to
  # cluster A doesn't see cluster B" behavior the spec asks for.
  def effective_role(environment)
    user = Current.user
    return nil unless user
    return "admin" if user.admin? # global admins bypass scoping entirely

    scoped_teams = user.teams.select(&:environment_scoped?)
    return user.role if scoped_teams.empty?
    return nil if environment.nil?

    perms = TeamEnvironmentPermission.where(team_id: scoped_teams.map(&:id), environment_id: environment.id)
    return nil if perms.empty?

    perms.max_by { |p| ROLE_RANK.fetch(p.role, 0) }.role
  end
end
