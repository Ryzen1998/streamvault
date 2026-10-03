FactoryBot.define do
  factory :addon do
    sequence(:url) { |n| "https://addon#{n}.example.com/manifest.json" }
    name { "Test Addon" }
    manifest_id { "org.test.addon" }
    manifest_types { %w[movie series] }
    enabled { true }
    position { 0 }

    trait :disabled do
      enabled { false }
    end
  end
end
