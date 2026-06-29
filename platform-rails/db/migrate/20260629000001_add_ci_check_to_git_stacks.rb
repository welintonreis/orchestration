class AddCiCheckToGitStacks < ActiveRecord::Migration[8.1]
  def change
    change_table :git_stacks, bulk: true do |t|
      t.boolean :ci_check_enabled,    default: false
      t.string  :ci_gitlab_url                        # e.g. https://gitlab.redhusky.com.br
      t.string  :ci_project_id                        # numeric project ID or namespace/project
      t.string  :ci_token_ciphertext                  # GitLab project/personal access token
    end
  end
end
