# frozen_string_literal: true

# Encrypted, user-bound handle for a stream picked from a listing. Provider
# resolve URLs embed the instance debrid key (Torrentio: /resolve/torbox/<key>/...,
# Comet: a base64 config), so stream pickers post this token instead of the
# raw URL. Because the server issued it, its request headers can be trusted too.
class StreamSelection
  PURPOSE = "stream-selection"
  TOKEN_TTL = 12.hours
  FIELDS = %i[resolve_url filename raw_size video_codec compatibility_score request_headers].freeze

  class Invalid < StandardError; end

  def self.issue(user:, candidate:)
    candidate = StreamCandidate.from(candidate)
    payload = FIELDS.to_h { |field| [ field.to_s, candidate.public_send(field) ] }
    ApplicationToken.issue(payload.merge("user_id" => user.id), purpose: PURPOSE, expires_in: TOKEN_TTL)
  end

  def self.resolve(token:, user:)
    payload = ApplicationToken.verify(token, purpose: PURPOSE)
    raise Invalid, "selection belongs to another user" unless payload.fetch("user_id").to_i == user.id
    raise Invalid, "selection has no stream" if payload["resolve_url"].blank?

    StreamCandidate.new(**FIELDS.to_h { |field| [ field, payload[field.to_s] ] })
  rescue ApplicationToken::Invalid, KeyError
    raise Invalid, "invalid or expired stream selection"
  end
end
