# frozen_string_literal: true

module Addons
  # Resolves the configured addons from the database (admin-managed), falling
  # back to the STREMIO_ADDONS environment variable for bootstrap/testing.
  #
  # Each entry exposes the manifest base URL plus a cached-friendly identity;
  # the Registry is the single source of truth for the set of trusted addon
  # hosts used by the playback layer.
  module Registry
    ENTRIES_CACHE_KEY = "addons/registry/entries"
    OPEN_TRUST_CACHE_KEY = "addons/registry/open_trust"
    ENTRIES_TTL = 30.seconds

    Entry = Struct.new(:url, :name, :reference, keyword_init: true) do
      def base_url
        Addons::Client.normalize_base_url(url)
      end

      def host
        URI.parse(base_url).host
      rescue URI::InvalidURIError
        nil
      end

      def client(**options)
        Addons::Client.new(url: url, **options)
      end
    end

    module_function

    # Cached briefly so a single playback request (which may resolve up to
    # MAX_ATTEMPTS candidates) does not query the addons table per candidate.
    # Admin changes take effect within the TTL.
    def entries
      Rails.cache.fetch(ENTRIES_CACHE_KEY, expires_in: ENTRIES_TTL) do
        from_database.presence || from_environment
      end
    end

    def clients(**options)
      entries.map { |entry| entry.client(**options) }
    end

    def configured?
      entries.any?
    end

    # When true, playback trusts any HTTPS + public host returned by an
    # installed addon, rather than an explicit host allowlist. Addons delegate
    # playback to per-service proxies (StremThru, MediaFlow) and debrid CDNs, so
    # the playable host varies per stream and cannot be allow-listed up front.
    #
    # Enabled per addon via the admin UI, or globally with STREAM_SOURCE_TRUST=any.
    def open_trust?
      return true if ENV["STREAM_SOURCE_TRUST"].to_s.strip.downcase == "any"

      Rails.cache.fetch(OPEN_TRUST_CACHE_KEY, expires_in: ENTRIES_TTL) { trust_flagged_addon? }
    end

    def trust_flagged_addon?
      return false unless addons_table_available?

      Addon.enabled.where(trust_source_hosts: true).exists?
    rescue ActiveRecord::StatementInvalid
      false
    end
    private_class_method :trust_flagged_addon?

    # Hosts of every configured addon. Playback trusts these hosts because the
    # addon proxies its own resolved media (self-authenticating URLs).
    def trusted_hosts
      entries.filter_map(&:host).uniq
    end

    # Additional stream-source hosts supplied by the operator. Addons that use
    # an external proxy (StremThru, MediaFlow) or a debrid CDN return playable
    # URLs on hosts that cannot be derived from the manifest, so they must be
    # allow-listed explicitly via STREAM_SOURCE_HOSTS.
    def proxy_hosts
      ENV.fetch("STREAM_SOURCE_HOSTS", "").split(",").filter_map do |entry|
        value = entry.strip
        next if value.blank?

        value = "https://#{value}" unless value.include?("://")
        URI.parse(value).host&.downcase
      rescue URI::InvalidURIError
        nil
      end.uniq
    end

    def from_database
      return [] unless addons_table_available?

      Addon.enabled.ordered.map do |addon|
        Entry.new(url: addon.url, name: addon.display_name, reference: addon.id.to_s)
      end
    rescue ActiveRecord::StatementInvalid
      []
    end
    private_class_method :from_database

    def from_environment
      ENV.fetch("STREMIO_ADDONS", "")
        .split(",")
        .map(&:strip)
        .reject(&:blank?)
        .each_with_index
        .map { |url, index| Entry.new(url: url, name: nil, reference: "env-#{index}") }
    end
    private_class_method :from_environment

    def addons_table_available?
      ActiveRecord::Base.connection.data_source_exists?("addons")
    rescue StandardError
      false
    end
    private_class_method :addons_table_available?
  end
end
