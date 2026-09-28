class CreateFamilyMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :family_memberships, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      # Single-column indexes are redundant: each column leads one of the
      # composite indexes below.
      t.references :user, null: false, foreign_key: true, type: :uuid, index: false
      t.references :family, null: false, foreign_key: true, type: :uuid, index: false
      t.string :role, null: false, default: "editor"
      t.timestamps
    end

    # One membership per user per family. The (family_id, user_id) ordering
    # additionally serves "who is in this family" lookups.
    add_index :family_memberships, [ :user_id, :family_id ], unique: true
    add_index :family_memberships, [ :family_id, :user_id ]

    add_check_constraint :family_memberships, "role IN ('owner','admin','editor','viewer')",
      name: "chk_family_memberships_role_enum"

    # Backfill one membership per existing user, mapping the legacy single
    # role onto the membership role set. Every existing family needs at least
    # one owner, and today's family admins are the people who administer those
    # families, so admins (and instance super_admins) become owners; members
    # become editors; guests become viewers. Down needs no data step: the
    # table (and every backfilled row) is dropped by reverting create_table.
    reversible do |dir|
      dir.up do
        execute <<~SQL
          INSERT INTO family_memberships (id, user_id, family_id, role, created_at, updated_at)
          SELECT gen_random_uuid(), users.id, users.family_id,
            CASE users.role
              WHEN 'guest' THEN 'viewer'
              WHEN 'member' THEN 'editor'
              WHEN 'admin' THEN 'owner'
              WHEN 'super_admin' THEN 'owner'
              ELSE 'editor'
            END,
            users.created_at, NOW()
          FROM users
          ON CONFLICT (user_id, family_id) DO NOTHING
        SQL
      end
    end
  end
end
