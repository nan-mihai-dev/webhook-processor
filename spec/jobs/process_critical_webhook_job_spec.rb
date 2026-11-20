require 'rails_helper'

RSpec.describe ProcessCriticalWebhookJob, type: :job do
  it_behaves_like 'a webhook processing job', event_type: 'refund.created', handler: :process_refund

  it 'has a handler for every event type routed to the critical queue' do
    expect(described_class::EVENT_HANDLERS.keys).to match_array(WebhookCreator::CRITICAL_EVENT_TYPES)
  end

  it 'processes charge.disputed instead of ignoring it' do
    webhook = create(:webhook, event_type: 'charge.disputed')

    described_class.new.perform(webhook.id)

    expect(webhook.reload).to be_completed
  end
end
