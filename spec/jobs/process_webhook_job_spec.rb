require 'rails_helper'

RSpec.describe ProcessWebhookJob, type: :job do
  let(:webhook) { create(:webhook, event_type: 'test.event') }

  describe '#perform' do
    it 'marks webhook as processing' do
      described_class.new.perform(webhook.id)

      webhook.reload
      expect(webhook.processing? || webhook.completed?).to be true
    end

    it 'marks webhook as completed on success' do
      described_class.new.perform(webhook.id)

      webhook.reload
      expect(webhook.completed?).to be true
      expect(webhook.processed_at).to be_present
    end

    it 'sets processed_at timestamp' do

      described_class.new.perform(webhook.id)

      webhook.reload
      expect(webhook.processed_at).to be_present
    end

    context 'with payment.succeeded event' do
      let(:webhook) do
        create(:webhook,
               event_type: 'payment.succeeded',
               payload: '{"amount": 5000, "customer": "cus_123"}')
      end

      it 'processes successfully' do
        expect {
          described_class.new.perform(webhook.id)
        }.not_to raise_error

        webhook.reload
        expect(webhook.completed?).to be true
      end
    end

    context 'with order.shipped event' do
      let(:webhook) do
        create(:webhook,
               event_type: 'order.shipped',
               payload: '{"order_id": "ord_123"}')
      end

      it 'processes successfully' do
        expect {
          described_class.new.perform(webhook.id)
        }.not_to raise_error

        webhook.reload
        expect(webhook.completed?).to be true
      end
    end

    context 'when webhook not found' do
      it 'skips silently without raising' do
        expect {
          described_class.new.perform(99999)
        }.not_to raise_error
      end
    end

    context 'when processing fails' do
      it 'marks webhook as failed' do
        # Make the job fail by causing an error
        allow_any_instance_of(ProcessWebhookJob).to receive(:process_test).and_raise(StandardError)

        begin
          described_class.new.perform(webhook.id)
        rescue StandardError
          # Expected to raise
        end

        webhook.reload
        expect(webhook.failed?).to be true
      end
    end
  end
end