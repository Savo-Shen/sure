class AddFamilyToChats < ActiveRecord::Migration[8.1]
  def change
    add_reference :chats, :family, type: :uuid, foreign_key: true

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE chats
          SET family_id = users.family_id
          FROM users
          WHERE chats.user_id = users.id
        SQL
      end
    end

    change_column_null :chats, :family_id, false
  end
end
