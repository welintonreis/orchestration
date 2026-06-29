class ImagePullJob < ApplicationJob
  queue_as :default

  def perform(image:, tag:, user_id:, endpoint:)
    client = DockerClient.new(endpoint: endpoint)
    client.image_pull(image, tag: tag.presence || "latest")
    user = User.find_by(id: user_id)
    AuditLog.record(user: user, action: "image_pull",
                    metadata: { image: image, tag: tag })
  rescue => e
    user = User.find_by(id: user_id)
    AuditLog.record(user: user, action: "image_pull_failed",
                    metadata: { image: image, tag: tag, error: e.message })
  end
end
