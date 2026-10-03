# frozen_string_literal: true

module Simkl
  # Adds the titles on the account's Simkl "Plan to Watch" list to its
  # Wishlist. Follows Simkl's sync rules: check /sync/activities first, read a
  # list in full only on the first import, and afterwards only what changed
  # since the saved activity time. Titles already in the Wishlist or Library
  # are left alone, and nothing is removed.
  class WatchlistImport
    # Simkl list type => [activities key, item key, StreamVault content type]
    LISTS = {
      "movies" => [ "movies", "movie", :movie ],
      "shows" => [ "tv_shows", "show", :show ]
    }.freeze

    def initialize(connection, client: SimklClient.new(access_token: connection.access_token))
      @connection = connection
      @client = client
    end

    # → ServiceResult with the number of titles added to the Wishlist.
    def call
      activities = @client.activities
      return record_failure(activities) if activities.failure?

      saved = (@connection.watchlist_activities || {}).dup
      added = 0
      LISTS.each do |type, (activity_key, item_key, content_type)|
        latest = activities.data.dig(activity_key, "plantowatch")
        next if latest.blank? || latest == saved[type]

        items = @client.plan_to_watch(type, date_from: saved[type])
        return record_failure(items) if items.failure?

        added += items.data.count { |item| add_to_wishlist(item[item_key], content_type) }
        saved[type] = latest
      end

      @connection.update!(watchlist_activities: saved, last_error: nil)
      ServiceResult.success(added)
    end

    private

    def add_to_wishlist(media, content_type)
      return false unless media.is_a?(Hash)

      imdb_id = media.dig("ids", "imdb").to_s
      return false unless imdb_id.match?(ContentRef::IMDB_ID_PATTERN) && media["title"].present?

      entries = @connection.user.collection_entries
      return false if entries.exists?(imdb_id: imdb_id)

      entries.create(
        imdb_id: imdb_id,
        content_type: content_type,
        list_state: :wishlist,
        title: media["title"],
        year: Integer(media["year"], exception: false),
        poster_url: poster_url(media["poster"])
      ).persisted?
    end

    # Simkl asks clients to load its images through wsrv.nl.
    def poster_url(path)
      "https://wsrv.nl/?url=https://simkl.in/posters/#{path}_ca.webp" if path.present?
    end

    def record_failure(result)
      @connection.update!(last_error: result.error_message)
      ServiceResult.failure(result.error_message)
    end
  end
end
