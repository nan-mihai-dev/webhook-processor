class AddReenqueueTrackingToWebhooks < ActiveRecord::Migration[8.1]
  def change
    add_column :webhooks, :reenqueue_count, :integer, null: false, default: 0
    add_column :webhooks, :last_error, :text
  end
end
