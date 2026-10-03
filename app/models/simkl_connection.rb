# frozen_string_literal: true

# A user's link to their own Simkl account. Finished movies and episodes are
# added to that account's Simkl history (see Simkl::HistorySync).
class SimklConnection < ApplicationRecord
  belongs_to :user

  encrypts :access_token

  validates :access_token, presence: true
end
