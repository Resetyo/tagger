class CreateCurrentStates < ActiveRecord::Migration[5.2]
  def change
    create_table :current_states do |t|
      t.string :domain
      t.string :domain_source
      t.integer :filter_type, default: 0
      t.string :filter_source

      t.timestamps
    end
  end
end
