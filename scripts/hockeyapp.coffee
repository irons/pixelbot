# Description:
#   Upload Android or iOS apps to HockeyApp
#
# Dependencies:
#
#
# Configuration:
#  JSON file named hockey.json with properties 'hockeyapptoken', 'file-path' to builds, and platform-market properties are required.
#
# Commands:
#   hubot upload <android>/<ios> <build_number> - uploads specified android or ios app to HockeyApp.
#
# Author:
# Jesse Chen
request = require 'request'
fs = require 'fs'

upload = (msg) ->
    platform = msg.match[1]
    market = msg.match[2]
    buildNumber = msg.match[3]

    fs.readFile "hockey.json", 'utf-8', (error, body) ->
      console.log("Something's wrong with the JSON file for hockeyapp IDs:" + error ) if error
      hockey_info = JSON.parse(body)

      msg.send JSON.stringify(hockey_info)

      key = platform + "-" + market
      if key of hockey_info
        app_id = hockey_info[key]
      else
        msg.send "app ID not found for #{market} #{platform}"

      extension = if platform.match "ios" then ".ipa" else ".apk"

      if "file-path" of hockey_info
        file_path = hockey_info["file-path"] + "/#{market}/#{platform}/#{market}-#{platform}#{extension}"
      else
        msg.send "Path to build not found in JSON file."

      if "hockeyapptoken" of hockey_info
        token = hockey_info["hockeyapptoken"]
      else
        msg.send "Hockey app token not found in JSON file."

      try
        ipa_file = fs.createReadStream("#{file_path}")
      catch error
        msg.send "Build not found."

      data = {
        ipa: ipa_file,
        notes: 'uploaded by hubot',
        notify: '1',
        tags: 'build-mgmt'
        }

      request.post {url: "https://rink.hockeyapp.net/api/2/apps/#{app_id}/app_versions/upload", headers: {'X-HockeyAppToken': "#{token}"}, formData: data}, (err,res, body) ->
        if err
          msg.reply "Error posting to HockeyApp: #{err}. ipa_file: #{ipa_file}"
        else if res.statusCode == 201
          msg.reply "Build posted to HockeyApp:\n #{body}"
        else
          msg.reply "Not sure what went on here... #{res.statusCode}, #{body}"+"\n#{app_id}, #{file_path}" + JSON.stringify(data)

module.exports = (robot) ->
    robot.respond /upload (android|ios)?(?:\s)([a-z]+)(?:\s)?(\d+)?/i, (msg) ->
      upload(msg)
