namespace :webhook do
  desc "Generate HMAC signature for testing"
  task :generate_signature, [:payload] => :environment do |t, args|
    unique_id = "evt_test_#{Time.now.to_i}_#{SecureRandom.hex(4)}"

    default_payload = {
      id: unique_id,
      source: "stripe",
      event_type: "payment.succeeded",
      amount: 5000,
      timestamp: Time.now.to_i
    }.to_json

    payload = args[:payload] || default_payload
    secret = ENV['WEBHOOK_SECRET']

    signature = OpenSSL::HMAC.hexdigest('SHA256', secret, payload)

    puts "\n" + "="*60
    puts "Webhook Signature Generator"
    puts "="*60
    puts "\nPayload:"
    puts JSON.pretty_generate(JSON.parse(payload))
    puts "\nSecret:"
    puts secret
    puts "\nSignature:"
    puts signature
    puts "\nCurl command:"
    puts <<~CURL
      curl -X POST http://localhost:3000/webhooks \\
        -H "Content-Type: application/json" \\
        -H "X-Webhook-Signature: #{signature}" \\
        -d '#{payload}'
    CURL
    puts "="*60 + "\n"
  end
end