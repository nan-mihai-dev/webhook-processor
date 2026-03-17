FactoryBot.define do
  factory :webhook do #-> creates a template name :webhook
    sequence(:external_id) { |n| "evt_#{SecureRandom.hex(8)}_#{n}" } # -> generates unique IDs
    source { "stripe" }
    event_type { "payment.succeeded" }
    payload { '{"amount": 5000, "currency": "usd"}' }
    status { :pending }
  end
end