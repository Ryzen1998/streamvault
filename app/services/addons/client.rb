# frozen_string_literal: true

require "digest"

module Addons
  # Client for a single Stremio addon, implemented against the addon protocol
  # (https://stremio.github.io/stremio-addon-sdk/protocol.html):
  #
  #   GET {base}/manifest.json
  #   GET {base}/stream/{type}/{id}.json          -> { "streams": [...] }
  #   GET {base}/catalog/{type}/{id}.json         -> { "metas": [...] }
  #   GET {base}/meta/{type}/{id}.json            -> { "meta": {...} }
  #
  # `type` is "movie" or "series"; `id` is an IMDB id (tt123) or, for episodes,
  # "tt123:season:episode". The client never sends debrid credentials — the
  # addon is responsible for resolving playback URLs.
  class Client
    REQUEST_TIMEOUT = 30
    OPEN_TIMEOUT = 5
    MANIFEST_TTL = 1.hour
    CACHE_TTL = 5.minutes

    attr_reader :base_url

    def initialize(url:, connection: nil, cache: Rails.cache, logger: Rails.logger)
      @base_url = self.class.normalize_base_url(url)
      @cache = cache
      @logger = logger
      @connection = connection || Faraday.new do |faraday|
        faraday.response :json
        faraday.response :follow_redirects
        faraday.adapter Faraday.default_adapter
        faraday.options.timeout = REQUEST_TIMEOUT
        faraday.options.open_timeout = OPEN_TIMEOUT
      end
    end

    # Strips a trailing /manifest.json so callers may pass either a manifest URL
    # or a bare base URL, while preserving any config path segment (uuid/password,
    # base64 config, alias, ...).
    def self.normalize_base_url(url)
      url.to_s.strip.sub(%r{/manifest\.json\z}, "").delete_suffix("/")
    end

    def manifest(force: false)
      cache_key = "addons/manifest/#{Digest::SHA256.hexdigest(@base_url)}"
      unless force
        cached = @cache.read(cache_key)
        return cached if cached
      end

      response = @connection.get("#{@base_url}/manifest.json")
      unless response.success? && response.body.is_a?(Hash)
        @logger.warn("[Addons::Client] manifest HTTP #{response.status} for #{@base_url}")
        return {}
      end

      @cache.write(cache_key, response.body, expires_in: MANIFEST_TTL)
      response.body
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      @logger.warn("[Addons::Client] manifest #{e.class} for #{@base_url}")
      {}
    rescue StandardError => e
      @logger.warn("[Addons::Client] manifest error: #{e.class}: #{e.message}")
      {}
    end

    # Validates a manifest URL without persisting anything. Used by the admin UI.
    def fetch_manifest!
      response = @connection.get("#{@base_url}/manifest.json")
      unless response.success? && response.body.is_a?(Hash) && response.body["id"].present?
        return ServiceResult.failure("Manifest request failed (HTTP #{response.status})")
      end

      @cache.write("addons/manifest/#{Digest::SHA256.hexdigest(@base_url)}", response.body, expires_in: MANIFEST_TTL)
      ServiceResult.success(response.body)
    rescue Faraday::TimeoutError
      ServiceResult.failure("Manifest request timed out")
    rescue Faraday::ConnectionFailed
      ServiceResult.failure("Could not connect to the addon")
    rescue StandardError => e
      ServiceResult.failure("Manifest error: #{e.message}")
    end

    def streams(imdb_id, type, season: nil, episode: nil)
      return ServiceResult.failure("IMDB ID is required") if imdb_id.blank?

      response = @connection.get(stream_path(imdb_id, type, season: season, episode: episode))
      if response.success? && response.body.is_a?(Hash) && response.body["streams"]
        ServiceResult.success(Array(response.body["streams"]))
      elsif response.status == 404
        ServiceResult.success([])
      else
        @logger.warn("[Addons::Client] streams HTTP #{response.status} for #{@base_url}")
        ServiceResult.failure("Addon returned HTTP #{response.status}")
      end
    rescue Faraday::TimeoutError
      ServiceResult.failure("Addon stream request timed out")
    rescue Faraday::ConnectionFailed
      ServiceResult.failure("Could not connect to the addon")
    rescue StandardError => e
      @logger.warn("[Addons::Client] streams error: #{e.class}: #{e.message}")
      ServiceResult.failure("Addon stream request failed")
    end

    def catalogs
      Array(manifest["catalogs"]).select { |catalog| catalog.is_a?(Hash) && catalog["type"].present? && catalog["id"].present? }
    end

    def catalog(type, catalog_id, skip: nil, genre: nil)
      response = @connection.get(catalog_path(type, catalog_id, skip: skip, genre: genre))
      if response.success? && response.body.is_a?(Hash)
        ServiceResult.success(Array(response.body["metas"]))
      else
        ServiceResult.failure("Catalog returned HTTP #{response.status}")
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      ServiceResult.failure("Catalog request failed (#{e.class})")
    rescue StandardError => e
      @logger.warn("[Addons::Client] catalog error: #{e.class}: #{e.message}")
      ServiceResult.failure("Catalog request failed")
    end

    def meta(type, imdb_id)
      response = @connection.get("#{@base_url}/meta/#{media_type(type)}/#{imdb_id}.json")
      if response.success? && response.body.is_a?(Hash) && response.body["meta"]
        ServiceResult.success(response.body["meta"])
      else
        ServiceResult.failure("Meta returned HTTP #{response.status}")
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      ServiceResult.failure("Meta request failed (#{e.class})")
    rescue StandardError => e
      @logger.warn("[Addons::Client] meta error: #{e.class}: #{e.message}")
      ServiceResult.failure("Meta request failed")
    end

    def manifest_id
      manifest["id"]
    end

    def manifest_name
      manifest["name"]
    end

    def manifest_types
      Array(manifest["types"])
    end

    def stream_supported?
      Array(manifest["resources"]).any? do |resource|
        if resource.is_a?(Hash)
          resource["name"] == "stream"
        else
          resource.to_s == "stream"
        end
      end
    rescue StandardError
      false
    end

    def supports_type?(type)
      declared = manifest_types.map(&:to_s)
      return true if declared.empty?

      declared.include?(media_type(type).to_s)
    end

    def media_type(type)
      type.to_s == "show" || type.to_s == "series" ? "series" : "movie"
    end

    private

    def stream_path(imdb_id, type, season:, episode:)
      if media_type(type) == "series" && season.present? && episode.present?
        "#{@base_url}/stream/series/#{imdb_id}:#{season}:#{episode}.json"
      else
        "#{@base_url}/stream/movie/#{imdb_id}.json"
      end
    end

    def catalog_path(type, catalog_id, skip:, genre:)
      extras = {}
      extras["genre"] = genre if genre.present?
      extras["skip"] = skip if skip.present? && skip.to_i.positive?
      path = "#{@base_url}/catalog/#{media_type(type)}/#{catalog_id}"
      return "#{path}.json" if extras.empty?

      "#{path}/#{URI.encode_www_form(extras)}.json"
    end
  end
end
