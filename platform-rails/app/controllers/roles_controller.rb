class RolesController < ApplicationController

  PERMISSIONS = [
    { resource: "Containers", view: true,  operator: true,  admin: true  },
    { resource: "Imagens",    view: true,  operator: true,  admin: true  },
    { resource: "Volumes",    view: true,  operator: true,  admin: true  },
    { resource: "Redes",      view: true,  operator: true,  admin: true  },
    { resource: "Stacks",     view: true,  operator: true,  admin: true  },
    { resource: "Serviços",   view: true,  operator: true,  admin: true  },
    { resource: "Configs",    view: true,  operator: true,  admin: true  },
    { resource: "Secrets",    view: true,  operator: true,  admin: true  },
    { resource: "Git Deploy", view: true,  operator: true,  admin: true  },
    { resource: "Escalar",    view: false, operator: true,  admin: true  },
    { resource: "Desidratar", view: false, operator: true,  admin: true  },
    { resource: "Remover",    view: false, operator: true,  admin: true  },
    { resource: "Deploy",     view: false, operator: true,  admin: true  },
    { resource: "Usuários",   view: false, operator: false, admin: true  },
    { resource: "Times",      view: false, operator: false, admin: true  },
    { resource: "Funções",    view: false, operator: false, admin: true  },
    { resource: "Ambientes",  view: false, operator: false, admin: true  },
    { resource: "Configurações", view: false, operator: false, admin: true },
    { resource: "Audit Logs", view: false, operator: false, admin: true  },
  ].freeze

  def index
    @permissions = PERMISSIONS
    @users_by_role = User.group(:role).count
  end
end
