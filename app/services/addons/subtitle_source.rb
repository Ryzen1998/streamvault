# frozen_string_literal: true

module Addons
  # External subtitle tracks from installed addons that serve the Stremio
  # `subtitles` resource (e.g. OpenSubtitles v3). Mirrors SubdlSubtitleProvider:
  # #search returns player tracks, #download fetches one track's file.
  #
  # Addons return arbitrary subtitle URLs, and the track id travels through the
  # browser, so each URL is wrapped in a signed token: the server only ever
  # downloads URLs it listed itself, and only from public addresses.
  class SubtitleSource
    TOKEN_PURPOSE = "addon-subtitle"
    TOKEN_TTL = 12.hours
    MAX_ADDONS = 4
    MAX_PER_LANGUAGE = 3
    MAX_BYTES = 2.megabytes
    MAX_REDIRECTS = 3

    # Codes addons use for StreamVault's languages (ISO 639-2/B and /T,
    # ISO 639-1, OpenSubtitles variants, English names).
    LANGUAGE_CODES = {
      "ENG" => %w[eng en english],
      "FRENCH" => %w[fre fra fr french],
      "GERMAN" => %w[ger deu de german],
      "SPANISH" => %w[spa spn es ea spanish],
      "ITALIAN" => %w[ita it italian],
      "JAPANESE" => %w[jpn ja japanese],
      "KOREAN" => %w[kor ko korean],
      "CHINESE" => %w[chi zho zh zht zhe chinese],
      "HINDI" => %w[hin hi hindi],
      "ARABIC" => %w[ara ar arabic],
      "PORTUGUESE" => %w[por pob pt pt-br portuguese],
      "RUSSIAN" => %w[rus ru russian],
      "DUTCH" => %w[dut nld nl dutch],
      "POLISH" => %w[pol pl polish],
      "TURKISH" => %w[tur tr turkish],
      "SWEDISH" => %w[swe sv swedish]
    }.flat_map { |language, codes| codes.map { |code| [ code, language ] } }.to_h.freeze

    def initialize(registry: Addons::Registry, download_connection: nil, logger: Rails.logger)
      @registry = registry
      @logger = logger
      @download_connection = download_connection || Faraday.new do |faraday|
        faraday.adapter Faraday.default_adapter
        faraday.options.timeout = 12
        faraday.options.open_timeout = 5
      end
    end

    def search(imdb_id:, type:, season: nil, episode: nil, filename: nil, preferred_languages: [], default_language: nil, **)
      return [] if imdb_id.blank?

      priority = ([ default_language ] + Array(preferred_languages)).compact.map(&:to_s).uniq
      content_id = type.to_s == "show" && season.present? && episode.present? ? "#{imdb_id}:#{season}:#{episode}" : imdb_id
      clients = @registry.entries.map { |entry| [ entry, entry.client(logger: @logger) ] }
        .select { |_entry, client| client.serves?("subtitles", type: type, id: content_id) }
        .first(MAX_ADDONS)

      tracks = clients.map do |entry, client|
        Thread.new { addon_tracks(entry, client, imdb_id, type, season, episode, filename) }
      end.flat_map(&:value)

      tracks.select { |track| priority.include?(track[:language]) }
        .group_by { |track| track[:language] }
        .sort_by { |language, _| priority.index(language) }
        .flat_map { |_language, language_tracks| language_tracks.first(MAX_PER_LANGUAGE) }
    rescue StandardError => e
      @logger.warn("[Addons::SubtitleSource] search failed: #{e.class}: #{e.message}")
      []
    end

    def download(payload)
      url = ApplicationToken.verify(payload, purpose: TOKEN_PURPOSE).fetch("url")
      body = fetch(url, MAX_REDIRECTS)
      body ? ServiceResult.success(utf8(body)) : ServiceResult.failure("Subtitle download failed")
    rescue ApplicationToken::Invalid, KeyError
      ServiceResult.failure("Invalid subtitle link")
    end

    private

    def addon_tracks(entry, client, imdb_id, type, season, episode, filename)
      result = client.subtitles(type, imdb_id, season: season, episode: episode, filename: filename)
      return [] unless result.success?

      addon_name = entry.name.presence || client.manifest_name.presence || "Addon"
      result.data.select { |subtitle| subtitle.is_a?(Hash) }
        .uniq { |subtitle| subtitle["url"] }
        .filter_map { |subtitle| track(subtitle, addon_name) }
    end

    # The URL itself stays server-side (some addons put config in it); the
    # browser only sees the signed track id.
    def track(subtitle, addon_name)
      url = subtitle["url"].to_s
      language = LANGUAGE_CODES[subtitle["lang"].to_s.strip.downcase]
      return unless language && url.match?(%r{\Ahttps?://}i)

      language_label = User::STREAM_LANGUAGE_OPTIONS.fetch(language)
      token = ApplicationToken.issue({ "url" => url }, purpose: TOKEN_PURPOSE, expires_in: TOKEN_TTL)
      {
        index: ExternalSubtitleService.stream_id("addon", token),
        position: nil,
        language: language,
        language_label: language_label,
        title: addon_name,
        codec: "srt",
        default: false,
        text_supported: true,
        forced: false,
        hearing_impaired: false,
        commentary: false,
        partial: false,
        quality: "full",
        quality_score: 0,
        external: true,
        source: "addon",
        label: "#{language_label} · #{addon_name}"
      }
    end

    # Follows redirects by hand so every hop passes the public-address check.
    def fetch(url, redirects_left)
      return unless ResolvedSource.public_url?(url)

      response = @download_connection.get(url)
      location = response.headers["location"]
      if (300..399).cover?(response.status) && location.present? && redirects_left.positive?
        return fetch(URI.join(url, location).to_s, redirects_left - 1)
      end
      return unless response.success? && response.body.to_s.bytesize <= MAX_BYTES

      response.body.to_s
    rescue Faraday::Error, URI::Error => e
      @logger.info("[Addons::SubtitleSource] download failed: #{e.class}")
      nil
    end

    # Subtitle files are usually UTF-8; older SRTs are often Windows-1252.
    def utf8(body)
      text = body.dup.force_encoding(Encoding::UTF_8)
      text = text.force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "") unless text.valid_encoding?
      text.delete_prefix("﻿")
    end
  end
end
