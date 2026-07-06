# feature-app-templates.md — one-click deploy gallery. CRUD is admin-only
# (POLICY overrides below); index/show/deploy default-open to any
# authenticated user for browsing, with `deploy` itself needing operator+
# via Authorization's fail-closed default (no override needed — it's a POST).
class AppTemplatesController < ApplicationController
  before_action :set_app_template, only: %i[show edit update destroy deploy]

  def index
    @app_templates = AppTemplate.order(:name)
  end

  def show
  end

  def new
    @app_template = AppTemplate.new
  end

  def create
    @app_template = AppTemplate.new(app_template_params)
    if @app_template.save
      redirect_to app_templates_path, notice: "Template \"#{@app_template.name}\" criado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @app_template.update(app_template_params)
      redirect_to app_templates_path, notice: "Template \"#{@app_template.name}\" atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @app_template.name
    @app_template.destroy
    redirect_to app_templates_path, notice: "Template \"#{name}\" removido."
  end

  # Renders the compose with the submitted variable values, runs the
  # host-path/socket guard, then shells the exact same `docker stack deploy`
  # invocation GitDeployer uses — the result is a normal stack, visible on
  # the regular Stacks listing, nothing template-specific persists past
  # this request.
  def deploy
    stack_name = params[:stack_name].to_s.strip
    if stack_name.blank? || !stack_name.match?(/\A[a-z0-9][a-z0-9_-]*\z/)
      return redirect_to app_template_path(@app_template), alert: "Nome do stack inválido (a-z0-9-_, começando com letra/número)."
    end

    values = params[:values].is_a?(ActionController::Parameters) ? params[:values].to_unsafe_h : {}
    rendered = @app_template.render_compose(values)
    safe, reason = AppTemplate.check_safety(rendered)
    unless safe
      return redirect_to app_template_path(@app_template), alert: "Template bloqueado: #{reason}"
    end

    output, success = deploy_stack(stack_name, rendered)
    AuditLog.record(user: Current.user, action: "deploy_app_template", target_type: "AppTemplate",
                     target_id: @app_template.id, metadata: { stack_name: stack_name, success: success },
                     ip_address: request.remote_ip)

    if success
      redirect_to stacks_path, notice: "Stack \"#{stack_name}\" deployado a partir de \"#{@app_template.name}\"."
    else
      redirect_to app_template_path(@app_template), alert: "Deploy falhou: #{output.to_s.first(500)}"
    end
  end

  private

  def deploy_stack(stack_name, compose_yaml)
    require "open3"
    require "tmpdir"
    host = active_environment&.effective_endpoint || "unix:///var/run/docker.sock"
    Dir.mktmpdir do |dir|
      compose_path = File.join(dir, "docker-compose.yml")
      File.write(compose_path, compose_yaml)
      out, err, status = Open3.capture3(
        "docker", "-H", host, "stack", "deploy", "--compose-file", compose_path, "--with-registry-auth", stack_name
      )
      [ [ out, err ].reject(&:empty?).join("\n"), status.success? ]
    end
  end

  def set_app_template
    @app_template = AppTemplate.find(params[:id])
  end

  def app_template_params
    params.require(:app_template).permit(:name, :description, :icon, :compose_yaml, variables: {})
  end
end
