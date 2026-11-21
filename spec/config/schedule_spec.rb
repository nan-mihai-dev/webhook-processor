require 'rails_helper'

RSpec.describe 'config/schedule.yml (sidekiq-cron)' do
  let(:schedule) { YAML.safe_load_file(Rails.root.join('config/schedule.yml')) }

  it 'runs StuckWebhookSweeperJob every 5 minutes on the low queue' do
    entry = schedule.fetch('stuck_webhook_sweeper')

    expect(entry).to include('cron' => '*/5 * * * *', 'class' => 'StuckWebhookSweeperJob', 'queue' => 'low')
  end

  it 'contains only valid sidekiq-cron jobs' do
    schedule.each do |name, entry|
      job = Sidekiq::Cron::Job.new(entry.merge('name' => name))
      expect(job).to be_valid, "#{name}: #{job.errors.join(', ')}"
    end
  end
end
