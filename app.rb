require 'bundler/setup'
Bundler.require
require 'sinatra'
Bundler.require :development if development?
require 'yaml'
require_relative './env.rb'

before do
  if request.post?
    self.params = JSON.parse request.body.read, symbolize_names: true
    request.body.rewind
  end

  @geoloqi = Geoloqi::Session.new(
    access_token: bearer_token,
    config: {
      client_id:     $config['geoloqi_client_id'], 
      client_secret: $config['geoloqi_client_secret']
    }
  )
end

helpers do
  def h(val)
    Rack::Utils.escape_html val
  end
end

get '/' do
  @title = "Everyday City"
  erb :'index'
end

get '/map/:resolution/:country/:region/:locality.png' do
  city = DB[:cities].filter(country: params[:country], region: params[:region], locality: params[:locality]).first
  not_found 'could not find city' if city.nil?
  img_width, img_height = params[:resolution].split('x')
  ppl = Rack::Utils.escape "54,,#{city[:lat]},#{city[:lng]}"
  map_img_url = "http://fb.ecn.api.tiles.virtualearth.net/api/GetMap.ashx?"+
                "b=r%2Cmkt.en-US%2Cstl.fb&key=#{$config['bing_img_key']}&td=D1&h=#{img_height}&w=#{img_width}&ppl=#{ppl}&z=8"
  redirect map_img_url
  #query = {mapArea: city[:bbox], mapSize: params[:resolution].gsub('x', ','), format: 'png', mapMetadata: 0, key: $config[:bing_key]}
  #map_img_url = "http://dev.virtualearth.net/REST/v1/Imagery/Map/Road?#{Rack::Utils.build_query query}"
  #puts "IMAGE URL: #{map_img_url}"
  #map_img_url
end

post '/api/users' do
  if params[:fb_access_token].nil? || params[:fb_expiration_date].nil?
    halt 500, "fb_access_token or fb_expiration_date (or both) not found"
  end

  facebook_profile = get_facebook_profile params[:fb_access_token]

  if facebook_profile[:id]
    # Check if we already have a Geoloqi account for this user
    user = DB[:users].filter(fb_user_id: facebook_profile[:id]).first
    if user.nil?
      resp = @geoloqi.create_anon_user

      DB[:users] << {
        lq_access_token:    @geoloqi.access_token, 
        geoloqi_user_id:    resp[:user_id],
        fb_user_id:         facebook_profile[:id],
        fb_user_url:        facebook_profile[:link],
        fb_access_token:    params[:fb_access_token], 
        fb_expiration_date: params[:fb_expiration_date],
        date_created:       Time.now
      }
      lq_access_token = @geoloqi.access_token
    else
      DB[:users].filter(:fb_user_id => facebook_profile[:id]).update({
        fb_access_token:    params[:fb_access_token],
        fb_expiration_date: params[:fb_expiration_date]
      })
      lq_access_token = user[:lq_access_token]
    end

    {lq_access_token: lq_access_token}.to_json
  else
    {error: "unknown_error"}.to_json
  end
end

get '/api/status' do
  if @geoloqi.access_token?
    begin
      resp = @geoloqi.get 'location/context'
    rescue => e
      puts "error: #{e.message}"
      return {error: e.message}.to_json
    end
    return {response: resp[:best_name]}.to_json
  else
    error 401, 'geoloqi access token required'
  end
end

get '/city/:country/:region/:locality' do
  @city = DB[:cities][country: params[:country], region: params[:region], locality: params[:locality]]
  erb :'og'
end

# Test route for getting a Facebook access token
get '/auth/callback' do
  resp = RestClient.post("https://graph.facebook.com/oauth/access_token", {
    client_id: $config['fb_client_id'],
    client_secret: $config['fb_client_secret'],
    redirect_uri: 'http://everydaycity.com/auth/callback',
    code: params[:code]
  }) {|response,request,result| Rack::Utils.parse_query response}

  @fb_access_token = resp['access_token']
  erb :'fb_auth'
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

def http_auth
  request.env['HTTP_AUTHORIZATION'] || params[:lq_access_token]
end

def bearer_token
  http_auth ? http_auth.gsub('Bearer ', '') : nil
end

def get_facebook_profile(access_token)
  resp = RestClient.get("https://graph.facebook.com/me?access_token=#{access_token}") {|response, request, result| response }
  JSON.parse resp, symbolize_names: true
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
