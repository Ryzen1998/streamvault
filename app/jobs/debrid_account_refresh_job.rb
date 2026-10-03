# frozen_string_literal: true

# Re-checks the instance debrid key daily so Admin -> Debrid shows a current
# plan and expiry, and admins hear about a lapsing subscription in time.
class DebridAccountRefreshJob < ApplicationJob
  queue_as :default

  def perform
    account = DebridAccount.current
    return unless account

    account.apply_verification(account.to_debrid.verify)
    account.save!
  end
end
