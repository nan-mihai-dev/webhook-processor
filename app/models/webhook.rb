class Webhook < ApplicationRecord
  after_initialize :set_default_status, if: :new_record?

  validates :external_id, presence: true, uniqueness: { scope: :source }
  validates :source, presence: true
  validates :event_type, presence: true
  validates :payload, presence: true

  # A processing claim older than this is treated as abandoned (e.g. the worker was killed).
  CLAIM_TIMEOUT = 10.minutes

  # Status enum
  enum :status, {
    pending: 'pending',
    processing: 'processing',
    completed: 'completed',
    failed: 'failed',
    ignored: 'ignored' # no handler for the event type
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

  # Terminal statuses: never process again.
  def finished?
    completed? || ignored?
  end

  # Another worker claimed this webhook recently. A nil processing_started_at
  # (claimed before the column existed) counts as stale.
  def claim_active?
    processing? && processing_started_at.present? && processing_started_at > CLAIM_TIMEOUT.ago
  end

  # Atomically claims the webhook for processing (SELECT ... FOR UPDATE, which also
  # reloads the row). Returns false if it's finished or another worker holds a live
  # claim. The lock is held only for this check-and-set; the work happens outside it.
  def claim_for_processing!
    with_lock do
      next false if finished? || claim_active?

      update!(status: :processing, processing_started_at: Time.current)
      true
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
