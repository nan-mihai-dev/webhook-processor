# spec/services/webhook_creator_spec.rb
require 'rails_helper'

RSpec.describe WebhookCreator do
  describe '#call' do
    let(:params) do
      {
        external_id: 'evt_123',
        source: 'stripe',
        event_type: 'payment.succeeded',
        payload: '{"amount": 5000}'
      }
    end

    context 'with valid parameters' do
      it 'creates a webhook' do
        expect {
          described_class.new(**params).call
        }.to change(Webhook, :count).by(1)
      end

      it 'enqueues ProcessWebhookJob' do
        allow(ProcessWebhookJob).to receive(:perform_async)

        creator = described_class.new(**params).call

        expect(ProcessWebhookJob).to have_received(:perform_async)
                                       .with(creator.webhook.id)
      end

      it 'returns success response' do
        creator = described_class.new(**params).call

        expect(creator).to be_success
        expect(creator.response[:status]).to eq('accepted')
        expect(creator.response[:webhook_id]).to be_present
      end
    end

    context 'with duplicate external_id' do
      before { create(:webhook, external_id: 'evt_123') }

      it 'does not create a new webhook' do
        expect {
          described_class.new(**params).call
        }.not_to change(Webhook, :count)
      end

      it 'returns duplicate message' do
        creator = described_class.new(**params).call

        expect(creator).to be_success
        expect(creator.response[:message]).to eq('Duplicate webhook')
      end

      it 'does not enqueue job' do
        allow(ProcessWebhookJob).to receive(:perform_async)

        described_class.new(**params).call

        expect(ProcessWebhookJob).not_to have_received(:perform_async)
      end
    end

    context 'with invalid parameters' do
      let(:invalid_params) do
        params.merge(source: nil) # source is required
      end

      it 'does not create webhook' do
        expect {
          described_class.new(**invalid_params).call
        }.not_to change(Webhook, :count)
      end

      it 'returns error response' do
        creator = described_class.new(**invalid_params).call

        expect(creator).not_to be_success
        expect(creator.response[:error]).to be_present
      end
    end
  end
end