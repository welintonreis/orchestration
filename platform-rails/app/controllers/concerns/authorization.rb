module Authorization
  extend ActiveSupport::Concern

  ROLE_RANK = { "readonly" => 0, "operator" => 1, "admin" => 2 }.freeze

  included do
    helper_method :can?
  end

  private

  def require_admin!
    unless can?(:admin)
      redirect_to root_path, alert: "Admin access required."
    end
  end

  def require_operator!
    unless can?(:operator)
      redirect_to root_path, alert: "Operator access required."
    end
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
