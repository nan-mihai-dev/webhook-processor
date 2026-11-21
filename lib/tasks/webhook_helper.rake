namespace :webhook do
  desc "Generate a signed test webhook (signature v2: HMAC of \"<timestamp>.<body>\")"
  task :generate_signature, [:payload] => :environment do |t, args|
    unique_id = "evt_test_#{Time.now.to_i}_#{SecureRandom.hex(4)}"

    default_payload = {
      id: unique_id,
      source: "stripe",
      event_type: "payment.succeeded",
      amount: 5000
    }.to_json

    payload = args[:payload] || default_payload
    secret = ENV['WEBHOOK_SECRET']
    abort "WEBHOOK_SECRET is not set" if secret.blank?

    timestamp = Time.now.to_i.to_s
    signature = OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{payload}")

    puts "\n" + "="*60
    puts "Webhook Signature Generator (v2)"
    puts "="*60
    puts "\nPayload:"
    puts JSON.pretty_generate(JSON.parse(payload))
    puts "\nTimestamp: #{timestamp}"
    puts "Signature: #{signature}"
    puts "\nValid for #{WebhookSignatureVerifier::REPLAY_TOLERANCE.inspect} from now. Curl command:"
    puts <<~CURL
      curl -X POST http://localhost:3000/webhooks \\
        -H "Content-Type: application/json" \\
        -H "X-Webhook-Timestamp: #{timestamp}" \\
        -H "X-Webhook-Signature: #{signature}" \\
        -d '#{payload}'
    CURL
    puts "="*60 + "\n"
  end
end
