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

      it 'enqueues ProcessCriticalWebhookJob for critical event types' do
        allow(ProcessCriticalWebhookJob).to receive(:perform_async)

        creator = described_class.new(**params).call

        expect(ProcessCriticalWebhookJob).to have_received(:perform_async)
                                               .with(creator.webhook.id)
      end

      it 'enqueues ProcessWebhookJob for standard event types' do
        allow(ProcessWebhookJob).to receive(:perform_async)

        creator = described_class.new(**params.merge(event_type: 'order.shipped')).call

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

    context 'with duplicate external_id from the same source' do
      let!(:existing) { create(:webhook, source: 'stripe', external_id: 'evt_123') }

      it 'does not create a new webhook' do
        expect {
          described_class.new(**params).call
        }.not_to change(Webhook, :count)
      end

      it 'returns a duplicate response with the existing id' do
        creator = described_class.new(**params).call

        expect(creator).to be_success
        expect(creator).to be_duplicate
        expect(creator.response).to eq(status: 'duplicate', webhook_id: existing.id)
      end

      it 'does not enqueue a job' do
        allow(ProcessCriticalWebhookJob).to receive(:perform_async)
        allow(ProcessWebhookJob).to receive(:perform_async)

        described_class.new(**params).call

        expect(ProcessCriticalWebhookJob).not_to have_received(:perform_async)
        expect(ProcessWebhookJob).not_to have_received(:perform_async)
      end

      it 'logs at info, not error' do
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:error)

        described_class.new(**params).call

        expect(Rails.logger).to have_received(:info).with(/Duplicate webhook source=stripe external_id=evt_123 existing_id=#{existing.id}/)
        expect(Rails.logger).not_to have_received(:error)
      end
    end

    context 'with duplicate external_id from a different source' do
      before { create(:webhook, source: 'github', external_id: 'evt_123') }

      it 'creates a new webhook' do
        expect {
          described_class.new(**params).call
        }.to change(Webhook, :count).by(1)
      end
    end

    context 'when a concurrent delivery wins the race' do
      # Both requests pass the duplicate check; the other one inserts first.
      let(:winner) { Webhook.find_by!(source: 'stripe', external_id: 'evt_123') }

      before do
        allow(ProcessCriticalWebhookJob).to receive(:perform_async)
      end

      it 'treats RecordNotUnique from the unique index as a duplicate' do
        allow(Webhook).to receive(:create!) do |attrs|
          create(:webhook, attrs)
          raise ActiveRecord::RecordNotUnique, 'duplicate key value violates unique constraint'
        end

        creator = described_class.new(**params).call

        expect(creator).to be_success
        expect(creator.response).to eq(status: 'duplicate', webhook_id: winner.id)
        expect(ProcessCriticalWebhookJob).not_to have_received(:perform_async)
      end

      it 'treats a uniqueness validation failure as a duplicate' do
        allow(Webhook).to receive(:create!) do |attrs|
          create(:webhook, attrs)
          record = Webhook.new(attrs)
          record.errors.add(:external_id, :taken)
          raise ActiveRecord::RecordInvalid, record
        end

        creator = described_class.new(**params).call

        expect(creator).to be_success
        expect(creator.response).to eq(status: 'duplicate', webhook_id: winner.id)
        expect(ProcessCriticalWebhookJob).not_to have_received(:perform_async)
      end

      it 're-raises RecordNotUnique if no existing row can be found' do
        allow(Webhook).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

        expect {
          described_class.new(**params).call
        }.to raise_error(ActiveRecord::RecordNotUnique)
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