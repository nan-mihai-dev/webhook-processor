require 'rails_helper'
require 'rake'

RSpec.describe 'rake webhook:generate_signature' do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?('webhook:generate_signature') }

  let(:task) { Rake::Task['webhook:generate_signature'] }
  let(:payload) { '{"id":"evt_rake","source":"stripe","event_type":"order.shipped"}' }

  after { task.reenable }

  it 'prints a v2 timestamp and signature that the verifier accepts with legacy disabled' do
    output = capture_stdout { task.invoke(payload) }

    timestamp = output[/^Timestamp: (\d+)$/, 1]
    signature = output[/^Signature: (\h{64})$/, 1]
    expect(timestamp).to be_present
    expect(signature).to be_present
    expect(output).to include("X-Webhook-Timestamp: #{timestamp}", "X-Webhook-Signature: #{signature}")

    expect(
      WebhookSignatureVerifier.verify!(payload: payload, signature: signature, timestamp: timestamp, allow_legacy: false)
    ).to be true
  end

  it 'does not print the secret' do
    output = capture_stdout { task.invoke(payload) }
    expect(output).not_to include(ENV.fetch('WEBHOOK_SECRET'))
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
