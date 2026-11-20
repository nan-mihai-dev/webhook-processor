class ScopeWebhookExternalIdUniquenessToSource < ActiveRecord::Migration[8.1]
  # CREATE/DROP INDEX CONCURRENTLY cannot run inside a transaction.
  disable_ddl_transaction!

  def change
    # Add the new index before dropping the old one so uniqueness is enforced throughout.
    add_index :webhooks, [:source, :external_id], unique: true, algorithm: :concurrently
    remove_index :webhooks, :external_id, unique: true, algorithm: :concurrently
  end
end
