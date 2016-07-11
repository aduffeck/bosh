Sequel.migration do
  up do
    create_table :local_dns_records do
      primary_key :id
      String :name, :unique => true, :null => false
      String :ip, :unique => true, :null => false
      foreign_key :instance_id, :instances, :null => false, :on_delete => :cascade
    end
  end

  down do
    drop_table :local_dns_records
  end
end

