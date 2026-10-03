# frozen_string_literal: true

module Streams
  # Sanitizes Stremio `behaviorHints.proxyHeaders.request` values.
  #
  # These headers tell the client which request headers a stream URL needs (some
  # hosts gate on User-Agent/Referer/Authorization). They originate from the
  # addon rather than the client, but they still flow into HTTP requests and
  # FFmpeg arguments, so malformed names/values and transport-level headers are
  # stripped here — the single chokepoint for both.
  module ProxyHeaders
    MAX_HEADERS = 20
    MAX_VALUE_BYTES = 4096
    TOKEN = /\A[A-Za-z0-9!#$%&'*+\-.^_`|~]+\z/.freeze

    # Hop-by-hop / transport headers, plus anything that could redirect or
    # truncate the request if supplied by an addon.
    BLOCKED = %w[
      host range content-length content-range connection transfer-encoding te
      trailer upgrade expect keep-alive via forwarded proxy-authorization
      proxy-connection proxy-authenticate x-forwarded-for x-forwarded-host
      x-forwarded-proto
    ].freeze

    module_function

    def sanitize(raw)
      return {} unless raw.is_a?(Hash)

      headers = {}
      raw.each do |key, value|
        break if headers.size >= MAX_HEADERS

        name = key.to_s.strip
        next if name.empty? || !name.match?(TOKEN) || BLOCKED.include?(name.downcase)

        value = value.to_s
        next if value.empty? || value.length > MAX_VALUE_BYTES || value.match?(/[\r\n\0]/)

        headers[canonical(name)] = value
      end
      headers
    end

    def canonical(name)
      name.split("-").map { |part| part.empty? ? part : "#{part[0].upcase}#{part[1..].to_s.downcase}" }.join("-")
    end
  end
end
