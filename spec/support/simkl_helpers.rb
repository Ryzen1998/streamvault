# frozen_string_literal: true

module SimklHelpers
  def with_simkl_client_id(value = "simkl-client-id")
    previous = ENV["SIMKL_CLIENT_ID"]
    ENV["SIMKL_CLIENT_ID"] = value
    yield
  ensure
    ENV["SIMKL_CLIENT_ID"] = previous
  end
end

RSpec.configure do |config|
  config.include SimklHelpers
end
