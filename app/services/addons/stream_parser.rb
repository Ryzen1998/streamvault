# frozen_string_literal: true

module Addons
  # Normalizes Stremio addon stream objects into StreamCandidate values.
  #
  # Addons differ in where they put metadata:
  #   * some return `title`/`infoHash`/`seeders` (Torrentio shape)
  #   * others put the release name in `behaviorHints.filename` and the
  #     human-readable detail in `description` (Comet/AIOStreams shape)
  #
  # Only streams with a playable `url` are returned; `infoHash`-only entries
  # cannot be played by a browser without a torrent engine and are skipped.
  class StreamParser
    def initialize(parser: Streams::ReleaseParser.new, logger: Rails.logger)
      @parser = parser
      @logger = logger
    end

    def parse(raw_streams, provider:)
      candidates = Array(raw_streams).filter_map do |stream|
        next unless stream.is_a?(Hash)

        url = stream["url"].to_s
        next if url.blank?

        candidate_for(stream, url, provider)
      end

      skipped = Array(raw_streams).count { |stream| stream.is_a?(Hash) && stream["url"].to_s.blank? }
      @logger.info("[Addons::StreamParser] #{provider} parsed #{candidates.length} playable streams (#{skipped} without url)") if skipped.positive?
      candidates
    end

    private

    def candidate_for(stream, url, provider)
      behavior_hints = stream["behaviorHints"].is_a?(Hash) ? stream["behaviorHints"] : {}
      description = stream["description"].to_s
      filename = behavior_hints["filename"].to_s
      title = filename.presence || stream["title"].to_s.presence || stream["name"].to_s
      attributes = @parser.analyze(title: title, filename: filename.presence || description)
      size = behavior_hints["videoSize"] || @parser.size_bytes(description) || attributes[:raw_size]
      info_hash = stream["infoHash"].presence || info_hash_from_binge_group(behavior_hints["bingeGroup"])

      StreamCandidate.new(
        title: title,
        info_hash: info_hash,
        file_idx: stream["fileIdx"],
        name: stream["name"],
        quality: attributes[:quality].presence || @parser.quality(stream["name"].presence || title),
        seeders: seeders(stream, description),
        size: @parser.format_size(size),
        raw_size: size,
        cached: cached?(stream, description),
        filename: filename,
        resolve_url: url,
        languages: attributes[:languages],
        video_codec: attributes[:video_codec],
        audio_codec: attributes[:audio_codec],
        container: attributes[:container],
        compatibility_score: attributes[:compatibility_score],
        provider: provider,
        request_headers: proxy_request_headers(behavior_hints)
      )
    end

    # Stremio `behaviorHints.proxyHeaders.request` — headers the host requires
    # when fetching the stream `url`.
    def proxy_request_headers(behavior_hints)
      proxy = behavior_hints["proxyHeaders"]
      return {} unless proxy.is_a?(Hash)

      Streams::ProxyHeaders.sanitize(proxy["request"])
    end

    def seeders(stream, description)
      stream["seeders"] || description[/👤\s*(\d+)/, 1].to_i
    end

    # Comet encodes the info hash as the last segment of bingeGroup
    # ("comet|realdebrid|<sha1>"); AIOStreams uses descriptive segments
    # ("...|2160p|BluRay REMUX|FraMeSToR"). Only accept an actual hash.
    def info_hash_from_binge_group(value)
      value.to_s.split("|").reverse.find { |segment| segment.match?(/\A[0-9a-f]{40}\z/i) }
    end

    def cached?(stream, description)
      text = [ stream["name"], stream["title"], stream["description"], description ].compact.join(" ")
      text.include?("⚡") || text.match?(/\bcached\b/i)
    end
  end
end
