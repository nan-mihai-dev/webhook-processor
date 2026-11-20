require 'rails_helper'

RSpec.describe Webhook, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      webhook = build(:webhook)
      expect(webhook).to be_valid
    end

    it 'requires external_id' do
      webhook = build(:webhook, external_id: nil)
      expect(webhook).not_to be_valid
      expect(webhook.errors[:external_id]).to include("can't be blank")
    end

    it 'requires external_id to be unique within a source' do
      create(:webhook, source: 'stripe', external_id: 'evt_duplicate')
      duplicate = build(:webhook, source: 'stripe', external_id: 'evt_duplicate')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:external_id]).to include("has already been taken")
    end

    it 'allows the same external_id from a different source' do
      create(:webhook, source: 'stripe', external_id: 'evt_duplicate')
      other = build(:webhook, source: 'github', external_id: 'evt_duplicate')
      expect(other).to be_valid
    end

  end

  describe 'status enum' do
    it 'defaults to pending' do
      webhook = create(:webhook)
      expect(webhook.pending?).to be true
      expect(webhook.status).to eq('pending')
    end

    it 'can transition to completed' do
      webhook = create(:webhook)
      webhook.completed!

      expect(webhook.completed?).to be true
      expect(webhook.status).to eq('completed')
    end

    it 'can transition to failed' do
      webhook = create(:webhook)
      webhook.failed!

      expect(webhook.failed?).to be true
      expect(webhook.status).to eq('failed')
    end
  end

  describe 'stuck detection' do
    # Builds a webhook whose last change happened `age` ago.
    def webhook_aged(age, **attrs)
      travel_to(age.ago) { create(:webhook, **attrs) }
    end

    let!(:old_pending)       { webhook_aged(6.minutes, status: :pending) }
    let!(:fresh_pending)     { webhook_aged(4.minutes, status: :pending) }
    let!(:stale_processing)  { create(:webhook, status: :processing, processing_started_at: 11.minutes.ago) }
    let!(:legacy_processing) { create(:webhook, status: :processing, processing_started_at: nil) }
    let!(:fresh_processing)  { create(:webhook, status: :processing, processing_started_at: 9.minutes.ago) }
    let!(:old_finished) do
      %i[completed failed ignored].map { |status| webhook_aged(1.hour, status: status) }
    end

    it '.stuck returns old pending and abandoned processing webhooks only' do
      expect(Webhook.stuck).to contain_exactly(old_pending, stale_processing, legacy_processing)
    end

    it '#stuck? agrees with the .stuck scope' do
      stuck_ids = Webhook.stuck.pluck(:id)
      Webhook.find_each do |webhook|
        expect(webhook.stuck?).to eq(stuck_ids.include?(webhook.id)), "mismatch for #{webhook.status} ##{webhook.id}"
      end
    end
  end

  describe '#requeue_if_stuck!' do
    let(:webhook) { travel_to(6.minutes.ago) { create(:webhook, status: :pending) } }

    it 'increments reenqueue_count and returns :reenqueued' do
      expect(webhook.requeue_if_stuck!).to eq(:reenqueued)
      expect(webhook.reload.reenqueue_count).to eq(1)
    end

    it 'gives up after MAX_REENQUEUES re-enqueues: marks failed with a message' do
      webhook.update_columns(reenqueue_count: Webhook::MAX_REENQUEUES)

      expect(webhook.requeue_if_stuck!).to eq(:gave_up)
      webhook.reload
      expect(webhook).to be_failed
      expect(webhook.last_error).to eq("Gave up after #{Webhook::MAX_REENQUEUES} re-enqueues (stuck in pending)")
    end

    it 'returns :skipped when a worker finished it after it was loaded (re-checked under the lock)' do
      stale_copy = Webhook.find(webhook.id)
      Webhook.where(id: webhook.id).update_all(status: 'completed')

      expect(stale_copy.requeue_if_stuck!).to eq(:skipped)
      expect(webhook.reload.reenqueue_count).to eq(0)
    end
  end
end
