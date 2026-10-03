FactoryBot.define do
  factory :debrid_account do
    service { "realdebrid" }
    api_key { "test_key" }

    trait :torbox do
      service { "torbox" }
      api_key { "tb_test_key" }
    end
  end
end
