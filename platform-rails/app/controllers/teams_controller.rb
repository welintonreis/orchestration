class TeamsController < ApplicationController
  before_action :set_team, only: %i[show edit update destroy]

  def index
    @teams = Team.includes(:users).order(:name)
  end

  def show
    @members = @team.team_memberships.includes(:user)
    @other_users = User.where.not(id: @team.user_ids).order(:email_address)
    @environment_permissions = @team.team_environment_permissions.includes(:environment)
    @other_environments = Environment.where.not(id: @team.environment_ids).order(:name)
  end

  def new
    @team = Team.new
  end

  def create
    @team = Team.new(team_params)
    if @team.save
      redirect_to teams_path, notice: "Time \"#{@team.name}\" criado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @team.update(team_params)
      redirect_to teams_path, notice: "Time atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @team.destroy
    redirect_to teams_path, notice: "Time removido."
  end

  def add_member
    team = Team.find(params[:id])
    user = User.find(params[:user_id])
    team.team_memberships.find_or_create_by!(user: user) { |m| m.role = params[:role] || "member" }
    redirect_to team_path(team), notice: "#{user.email_address} adicionado."
  rescue => e
    redirect_to team_path(team), alert: "Erro: #{e.message}"
  end

  def remove_member
    team = Team.find(params[:id])
    team.team_memberships.find_by(user_id: params[:user_id])&.destroy
    redirect_to team_path(team), notice: "Membro removido."
  end

  # Adding the FIRST row here is what flips Team#environment_scoped? on —
  # from that point, every environment without a row for this team is
  # denied to its members, not just capped at readonly.
  def add_environment_permission
    team = Team.find(params[:id])
    environment = Environment.find(params[:environment_id])
    team.team_environment_permissions.find_or_create_by!(environment: environment) { |p| p.role = params[:role] || "readonly" }
    redirect_to team_path(team), notice: "Permissão para \"#{environment.name}\" adicionada."
  rescue => e
    redirect_to team_path(team), alert: "Erro: #{e.message}"
  end

  def remove_environment_permission
    team = Team.find(params[:id])
    team.team_environment_permissions.find_by(environment_id: params[:environment_id])&.destroy
    redirect_to team_path(team), notice: "Permissão removida."
  end

  private

  def set_team
    @team = Team.find(params[:id])
  end

  def team_params
    params.require(:team).permit(:name, :description)
  end
end
