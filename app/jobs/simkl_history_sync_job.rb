# frozen_string_literal: true

class SimklHistorySyncJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    connection = SimklConnection.find_by(user_id: user_id)
    return unless connection && SimklClient.configured?

    result = Simkl::HistorySync.new(connection).call
    Rails.logger.info("[SimklHistorySyncJob] user=#{user_id} #{result.success? ? "sent=#{result.data}" : "failed: #{result.error_message}"}")
  end
end
