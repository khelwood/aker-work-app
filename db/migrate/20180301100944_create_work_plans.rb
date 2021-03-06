class CreateWorkPlans < ActiveRecord::Migration[5.1]
  def change
    enable_extension 'uuid-ossp'

    create_table :work_plans, id: :serial do |t|
      t.integer :project_id
      t.references :product, foreign_key: true
      t.uuid :original_set_uuid
      t.citext :owner_email, null: false
      t.string :comment
      t.date :desired_date
      t.uuid :uuid, null: false
      t.timestamps
    end

    add_index :work_plans, :owner_email
  end
end
