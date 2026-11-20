# Behaviour shared by every job that includes WebhookProcessing.
#   event_type: a type the job handles
#   handler:    the private method EVENT_HANDLERS maps it to
RSpec.shared_examples 'a webhook processing job' do |event_type:, handler:|
  subject(:job) { described_class.new }

  let(:webhook) { create(:webhook, event_type: event_type, payload: '{"ref": "abc"}') }

  it 'is safe to run twice: the second run is skipped' do
    allow(job).to receive(handler).and_call_original

    job.perform(webhook.id)
    first_processed_at = webhook.reload.processed_at
    job.perform(webhook.id)

    expect(job).to have_received(handler).once
    expect(webhook.reload).to be_completed
    expect(webhook.processed_at).to eq(first_processed_at)
  end

  it 'skips a webhook another worker claimed recently' do
    freeze_time
    webhook.update!(status: :processing, processing_started_at: 2.minutes.ago)
    allow(job).to receive(handler)

    job.perform(webhook.id)

    expect(job).not_to have_received(handler)
    expect(webhook.reload).to be_processing
    expect(webhook.processing_started_at).to eq(2.minutes.ago)
  end

  it 'takes over a stale claim (older than Webhook::CLAIM_TIMEOUT)' do
    freeze_time
    webhook.update!(status: :processing, processing_started_at: 11.minutes.ago)
    allow(job).to receive(handler).and_call_original

    job.perform(webhook.id)

    expect(job).to have_received(handler).once
    expect(webhook.reload).to be_completed
    expect(webhook.processing_started_at).to eq(Time.current)
  end

  it 'takes over a processing webhook claimed before processing_started_at existed' do
    webhook.update!(status: :processing, processing_started_at: nil)
    allow(job).to receive(handler).and_call_original

    job.perform(webhook.id)

    expect(job).to have_received(handler).once
    expect(webhook.reload).to be_completed
  end

  it 'marks an unknown event type as ignored with a single warning' do
    unknown = create(:webhook, event_type: 'unknown.event')
    allow(Rails.logger).to receive(:warn)

    2.times { job.perform(unknown.id) }

    expect(unknown.reload).to be_ignored
    expect(unknown.processed_at).to be_present
    expect(Rails.logger).to have_received(:warn).with(/Unknown event type "unknown.event"/).once
  end

  it 'sets Sentry context for error reports' do
    allow(Sentry).to receive(:set_context)

    job.perform(webhook.id)

    expect(Sentry).to have_received(:set_context).with(
      'webhook', hash_including(id: webhook.id, event_type: event_type, queue: described_class.get_sidekiq_options['queue'])
    )
  end

  context 'when the handler raises' do
    before { allow(job).to receive(handler).and_raise(RuntimeError, 'boom') }

    it 'marks the webhook failed and re-raises so Sidekiq retries' do
      expect { job.perform(webhook.id) }.to raise_error(RuntimeError, 'boom')
      expect(webhook.reload).to be_failed
    end

    it 'leaves error reporting to sentry-sidekiq (no manual capture)' do
      allow(Sentry).to receive(:capture_exception)

      expect { job.perform(webhook.id) }.to raise_error(RuntimeError)
      expect(Sentry).not_to have_received(:capture_exception)
    end

    it 'completes on a later retry' do
      expect { job.perform(webhook.id) }.to raise_error(RuntimeError)

      allow(job).to receive(handler).and_call_original
      job.perform(webhook.id)

      expect(webhook.reload).to be_completed
    end
  end
end
