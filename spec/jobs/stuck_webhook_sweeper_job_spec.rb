require 'rails_helper'

RSpec.describe StuckWebhookSweeperJob, type: :job do
  # A method, not `subject`: subject is memoized, so repeated sweeps would silently run once.
  def sweep
    described_class.new.perform
  end

  before do
    allow(ProcessWebhookJob).to receive(:perform_async)
    allow(ProcessCriticalWebhookJob).to receive(:perform_async)
    allow(Sentry).to receive(:capture_message)
  end

  # Creates a webhook whose last change happened `age` ago.
  def webhook_aged(age, **attrs)
    travel_to(age.ago) { create(:webhook, **attrs) }
  end

  describe 'stuck pending webhooks' do
    let!(:critical) { webhook_aged(6.minutes, status: :pending, event_type: 'payment.succeeded') }
    let!(:standard) { webhook_aged(6.minutes, status: :pending, event_type: 'order.shipped') }

    it 're-enqueues each one to the queue for its event type' do
      sweep

      expect(ProcessCriticalWebhookJob).to have_received(:perform_async).with(critical.id).once
      expect(ProcessWebhookJob).to have_received(:perform_async).with(standard.id).once
    end

    it 'increments reenqueue_count' do
      sweep

      expect(critical.reload.reenqueue_count).to eq(1)
      expect(standard.reload.reenqueue_count).to eq(1)
    end

    it 'waits another PENDING_TIMEOUT before re-enqueueing the same webhook again' do
      sweep
      sweep # immediately: updated_at was bumped by the first sweep

      expect(ProcessWebhookJob).to have_received(:perform_async).with(standard.id).once

      travel_to(Webhook::PENDING_TIMEOUT.from_now + 1.second) { sweep }

      expect(ProcessWebhookJob).to have_received(:perform_async).with(standard.id).twice
    end
  end

  it 'leaves a pending webhook alone until PENDING_TIMEOUT has passed' do
    fresh = webhook_aged(4.minutes, status: :pending, event_type: 'order.shipped')

    sweep

    expect(ProcessWebhookJob).not_to have_received(:perform_async)
    expect(fresh.reload.reenqueue_count).to eq(0)
  end

  it 're-enqueues processing webhooks with an abandoned claim, not live ones' do
    stale = create(:webhook, status: :processing, processing_started_at: 11.minutes.ago, event_type: 'order.shipped')
    live  = create(:webhook, status: :processing, processing_started_at: 2.minutes.ago, event_type: 'order.shipped')

    sweep

    expect(ProcessWebhookJob).to have_received(:perform_async).with(stale.id)
    expect(ProcessWebhookJob).not_to have_received(:perform_async).with(live.id)
  end

  describe 'past the re-enqueue cap' do
    let!(:webhook) do
      webhook_aged(6.minutes, status: :pending, event_type: 'order.shipped', reenqueue_count: Webhook::MAX_REENQUEUES)
    end

    it 'marks the webhook failed with a message instead of re-enqueueing it' do
      sweep

      webhook.reload
      expect(webhook).to be_failed
      expect(webhook.last_error).to match(/Gave up after #{Webhook::MAX_REENQUEUES} re-enqueues/)
      expect(ProcessWebhookJob).not_to have_received(:perform_async)
    end

    it 'sends exactly one Sentry event, even across later sweeps' do
      sweep
      travel_to(1.hour.from_now) { sweep }

      expect(Sentry).to have_received(:capture_message).once.with(
        /gave up after #{Webhook::MAX_REENQUEUES} re-enqueues/,
        hash_including(level: :error, contexts: { webhook: hash_including(id: webhook.id, stuck_status: 'pending') })
      )
    end
  end

  it 'logs one summary line per run' do
    webhook_aged(6.minutes, status: :pending, event_type: 'order.shipped')
    webhook_aged(6.minutes, status: :pending, event_type: 'order.shipped', reenqueue_count: Webhook::MAX_REENQUEUES)
    webhook_aged(1.minute, status: :pending, event_type: 'order.shipped')
    allow(Rails.logger).to receive(:info)

    sweep

    expect(Rails.logger).to have_received(:info).with(/\[StuckWebhookSweeperJob\]/).once
    expect(Rails.logger).to have_received(:info).with(
      '[StuckWebhookSweeperJob] scanned=2 reenqueued=1 gave_up=1 skipped=0'
    )
  end
end
