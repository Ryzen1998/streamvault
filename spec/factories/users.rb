FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    # Set language defaults explicitly so the factory doesn't depend on
    # the before_validation :set_default_languages callback firing — if
    # that callback ever changes, every factory-built user would have
    # nil languages and fail validations downstream.
    preferred_languages { [ "ENG" ] }
    default_language { "ENG" }

    trait :admin do
      admin { true }
    end
  end
end
