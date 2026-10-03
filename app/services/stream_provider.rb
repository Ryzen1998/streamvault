# frozen_string_literal: true

# Factory that returns the configured stream provider(s).
#
# When one or more Stremio addons are installed (admin-managed, see
# Addons::Registry) they are the sole stream sources. Otherwise the legacy
# STREAM_PROVIDER configuration applies:
#   "torrentio" → Torrentio only (default)
#   "comet"     → configured Comet followed by Torrentio
#   "auto"      → configured Comet followed by Torrentio
#
# Each provider implements:
#   streams(imdb_id, type, season:, episode:, title:, preferred_languages:, default_language:)
#     → ServiceResult<Array<StreamCandidate>>
#   resolve_base_urls → Array<String> (for resolver origin validation)
module StreamProvider
  module_function

  # Returns an ordered array of provider instances. The first provider is
  # primary; subsequent ones are fallbacks used when the primary returns no
  # streams or fails to connect. Legacy providers resolve through the
  # instance debrid account (see Debrid).
  def providers(debrid: Debrid.current)
    addon_entries = Addons::Registry.entries
    if addon_entries.any?
      return addon_entries.map { |addon| Streams::StremioAddonProvider.new(addon: addon) }
    end

    torrentio = Streams::TorrentioProvider.new(debrid: debrid)
    setting = ENV.fetch("STREAM_PROVIDER", "torrentio").to_s.downcase
    return [ torrentio ] unless %w[comet auto].include?(setting)

    [ (CometService.new(debrid: debrid) if CometService.comet_url.present?), torrentio ].compact
  end

  # All origins from which the resolver may follow a provider URL.
  def resolve_base_urls
    addon_urls = Addons::Registry.entries.map(&:base_url).reject(&:blank?)
    return (addon_urls + extra_source_origins).uniq if addon_urls.any?

    urls = [ Streams::TorrentioProvider::BASE_URL, "https://torrentio.strem.fun" ]
    setting = ENV.fetch("STREAM_PROVIDER", "torrentio").to_s.downcase
    urls.unshift(CometService.comet_url) if %w[comet auto].include?(setting) && CometService.comet_url.present?
    urls.uniq
  end

  # Origins for operator-supplied stream-source hosts (proxy / CDN).
  def extra_source_origins
    Addons::Registry.proxy_hosts.map { |host| "https://#{host}" }
  end

  # Whether a resolve URL belongs to one of our own addon origins (which proxy
  # their own media) rather than an upstream debrid host. Direct origins are
  # probed directly, never through the Torrentio proxy.
  def direct_origin?(url)
    uri = URI.parse(url.to_s)
    return false unless uri.is_a?(URI::HTTP)

    origin_keys.include?([ uri.scheme, uri.host, uri.port ])
  rescue URI::InvalidURIError
    false
  end

  # [scheme, host, port] tuples for every configured addon / proxy origin.
  def origin_keys
    origins = Addons::Registry.entries.map(&:base_url) + extra_source_origins
    origins << CometService.comet_url if CometService.comet_url.present?
    origins.filter_map { |origin| origin_key(origin) }.uniq
  end

  def origin_key(url)
    uri = URI.parse(url.to_s)
    [ uri.scheme, uri.host, uri.port ] if uri.is_a?(URI::HTTP)
  rescue URI::InvalidURIError
    nil
  end

  # Hosts StreamVault trusts as playback sources: the configured addons (which
  # serve self-authenticating proxied URLs). See ResolvedSource.
  def trusted_stream_hosts
    Addons::Registry.trusted_hosts
  end
end
