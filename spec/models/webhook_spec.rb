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
end