#!/usr/bin/env ruby
require 'bundler/setup'
Bundler.require
require_relative './env.rb'

users = DB[:users].all

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

  bing_url = "http://dev.virtualearth.net/REST/v1/Locations/#{lat},#{lng}?includeEntityTypes=PopulatedPlace&key=#{$config['bing_key']}"
  bing_resp = JSON.parse(RestClient.get(bing_url), symbolize_names: true)[:resourceSets].first[:resources].first

  DB[:cities] << {
    name:     bing_resp[:name],
    bbox:     bing_resp[:bbox].join ',',
    lat:      bing_resp[:point][:coordinates][0],
    lng:      bing_resp[:point][:coordinates][1],
    locality: bing_resp[:address][:locality],
    region:   bing_resp[:address][:adminDistrict],
    country:  bing_resp[:address][:countryRegion]
  }
  
  city = DB[:cities][name: bing_resp[:name]]

  if user[:current_city] != city[:name]
    # DB[:users].filter(geoloqi_user_id: user[:geoloqi_user_id]).update current_city: city[:name]

    binding.pry
    # update to facebook
    fb_resp = RestClient.post 'https://graph.facebook.com/me/everydaycity:arrive_in', {
      city: "http://everydaycity.com/city/#{city[:country]}/#{city[:region]}/#{city[:locality]}",
      access_token: user[:fb_access_token]
    }
    puts fb_resp.inspect
  end
end