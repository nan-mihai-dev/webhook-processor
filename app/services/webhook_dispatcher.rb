# Single place that decides which job (and therefore which Sidekiq queue)
# processes a webhook. Used on ingestion, manual retry, and by the sweeper.
class WebhookDispatcher
  CRITICAL_EVENT_TYPES = [
    'payment.succeeded',
    'payment.failed',
    'refund.created',
    'charge.disputed'
  ].freeze

  def self.job_for(webhook)
    CRITICAL_EVENT_TYPES.include?(webhook.event_type) ? ProcessCriticalWebhookJob : ProcessWebhookJob
  end

  def self.dispatch(webhook)
    job = job_for(webhook)
    job.perform_async(webhook.id)

    prefix = job == ProcessCriticalWebhookJob ? '! Enqueued CRITICAL webhook' : 'Enqueued webhook'
    Rails.logger.info "#{prefix} #{webhook.id}: #{webhook.event_type}"
    job
  end
end
