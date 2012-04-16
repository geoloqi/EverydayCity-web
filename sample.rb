#!/usr/bin/env ruby
require 'bundler/setup'
Bundler.require
Bundler.require :sample
require_relative './env.rb'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: ./sample.rb [t]"

  opts.on("-t", "--token=[TOKEN]", "Access token") do |t|
    options[:access_token] = t
  end

end.parse!

if options[:access_token]
  mogli_client = Mogli::Client.new options[:access_token]
  access_token = mogli_client.access_token
else
  authenticator = Mogli::Authenticator.new(($config['fb_client_id']||286536824758724), $config['fb_client_secret'], 'http://everydaycity.com/auth/callback')
  puts authenticator.authorize_url(:scope => 'publish_stream publish_actions', :display => 'page')

  puts
  puts "Visit the above URL in your browser, and paste the resulting access token below"
  puts
  access_token = ask("Enter Facebook access token: ") { |q| q.echo = true }
end

puts

puts "Sending to everydaycity.com"

resp = RestClient.post('http://everydaycity.com/api/users', {
  fb_access_token: access_token,
  fb_expiration_date: 1339743600
}.to_json) {|response, request, result| response }
auth = JSON.parse resp, symbolize_names: true

lq_access_token = auth[:lq_access_token]

puts "Created Geoloqi user with access token: #{lq_access_token}"
puts 

puts "Sending location update to Geoloqi at Facebook HQ"

resp = RestClient.post('https://api.geoloqi.com/1/location/update', [{
  date: Time.now.to_i,
  location: {
    position: {
      latitude: 37.485107, 
      longitude: -122.147579,
      speed: 0,
      altitude: 0,
      horizontal_accuracy: 10
    },
    type: "point",
  },
  raw: {
    source: "everydaycity_sample"
  }
}].to_json, {:content_type => :json, 
             :accept => :json, 
             :authorization => "OAuth #{lq_access_token}"
}) {|response, request, result| response }

puts resp
