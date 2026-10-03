# frozen_string_literal: true

# An installed Stremio addon. `url` is the addon's manifest URL as pasted by an
# administrator (e.g. https://aiostreams.example.com/stremio/<uuid>/<password>/manifest.json).
#
# StreamVault consumes the addon over the standard Stremio addon protocol
# (manifest / catalog / meta / stream). Playback relies on the addon returning
# playable `url`s (addon-proxied), so credentials for the upstream debrid
# services stay on the addon and are never stored here.
class Addon < ApplicationRecord
  MANIFEST_SUFFIX = "/manifest.json"

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:position, :id) }

  validates :url, presence: true
  validate :url_must_be_valid

  before_validation :normalize_url

  # Base URL used to build resource paths ({base}/catalog/..., {base}/stream/...).
  def manifest_base_url
    url.to_s.sub(%r{#{Regexp.escape(MANIFEST_SUFFIX)}\z}, "")
  end

  def host
    URI.parse(manifest_base_url).host
  rescue URI::InvalidURIError
    nil
  end

  def display_name
    name.presence || manifest_id.presence || host.presence || url
  end

  def supports_type?(*types)
    supported = Array(manifest_types).map(&:to_s)
    return true if supported.empty?

    types.map(&:to_s).any? { |type| supported.include?(type) }
  end

  private

  def normalize_url
    self.url = url.to_s.strip
    return if url.blank?
    return if url.end_with?(MANIFEST_SUFFIX)

    self.url = "#{url.delete_suffix('/')}#{MANIFEST_SUFFIX}"
  end

  def url_must_be_valid
    return if url.blank?

    uri = URI.parse(url)
    unless uri.is_a?(URI::HTTP) && uri.host.present?
      errors.add(:url, "must be an http(s) URL")
      return
    end

    errors.add(:url, "must point to a manifest.json") unless url.end_with?(MANIFEST_SUFFIX)
  rescue URI::InvalidURIError
    errors.add(:url, "is not a valid URL")
  end
end
