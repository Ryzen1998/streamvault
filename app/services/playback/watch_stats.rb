# frozen_string_literal: true

module Playback
  # Watch statistics for one account, derived from its saved playback
  # positions. Times are approximate: a title counts up to the furthest point
  # reached, and activity lands on the day it was last watched.
  class WatchStats
    ACTIVITY_DAYS = 30
    TOP_SHOW_LIMIT = 5

    Result = Struct.new(:titles_count, :watched_seconds, :movies_finished, :episodes_finished,
      :in_progress_count, :shows_count, :activity, :top_shows, keyword_init: true) do
      def empty?
        titles_count.zero?
      end
    end
    Day = Struct.new(:date, :count, keyword_init: true)
    Show = Struct.new(:imdb_id, :title, :poster_url, :episodes_watched, :watched_seconds, keyword_init: true)

    def initialize(user, today: Time.zone.today)
      @user = user
      @today = today
    end

    def call
      entries = @user.playback_progresses.to_a
      finished, unfinished = entries.partition { |entry| PlaybackCompletionPolicy.finished?(entry) }

      Result.new(
        titles_count: entries.size,
        watched_seconds: entries.sum(&:progress_seconds),
        movies_finished: finished.count(&:movie?),
        episodes_finished: finished.count(&:episode?),
        in_progress_count: unfinished.count { |entry| entry.progress_seconds.positive? },
        shows_count: entries.select(&:episode?).map(&:imdb_id).uniq.size,
        activity: activity(entries),
        top_shows: top_shows(entries)
      )
    end

    private

    def activity(entries)
      first_day = @today - (ACTIVITY_DAYS - 1)
      counts = entries.map { |entry| entry.watched_at.in_time_zone.to_date }.tally
      (first_day..@today).map { |date| Day.new(date: date, count: counts.fetch(date, 0)) }
    end

    def top_shows(entries)
      shows = entries.select(&:episode?).group_by(&:imdb_id).map do |imdb_id, episodes|
        latest = episodes.max_by(&:watched_at)
        Show.new(
          imdb_id: imdb_id,
          title: latest.title,
          poster_url: latest.poster_url,
          episodes_watched: episodes.size,
          watched_seconds: episodes.sum(&:progress_seconds)
        )
      end
      shows.sort_by { |show| [ -show.episodes_watched, -show.watched_seconds ] }.first(TOP_SHOW_LIMIT)
    end
  end
end
