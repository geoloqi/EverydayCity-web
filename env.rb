$config = YAML.load_file './config.yml'

DB = Sequel.connect $config['database']

unless DB.table_exists? :users
  DB.create_table :users do
    String  :lq_access_token, key: true
    String  :geoloqi_user_id
    String  :fb_access_token
    Integer :fb_expiration_date
    String  :current_city
  end
end

unless DB.table_exists? :cities
  DB.create_table :cities do
    String :country
    String :lat
    String :lng
    String :region
    String :locality
    String :bbox
    String :name
  end
end