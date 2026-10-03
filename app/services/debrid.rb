# frozen_string_literal: true

require "digest"

# The debrid service every stream is resolved through. One account serves the
# whole instance: admins configure it under Admin -> Debrid (DebridAccount,
# encrypted at rest), with DEBRID_SERVICE / DEBRID_API_KEY as a bootstrap
# fallback. Users never supply or see a key.
module Debrid
  SERVICES = {
    "torbox" => {
      name: "TorBox",
      key_url: "https://torbox.app/settings",
      # API host plus the CDN domains from TorBox's published allowlist
      # (support.torbox.app, "URLs to whitelist").
      hosts: %w[torbox.app tb-cdn.cx tb-cdn.earth tb-cdn.io tb-cdn.pw tb-cdn.sh tb-cdn.st tb-cdn.to]
    },
    "realdebrid" => {
      name: "RealDebrid",
      key_url: "https://real-debrid.com/apitoken",
      hosts: %w[real-debrid.com]
    }
  }.freeze

  Account = Struct.new(:service, :api_key, keyword_init: true) do
    def name
      SERVICES.fetch(service)[:name]
    end

    def torbox?
      service == "torbox"
    end

    def realdebrid?
      service == "realdebrid"
    end

    # Identifies the account in cache keys without exposing the key itself.
    def fingerprint
      "#{service}-#{Digest::SHA256.hexdigest(api_key.to_s).first(12)}"
    end

    def redact(text)
      api_key.present? ? text.to_s.gsub(api_key, "[REDACTED]") : text.to_s
    end

    def verify
      client = torbox? ? TorboxService.new(api_key) : RealDebridService.new(api_key)
      client.verify_key
    end

    # Keep the key out of logs and error messages.
    def inspect
      "#<Debrid::Account service=#{service.inspect}>"
    end
    alias_method :to_s, :inspect
  end

  module_function

  def current
    from_database || from_environment
  end

  def configured?
    current.present?
  end

  def from_database
    account = DebridAccount.current
    Account.new(service: account.service, api_key: account.api_key) if account
  rescue ActiveRecord::StatementInvalid
    nil
  end

  def from_environment
    service = ENV["DEBRID_SERVICE"].to_s.strip.downcase
    api_key = ENV["DEBRID_API_KEY"].to_s.strip
    return if api_key.blank? || !SERVICES.key?(service)

    Account.new(service: service, api_key: api_key)
  end
end
