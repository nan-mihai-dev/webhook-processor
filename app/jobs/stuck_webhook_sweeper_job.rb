# Recovers webhooks that are stuck without an error, which Sidekiq retries can't see:
# - pending with no job (the enqueue failed after the row was saved)
# - processing with an abandoned claim (the worker was killed mid-job)
#
# Runs every 5 minutes (config/schedule.yml, sidekiq-cron). Safe to overlap with
# workers: each webhook is re-checked under a row lock, and re-enqueued jobs go
# through the processing jobs' own claim step.
class StuckWebhookSweeperJob
  include Sidekiq::Job

  # No retries: the next scheduled run picks up anything left over.
  sidekiq_options queue: :low, retry: false

  def perform
    counts = Hash.new(0)

    Webhook.stuck.find_each do |webhook|
      counts[:scanned] += 1
      stuck_status = webhook.status
      outcome = webhook.requeue_if_stuck!
      counts[outcome] += 1

      case outcome
      when :reenqueued
        # After the lock has committed, so the job never reads uncommitted state.
        WebhookDispatcher.dispatch(webhook)
      when :gave_up
        report_gave_up(webhook, stuck_status)
      end
    end

    Rails.logger.info(
      "[StuckWebhookSweeperJob] scanned=#{counts[:scanned]} reenqueued=#{counts[:reenqueued]} " \
      "gave_up=#{counts[:gave_up]} skipped=#{counts[:skipped]}"
    )
  end

  private

  def report_gave_up(webhook, stuck_status)
    Sentry.capture_message(
      "Webhook gave up after #{Webhook::MAX_REENQUEUES} re-enqueues",
      level: :error,
      contexts: {
        webhook: {
          id: webhook.id,
          source: webhook.source,
          event_type: webhook.event_type,
          stuck_status: stuck_status
        }
      }
    )
  end
end
