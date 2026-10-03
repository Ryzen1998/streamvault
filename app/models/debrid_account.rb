# frozen_string_literal: true

# The instance-wide debrid account, managed by admins (Admin -> Debrid). Only
# one row is used; see Debrid.current for how the app reads it.
class DebridAccount < ApplicationRecord
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
end
