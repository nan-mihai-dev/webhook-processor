class AddProcessingStartedAtToWebhooks < ActiveRecord::Migration[8.1]
  def change
    add_column :webhooks, :processing_started_at, :datetime
  end
end
