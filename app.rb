require 'bundler/setup'
Bundler.require
require 'yaml'

def http_auth
  request.env['HTTP_AUTHORIZATION'] || params[:bearer_token]
end

def bearer_token
  http_auth ? http_auth.gsub('Bearer ', '') : nil
end

module Geoloqi
  class Session
    def create_anon_user(opts={})
      auth = post_with_credentials 'user/create_anon'

      auth['expires_at'] = auth_expires_at auth['expires_in']
      self.auth = auth
      self.auth
    end

    def update_user(user_id, opts={})
      post_with_credentials "user/update/#{user_id}", opts
    end

    def post_with_credentials(action, opts={})
      unless @config.client_id? && @config.client_secret?
        raise 'client_id and client_secret are required to perform this action'
      end

      post action, {
        client_id:     @config.client_id,
        client_secret: @config.client_secret
      }.merge!(opts)
    end
  end
end

configure do
  $config = YAML.load_file './config.yml'
end

before do
  @geoloqi = Geoloqi::Session.new(
    access_token: bearer_token,
    config: {
      client_id:     $config['geoloqi_client_id'], 
      client_secret: $config['geoloqi_client_secret']
    }
  )
end

get '/' do
  erb :'index'
end

post '/api/users' do
  resp = @geoloqi.create_anon_user

  @geoloqi.update_user resp[:user_id], {
    extra: {
      fb_access_token:    params[:fb_access_token],
      fb_expiration_date: params[:fb_expiration_date]
    }
  }

  {lq_access_token: @geoloqi.access_token}.to_json
end

get '/api/status' do
  if @geoloqi.access_token?
    begin
      @response = @geoloqi.get 'location/context'
    rescue => e
      puts "error: #{e.message}"
      return {error: e.message}.to_json
    end
    return {response: @response[:best_name]}.to_json
  else
    error 401, 'geoloqi access token required'
  end
end

get '/:region/:locality/:city' do
  
end

=begin
{
  locality_name: "Portland",
  region_name: "OR",
  country_name: "US",
  full_name: "Portland, OR, US",
  best_name: "Portland"
}
=end