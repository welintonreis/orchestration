class TeamsController < ApplicationController
  before_action :require_admin!
  before_action :set_team, only: %i[show edit update destroy]

  def index
    @teams = Team.includes(:users).order(:name)
  end

  def show
    @members = @team.team_memberships.includes(:user)
    @other_users = User.where.not(id: @team.user_ids).order(:email_address)
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

  private

  def set_team
    @team = Team.find(params[:id])
  end

  def team_params
    params.require(:team).permit(:name, :description)
  end
end
