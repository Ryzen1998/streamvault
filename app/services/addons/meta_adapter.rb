# frozen_string_literal: true

module Addons
  # Normalizes Stremio addon `meta` / catalog-preview objects into the shapes
  # StreamVault's views expect (the same shapes produced by
  # Catalog::CinemetaClient#normalize_summary / #normalize_metadata).
  #
  # `type` is StreamVault's content type ("movie" / "show"); addon "series" is
  # mapped to "show" on the way out.
  class MetaAdapter
    class << self
      def summary(meta, type)
        return nil unless meta.is_a?(Hash)

        {
          imdb_id: identifier(meta),
          title: meta["name"].to_s,
          year: meta["releaseInfo"].presence || meta["year"],
          type: app_type(type),
          poster_url: meta["poster"],
          imdb_rating: meta["imdbRating"]
        }
      end

      def metadata(meta, type)
        return nil unless meta.is_a?(Hash)

        {
          imdb_id: identifier(meta),
          title: meta["name"].to_s,
          year: meta["year"].presence || meta["releaseInfo"],
          type: app_type(type),
          poster_url: meta["poster"],
          background_url: meta["background"],
          plot: meta["description"],
          genre: Array(meta["genres"]).join(", ").presence,
          director: Array(meta["director"]).join(", ").presence,
          actors: Array(meta["cast"]).join(", ").presence,
          rated: meta["certification"],
          imdb_rating: meta["imdbRating"],
          runtime: meta["runtime"],
          runtime_seconds: parse_runtime_seconds(meta["runtime"]),
          total_seasons: Array(meta["videos"]).filter_map { |video| video["season"] }.max,
          episodes: episodes(meta["videos"])
        }
      end

      def episodes(videos)
        Array(videos).select { |video| video.is_a?(Hash) && video["episode"] }.map do |video|
          {
            season: video["season"],
            episode: video["episode"],
            title: video["name"].presence || "Episode #{video['episode']}",
            released: video["released"].presence&.to_date&.to_s,
            imdb_id: video["id"],
            overview: video["overview"],
            runtime: video["runtime"],
            runtime_seconds: parse_runtime_seconds(video["runtime"])
          }
        end
      end

      def identifier(meta)
        (meta["imdb_id"].presence || meta["id"]).to_s
      end

      def app_type(type)
        type.to_s == "series" ? "show" : type.to_s
      end

      # Accepts ISO-8601 ("PT2H15M"), "2h 15m", or plain minutes.
      def parse_runtime_seconds(runtime)
        value = runtime.to_s.strip
        return if value.blank?

        if (iso = value.match(/\APT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?\z/i))
          total = (iso[1].to_i * 3600) + (iso[2].to_i * 60) + iso[3].to_i
          return total if total.positive?
        end

        hours = value[/(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hour|hours)\b/i, 1].to_f
        minutes = value[/(\d+(?:\.\d+)?)\s*(?:m|min|mins|minute|minutes)\b/i, 1].to_f
        return ((hours * 3600) + (minutes * 60)).round if hours.positive? || minutes.positive?

        numeric_minutes = value[/\A(\d+(?:\.\d+)?)\z/, 1]&.to_f
        (numeric_minutes * 60).round if numeric_minutes&.positive?
      end
    end
  end
end
