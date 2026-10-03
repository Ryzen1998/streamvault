FactoryBot.define do
  factory :simkl_connection do
    user
    access_token { "simkl-token" }
    username { "Simkl Tester" }
  end
end
