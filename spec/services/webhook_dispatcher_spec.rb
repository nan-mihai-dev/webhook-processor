require 'rails_helper'

RSpec.describe WebhookDispatcher do
  describe '.dispatch' do
    it 'sends critical event types to ProcessCriticalWebhookJob' do
      webhook = create(:webhook, event_type: 'refund.created')
      allow(ProcessCriticalWebhookJob).to receive(:perform_async)

      expect(described_class.dispatch(webhook)).to eq(ProcessCriticalWebhookJob)
      expect(ProcessCriticalWebhookJob).to have_received(:perform_async).with(webhook.id)
    end

    it 'sends every other event type to ProcessWebhookJob' do
      webhook = create(:webhook, event_type: 'order.shipped')
      allow(ProcessWebhookJob).to receive(:perform_async)

      expect(described_class.dispatch(webhook)).to eq(ProcessWebhookJob)
      expect(ProcessWebhookJob).to have_received(:perform_async).with(webhook.id)
    end
  end
end
