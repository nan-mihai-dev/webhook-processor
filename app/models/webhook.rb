class Webhook < ApplicationRecord
  after_initialize :set_default_status, if: :new_record?

  validates :external_id, presence: true, uniqueness: true
  validates :source, presence: true
  validates :event_type, presence: true
  validates :payload, presence: true

  # Status enum
  enum :status, {
    pending: 'pending',
    processing: 'processing',
    completed: 'completed',
    failed: 'failed'
  }, default: :pending

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :pending_or_processing, -> { where(status: [:pending, :processing]) }
  scope :failed_for_retry, -> { where(status: :failed) }
  scope :by_source, -> (source) { where(source: source) }

  def self.stats_by_status
    Rails.cache.fetch('webhook_stats_by_status', expires_in: 5.minutes) do
      group(:status).count
    end
  end

  def self.stats_by_source
    Rails.cache.fetch('webhook_stats_by_source', expires_in: 5.minutes) do
      group(:source).count
    end
  end

  after_save :invalidate_caches
  after_destroy :invalidate_caches

  private
  def invalidate_caches
    Rails.cache.delete('webhook_stats_by_status')
    Rails.cache.delete('webhook_stats_by_source')
  end

  def self.retryable
    failed_for_retry.recent.limit(100)
  end

  def set_default_status
    self.status ||= 'pending'
  end
end
