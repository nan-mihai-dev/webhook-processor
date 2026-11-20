class Webhook < ApplicationRecord
  after_initialize :set_default_status, if: :new_record?

  validates :external_id, presence: true, uniqueness: { scope: :source }
  validates :source, presence: true
  validates :event_type, presence: true
  validates :payload, presence: true

  # A processing claim older than this is treated as abandoned (e.g. the worker was killed).
  CLAIM_TIMEOUT = 10.minutes
  # A webhook pending longer than this has probably lost its job (enqueue failed after save).
  PENDING_TIMEOUT = 5.minutes
  # StuckWebhookSweeperJob re-enqueues a stuck webhook at most this many times, then marks it failed.
  MAX_REENQUEUES = 5

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

  # Webhooks that will not make progress on their own: pending with no recent change
  # (updated_at = when it became pending or was last re-enqueued), or processing with
  # an abandoned claim. Must match #stuck?.
  scope :stuck, -> {
    where(status: :pending, updated_at: ...PENDING_TIMEOUT.ago).or(
      where(status: :processing).where(
        'processing_started_at IS NULL OR processing_started_at < ?', CLAIM_TIMEOUT.ago
      )
    )
  }

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

  # Instance version of the .stuck scope.
  def stuck?
    (pending? && updated_at < PENDING_TIMEOUT.ago) || (processing? && !claim_active?)
  end

  # Called by StuckWebhookSweeperJob for each webhook from .stuck. Re-checks under a row
  # lock (a worker may have finished or claimed it since the scan) and returns:
  #   :skipped    - no longer stuck
  #   :gave_up    - re-enqueued MAX_REENQUEUES times already; now marked failed
  #   :reenqueued - counter incremented; the caller enqueues the job after the lock commits
  def requeue_if_stuck!
    with_lock do
      next :skipped unless stuck?

      if reenqueue_count >= MAX_REENQUEUES
        update!(status: :failed, last_error: "Gave up after #{MAX_REENQUEUES} re-enqueues (stuck in #{status})")
        next :gave_up
      end

      update!(reenqueue_count: reenqueue_count + 1)
      :reenqueued
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
