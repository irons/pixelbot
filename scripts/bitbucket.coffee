# Description:
#   Creates Bitbucket repositories and adds users.
#
# Dependencies:
#
#
# Configuration:
#  HUBOT_BITBUCKET_AUTH_USER
#  HUBOT_BITBUCKET_AUTH_PASSWORD
#
# Commands:
#
#  hubot bitbucket create <repository-name> -  creates new repository in Bitbucket
#
# Author:
# Jesse Chen

create = (msg) ->
  repo_name = msg.match[1]

  if process.env.HUBOT_BITBUCKET_AUTH_USER && process.env.HUBOT_BITBUCKET_AUTH_PASSWORD
    user = process.env.HUBOT_BITBUCKET_AUTH_USER
    password = process.env.HUBOT_BITBUCKET_AUTH_PASSWORD

    req = msg.http("https://bitbucket.org/api/2.0/repositories/#{user}/#{repo_name}")
    auth = new Buffer(user+':'+password).toString('base64')
    req.headers Authorization: "Basic #{auth}"

    body = {
      scm: "git",
      repo_slug: repo_name,
      is_private: true,
      fork_policy: "no_forks",
      has_wiki: false
    }

    req.post(body) (err, res, data) ->
      if err
        msg.reply "whoops! an error has occcured: #{err}"
      else if res.statusCode == 401
        msg.reply "There's something wrong your username and password for Bitbucket."
      else if res.statusCode == 200
        msg.reply "New repository created! \m #{data}"
      else
        msg.reply "#{res.statusCode}: #{data}"


module.exports = (robot) ->
    robot.respond /bitbucket create ([0-9a-z\-]+)?/i, (msg) ->
      create(msg)
