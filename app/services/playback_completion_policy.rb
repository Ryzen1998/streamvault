# frozen_string_literal: true

class PlaybackCompletionPolicy
  MOVIE_PERCENTAGE = 95
  EPISODE_RATIO = 0.98

  def self.movie_finished?(entry_or_percentage)
    percentage = if entry_or_percentage.respond_to?(:progress_percentage)
      entry_or_percentage.progress_percentage
    else
      entry_or_percentage
    end

    percentage.to_i >= MOVIE_PERCENTAGE
  end

  def self.episode_finished?(entry)
    return false unless entry

    duration = entry.duration_seconds.to_i
    duration.positive? && entry.progress_seconds.to_f.fdiv(duration) >= EPISODE_RATIO
  end

  def self.finished?(entry)
    entry.movie? ? movie_finished?(entry) : episode_finished?(entry)
  end

  # SQL twin of finished? for aggregates over playback_progresses: 1 when the
  # row counts as finished, else 0. Movies compare the rounded percentage, so
  # 94.5% already rounds up to 95%.
  def self.finished_sql
    movie = PlaybackProgress.content_types.fetch("movie")
    episode = PlaybackProgress.content_types.fetch("episode")
    <<~SQL.squish
      CASE WHEN duration_seconds > 0 AND (
        (content_type = #{movie} AND progress_seconds * 100.0 / duration_seconds >= #{MOVIE_PERCENTAGE - 0.5})
        OR (content_type = #{episode} AND progress_seconds * 1.0 / duration_seconds >= #{EPISODE_RATIO})
      ) THEN 1 ELSE 0 END
    SQL
  end
end
