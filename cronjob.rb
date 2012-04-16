#!/usr/bin/env ruby
require 'bundler/setup'
Bundler.require
require_relative './env.rb'
require 'pry'
users = DB[:users].all

def update_facebook(country, region, locality, access_token)
  resp = RestClient.post('https://graph.facebook.com/me/everydaycity:arrive_in', {
    city: "http://everydaycity.com/city/#{country}/#{region}/#{locality}",
    access_token: access_token
  }) {|response, request, result| response }
  
  JSON.parse resp, symbolize_names: true
end

users.each do |user|
  begin
    last = Geoloqi.get user[:lq_access_token], 'location/last'
  rescue Geoloqi::ApiError => e
    if e.type == 'no_recent_location'
      puts "no recent location, skipping user #{user[:geoloqi_user_id]}"
      next
    else
      fail
    end
  end

  lat, lng = last[:location][:position][:latitude], last[:location][:position][:longitude]

  bing_url = "http://dev.virtualearth.net/REST/v1/Locations/#{lat},#{lng}?includeEntityTypes=PopulatedPlace&key=#{$config['bing_geocoding_key']}"
  bing_resp = JSON.parse(RestClient.get(bing_url), symbolize_names: true)[:resourceSets].first[:resources].first

  # If geocoder returns nothing, go to next.
  if bing_resp.nil?
    puts bing_url
    puts "BING returned no city, skip"
    next
  end

  city_args = {
    name:         bing_resp[:name],
    bbox:         bing_resp[:bbox].join(','),
    lat:          bing_resp[:point][:coordinates][0],
    lng:          bing_resp[:point][:coordinates][1],
    locality:     bing_resp[:address][:locality],
    region:       bing_resp[:address][:adminDistrict],
    country:      bing_resp[:address][:countryRegion],
    date_created: Time.now
  }

  city = DB[:cities].filter(country: city_args[:country], region: city_args[:region], locality: city_args[:locality]).first

  if city.nil?
    DB[:cities] << city_args
    city = DB[:cities][name: bing_resp[:name]]
  end

  # If token expires within an hour (or earlier), refresh the token.
  if Time.at(user[:fb_expiration_date] || 0) - Time.now < 3600
    args = {
      client_id:        $config['fb_client_id'],
      client_secret:    $config ['fb_client_secret'],
      grant_type:       'fb_exchange_token',
      fb_exchange_token: user[:fb_access_token]
    }

    res = RestClient.post("https://graph.facebook.com/oauth/access_token", args) {|response, request, result| response }
    res = Rack::Utils.parse_query res

    unless res['error']
      puts "UPDATING TOKEN"
      DB[:users].filter(geoloqi_user_id: user[:geoloqi_user_id]).update(fb_access_token: res['access_token'], fb_expiration_date: Time.now.to_i+res['expires'].to_i)
    end
  end

  if user[:current_city] != city[:name]
    puts "user current city #{user[:current_city]} is wrong, changing to #{city[:name]}"
    DB[:users].filter(geoloqi_user_id: user[:geoloqi_user_id]).update current_city: city[:name]

    retry_attempt = 0

    while true
      fb_resp = update_facebook city[:country], city[:region], city[:locality], user[:fb_access_token]

      if fb_resp[:error] && fb_resp[:error][:message] =~ /Transfer failed/
        retry_attempt += 1
        puts "TRANSFER FAILED, RETRYING (attempt ##{retry_attempt})"
      else
        break
      end

      if retry_attempt == 5
        puts "TRANSFER FAILED #{retry_attempt} times for user #{user[:geoloqi_user_id]}, skipping"
        next
      end
    end

    puts "FB RESPONSE: #{fb_resp}"

    DB[:visits] << {
      user_id: user[:id],
      city_id: city[:id],
      date_visited: Time.now,
      lat: lat,
      lng: lng,
      fb_post_id: fb_resp[:id]
    }
  end
end
