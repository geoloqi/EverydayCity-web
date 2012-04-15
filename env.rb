$config = YAML.load_file './config.yml'

DB = Sequel.connect $config['database']

unless DB.table_exists? :users
  DB.create_table :users do
    primary_key :id
    String      :lq_access_token, :index => true
    String      :geoloqi_user_id
    String      :fb_access_token
    Integer     :fb_expiration_date
    String      :fb_user_id
    String      :fb_user_url
    String      :current_city
    Time        :date_created
  end
end

unless DB.table_exists? :cities
  DB.create_table :cities do
    primary_key :id
    String      :country,  :size => 50
    String      :region,   :size => 100
    String      :locality, :size => 100
    String      :name
    Float       :lat
    Float       :lng
    String      :bbox
    Time        :date_created
    index       [:country, :region, :locality]
  end
end