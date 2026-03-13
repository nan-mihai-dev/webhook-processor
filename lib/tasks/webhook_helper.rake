namespace :webhook do
  desc "Generate HMAC signature for testing"
  task :generate_signature, [:payload] => :environment do |t, args|
    # Better default payload with event_type
    payload = args[:payload] || '{"id":"evt_test_123","source":"stripe","event_type":"payment.succeeded","amount":5000}'
    secret = ENV['WEBHOOK_SECRET']

    signature = OpenSSL::HMAC.hexdigest('SHA256', secret, payload)

    puts "\n" + "="*60
    puts "Webhook Signature Generator"
    puts "="*60
    puts "\nPayload:"
    puts payload
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