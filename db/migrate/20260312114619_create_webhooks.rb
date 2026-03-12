class CreateWebhooks < ActiveRecord::Migration[8.1]
  def change
    create_table :webhooks do |t|
      t.string :external_id, null: false
      t.string :source, null: false
      t.string :event_type, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :status, default: 'pending'
      t.datetime :processed_at

      t.timestamps
    end

    add_index :webhooks, :external_id, unique: true
    add_index :webhooks, :source
    add_index :webhooks, :status
    add_index :webhooks, :created_at
  end
end
