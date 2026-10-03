# frozen_string_literal: true

module Simkl
  # Adds the account's finished movies and episodes that Simkl hasn't seen yet
  # to its Simkl history. Rows are marked once Simkl accepts them, so a failed
  # push is retried by the next sync and nothing is sent twice.
  class HistorySync
    BATCH_SIZE = 100

    def initialize(connection, client: SimklClient.new(access_token: connection.access_token))
      @connection = connection
      @client = client
    end

    # → ServiceResult with the number of titles sent.
    def call
      sent = 0
      pending_entries.each_slice(BATCH_SIZE) do |batch|
        result = @client.add_to_history(**payload(batch))
        if result.failure?
          @connection.update!(last_error: result.error_message)
          return ServiceResult.failure(result.error_message)
        end

        PlaybackProgress.where(id: batch.map(&:id)).update_all(simkl_synced_at: Time.current)
        sent += batch.size
      end

      @connection.update!(last_synced_at: Time.current, last_error: nil)
      ServiceResult.success(sent)
    end

    private

    def pending_entries
      @connection.user.playback_progresses
        .where(simkl_synced_at: nil)
        .where(Arel.sql("(#{PlaybackCompletionPolicy.finished_sql}) = 1"))
        .order(:watched_at)
        .to_a
    end

    def payload(entries)
      movies, episodes = entries.partition(&:movie?)
      {
        movies: movies.map { |entry| { title: entry.title, ids: { imdb: entry.imdb_id }, watched_at: timestamp(entry) } },
        shows: episodes.group_by(&:imdb_id).map { |imdb_id, show_episodes| show(imdb_id, show_episodes) }
      }
    end

    def show(imdb_id, episodes)
      seasons = episodes.group_by(&:season_number).sort.map do |number, season_episodes|
        {
          number: number,
          episodes: season_episodes.sort_by(&:episode_number).map { |entry| { number: entry.episode_number, watched_at: timestamp(entry) } }
        }
      end
      { title: episodes.max_by(&:watched_at).title, ids: { imdb: imdb_id }, seasons: seasons }
    end

    def timestamp(entry)
      entry.watched_at.utc.iso8601
    end
  end
end
