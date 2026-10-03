# frozen_string_literal: true

module Playback
  # Per-account watch totals for the admin user list, from grouped queries
  # over playback progress (no per-user N+1).
  class AccountSummaries
    Summary = Struct.new(:watched_seconds, :finished_count, :last_watched_at, keyword_init: true)
    EMPTY = Summary.new(watched_seconds: 0, finished_count: 0, last_watched_at: nil).freeze

    def self.for(users)
      progress = PlaybackProgress.where(user_id: users.map(&:id)).group(:user_id)
      seconds = progress.sum(:progress_seconds)
      finished = progress.sum(Arel.sql(PlaybackCompletionPolicy.finished_sql))
      last_watched = progress.maximum(:watched_at)

      users.to_h do |user|
        summary = Summary.new(
          watched_seconds: seconds.fetch(user.id, 0).to_i,
          finished_count: finished.fetch(user.id, 0).to_i,
          last_watched_at: last_watched[user.id]
        )
        [ user.id, summary ]
      end
    end
  end
end
