# Description:
#   Creates Bitbucket repositories, read, read-write access groups, and adds users to specified groups.
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
#  hubot bitbucket create <repository-name> -  creates new repository in Bitbucket.
#  hubot bitbucket add <bitbucket user> to <bitbucket group> - adds user to read or read-write access groups.
#
# Author:
# Jesse Chen

create = (msg) ->
  repo_name = msg.match[1]

  if process.env.HUBOT_BITBUCKET_AUTH_USER && process.env.HUBOT_BITBUCKET_AUTH_PASSWORD
    user = process.env.HUBOT_BITBUCKET_AUTH_USER
    password = process.env.HUBOT_BITBUCKET_AUTH_PASSWORD

    req = msg.http("https://bitbucket.org/api/2.0/repositories/#{user}/#{repo_name}")
    auth = new Buffer(user + ':' + password).toString('base64')
    req.headers Authorization: "Basic #{auth}"

    data = JSON.stringify({
      scm: "git",
      repo_slug: repo_name,
      is_private: true,
      fork_policy: "no_forks",
      has_wiki: false
    })

    req.header('Content-Type', 'application/json')
    req.post(data) (err, res, body) ->
      if err
        msg.send "whoops! an error has occcured: #{err}"
      else if res.statusCode == 401
        msg.send "There's something wrong your username and password for Bitbucket."
      else if res.statusCode == 200
        msg.send "New repository created! \n https://bitbucket.org/#{user}/#{repo_name}"
        createGroup(msg, repo_name + "-read", repo_name, "read")
        createGroup(msg, repo_name + "-readwrite", repo_name, "write")
      else
        msg.send "#{res.statusCode}: #{body}"

createGroup = (msg, group_name, repo_name, priv) ->
  if process.env.HUBOT_BITBUCKET_AUTH_USER && process.env.HUBOT_BITBUCKET_AUTH_PASSWORD
    user = process.env.HUBOT_BITBUCKET_AUTH_USER
    password = process.env.HUBOT_BITBUCKET_AUTH_PASSWORD

    req = msg.http("https://bitbucket.org/api/1.0/groups/#{user}/")
    auth = new Buffer(user + ':' + password).toString('base64')
    req.headers Authorization: "Basic #{auth}"

    req.header('Content-Type', 'application/x-www-form-urlencoded')
    req.post("name=#{group_name}") (err, res, body) ->
      if err
        msg.send "whoops! an error has occcured: #{err}"
      else if res.statusCode == 401
        msg.send "There's something wrong your username and password for Bitbucket."
      else if res.statusCode == 200
        msg.send "Group created: #{group_name}."
        addGroup(msg, repo_name, group_name, priv)
      else
        msg.send "#{res.statusCode}: #{body}"


addGroup = (msg, repo, group, priv) ->
  if process.env.HUBOT_BITBUCKET_AUTH_USER && process.env.HUBOT_BITBUCKET_AUTH_PASSWORD
    user = process.env.HUBOT_BITBUCKET_AUTH_USER
    password = process.env.HUBOT_BITBUCKET_AUTH_PASSWORD

    req = msg.http("https://bitbucket.org/api/1.0/group-privileges/#{user}/#{repo}/#{user}/#{group}")
    auth = new Buffer(user+':'+password).toString('base64')
    req.headers Authorization: "Basic #{auth}"

    req.put("#{priv}") (err, res, body) ->
      if err
        msg.send "whoops! an error has occcured: #{err}"
      else if res.statusCode == 401
        msg.send "There's something wrong your username and password for Bitbucket."
      else if res.statusCode == 200
        msg.send "Group #{group} added to #{repo} repository."
      else
        msg.send "#{res.statusCode}: #{body}"


addUser = (msg) ->
  user = msg.match[1]
  group = msg.match[2]

  if process.env.HUBOT_BITBUCKET_AUTH_USER && process.env.HUBOT_BITBUCKET_AUTH_PASSWORD
    owner = process.env.HUBOT_BITBUCKET_AUTH_USER
    password = process.env.HUBOT_BITBUCKET_AUTH_PASSWORD

    req = msg.http("https://bitbucket.org/api/1.0/groups/#{owner}/#{group}/members/#{user}")
    auth = new Buffer(owner + ':' + password).toString('base64')
    req.headers Authorization: "Basic #{auth}"

    req.put() (err, res, body) ->
      if err
        msg.send "whoops! an error has occcured: #{err}"
      else if res.statusCode == 401
        msg.send "There's something wrong your username and password for Bitbucket."
      else if res.statusCode == 200
        msg.send "User #{user} added to #{group} group."
      else
        msg.send "#{res.statusCode}: #{body}"


module.exports = (robot) ->
    robot.respond /bitbucket create ([0-9a-z\-]+)?/i, (msg) ->
      create(msg)

    robot.respond /bitbucket add ([^~,]+)? to ([^~,]+)?/i, (msg) ->
      addUser(msg)
