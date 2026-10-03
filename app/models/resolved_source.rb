# frozen_string_literal: true

require "ipaddr"
require "socket"
require "uri"

class ResolvedSource
  PURPOSE = "resolved-source"
  TOKEN_TTL = 12.hours
  REALDEBRID_HOSTS = %w[real-debrid.com download.real-debrid.com streaming.real-debrid.com].freeze
  # Direct debrid download hosts: the services StreamVault resolves through
  # itself (Debrid::SERVICES) plus other well-known ones. Addons are expected to
  # proxy their own media (see Addons::Registry), but when an addon redirects
  # to a debrid host we still trust it.
  DEBRID_HOSTS = (Debrid::SERVICES.values.flat_map { |service| service[:hosts] } + %w[
    alldebrid.com
    premiumize.me
    debrid-link.com
    debrid-link.fr
    offcloud.com
    put.io
    pikpak.com
    seedr.cc
  ]).uniq.freeze
  PRIVATE_NETWORKS = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
    172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16
    198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
    ::1/128 fc00::/7 fe80::/10 ff00::/8
  ].map { |range| IPAddr.new(range) }.freeze

  class Invalid < StandardError; end

  attr_reader :url, :filename, :upstream_headers

  def initialize(url:, filename: nil, upstream_headers: {})
    @url = url.to_s
    @filename = filename.to_s.presence || inferred_filename
    # Addon-provided headers the source host requires (Stremio proxyHeaders).
    @upstream_headers = Streams::ProxyHeaders.sanitize(upstream_headers)
    raise Invalid, "untrusted stream host" unless trusted_host?

    freeze
  end

  def self.issue(user:, url:, filename: nil, upstream_headers: {})
    source = new(url: url, filename: filename, upstream_headers: upstream_headers)
    ApplicationToken.issue(
      {
        "user_id" => user.id,
        "url" => source.url,
        "filename" => source.filename,
        "upstream_headers" => source.upstream_headers
      },
      purpose: PURPOSE,
      expires_in: TOKEN_TTL
    )
  end

  def self.resolve(token:, user:, verify_dns: true)
    payload = ApplicationToken.verify(token, purpose: PURPOSE)
    raise Invalid, "source belongs to another user" unless payload.fetch("user_id").to_i == user.id

    source = new(
      url: payload.fetch("url"),
      filename: payload["filename"],
      upstream_headers: payload["upstream_headers"]
    )
    raise Invalid, "stream host did not resolve publicly" if verify_dns && !source.public_address?

    source
  rescue ApplicationToken::Invalid, KeyError
    raise Invalid, "invalid or expired source"
  end

  def request_headers
    # Addon-provided headers first; the instance RealDebrid key is only added
    # for RealDebrid links (sending a debrid key to any other host would leak it).
    headers = upstream_headers.dup
    debrid = Debrid.current if realdebrid_host?
    headers["Authorization"] = "Bearer #{debrid.api_key}" if debrid&.realdebrid?
    headers
  end

  def public_address?
    self.class.public_url?(url)
  end

  # SSRF guard reused before any server-side fetch. Returns true only when the
  # URL is HTTP(S) with a host that resolves exclusively to public addresses.
  def self.public_url?(value)
    uri = URI.parse(value.to_s)
    return false unless uri.is_a?(URI::HTTP) && uri.host.present?

    addresses = Addrinfo.getaddrinfo(uri.host, nil, :UNSPEC, :STREAM).map(&:ip_address).uniq
    addresses.any? && addresses.none? { |address| private_address?(address) }
  rescue URI::InvalidURIError, SocketError
    false
  end

  def self.private_address?(address)
    ip = IPAddr.new(address)
    PRIVATE_NETWORKS.any? { |network| network.include?(ip) }
  rescue IPAddr::InvalidAddressError
    true
  end

  def to_h
    { url: url, filename: filename }
  end

  private

  def uri
    @uri ||= URI.parse(url)
  rescue URI::InvalidURIError
    raise Invalid, "invalid stream URL"
  end

  def trusted_host?
    return false unless uri.is_a?(URI::HTTPS) && uri.host.present?
    # Open trust: an installed addon may return playable URLs on per-service
    # proxies / CDNs that cannot be allow-listed. The public-address guard still
    # applies (see ResolvedSource.public_url?).
    return true if Addons::Registry.open_trust?

    host = uri.host.downcase
    trusted_hostnames.any? { |allowed| host == allowed || host.end_with?(".#{allowed}") }
  end

  # Debrid download hosts plus the configured addon hosts (which proxy their
  # own resolved media) and any operator-supplied stream-source hosts.
  def trusted_hostnames
    (DEBRID_HOSTS + Addons::Registry.trusted_hosts + Addons::Registry.proxy_hosts).uniq
  end

  def realdebrid_host?
    host = uri.host.to_s.downcase
    REALDEBRID_HOSTS.any? { |allowed| host == allowed || host.end_with?(".#{allowed}") }
  end

  def inferred_filename
    File.basename(uri.path.to_s).presence || "stream"
  end
end
