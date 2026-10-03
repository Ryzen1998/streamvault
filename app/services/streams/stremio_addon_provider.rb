# frozen_string_literal: true

module Streams
  # Stream provider backed by a configured Stremio addon.
  #
  # One instance per installed addon (see Addons::Registry). The addon is
  # responsible for resolving playback URLs — StreamVault only consumes the
  # `url` it returns, so debrid credentials remain on the addon.
  class StremioAddonProvider
    def initialize(addon:, client: nil, parser: Addons::StreamParser.new, logger: Rails.logger)
      @addon = addon
      @client = client || addon.client(logger: logger)
      @parser = parser
      @logger = logger
    end

    def streams(imdb_id, type, season: nil, episode: nil, title: nil, preferred_languages: nil, default_language: nil)
      return ServiceResult.failure("IMDB ID is required") if imdb_id.blank?

      result = @client.streams(imdb_id, type, season: season, episode: episode)
      return result if result.failure?

      candidates = @parser.parse(result.data, provider: provider_label)
      ranked = Ranker.new(
        default_language: default_language,
        preferred_languages: preferred_languages
      ).call(candidates)
      ServiceResult.success(ranked)
    end

    # Distinct label per addon so the resolver interleaves results from
    # different addons as separate groups.
    def provider_label
      name = @addon.respond_to?(:name) ? @addon.name.presence : nil
      "Streams::StremioAddonProvider[#{name || base_url}]"
    end

    def base_url
      @client.base_url
    end

    def resolve_base_urls
      [ base_url ]
    end
  end
end
