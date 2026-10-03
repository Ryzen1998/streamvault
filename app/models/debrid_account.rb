# frozen_string_literal: true

# The instance-wide debrid account, managed by admins (Admin -> Debrid). Only
# one row is used; see Debrid.current for how the app reads it.
class DebridAccount < ApplicationRecord
  EXPIRY_WARNING = 7.days

  encrypts :api_key

  validates :service, inclusion: { in: Debrid::SERVICES.keys }
  validates :api_key, presence: true

  def self.current
    order(:id).first
  end

  def service_name
    Debrid::SERVICES.dig(service, :name) || service
  end

  def to_debrid
    Debrid::Account.new(service: service, api_key: api_key)
  end

  # Records a Debrid::Account#verify result. A failed check keeps the last
  # known plan and expiry.
  def apply_verification(result)
    if result.success?
      assign_attributes(verified_at: Time.current, last_error: nil, **result.data.slice(:plan, :expires_at))
    else
      assign_attributes(verified_at: nil, last_error: result.error_message)
    end
  end

  # The subscription lapses within EXPIRY_WARNING (or already has); every
  # user's streaming stops when it does.
  def expiring?
    expires_at.present? && expires_at <= EXPIRY_WARNING.from_now
  end

  def expired?
    expires_at.present? && expires_at.past?
  end
end
