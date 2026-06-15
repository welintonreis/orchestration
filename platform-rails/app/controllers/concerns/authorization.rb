module Authorization
  extend ActiveSupport::Concern

  private

  def require_admin!
    unless Current.user&.admin?
      redirect_to root_path, alert: "Admin access required."
    end
  end

  def require_operator!
    unless Current.user&.admin? || Current.user&.operator?
      redirect_to root_path, alert: "Operator access required."
    end
  end
end
