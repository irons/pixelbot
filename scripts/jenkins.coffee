# Description:
#   Interact with your Jenkins CI server
#
# Dependencies:
#   None
#
# Configuration:
#   HUBOT_JENKINS_URL
#   HUBOT_JENKINS_AUTH
#   HUBOT_SLACK_API_TOKEN
#
#   Auth should be in the "user:password" format.
#
# Commands:
#
#   hubot list - lists Jenkins jobs.
#   hubot build <android>|<ios> <variants> (optional) - builds the android or ios job
#   hubot describe <android>|<ios> - describe the android or ios job.
#   hubot last <android>|<ios> - details about the last build for the android or ios job.
#   hubot log <android>|<ios> -b <build number> (optional) - uploads Jenkins console log of android|ios job. Logs for all variants will be uploaded
#
# Author:
# Jesse Chen

querystring = require 'querystring'
fs = require 'fs'
request = require 'request'

# Holds jobs and info on jobs as objects.
jobList = {}

# Takes a list of build variants as parameter and returns an object with names as properties and values in lists.
buildVariant = (bvlist) ->
  bv = {}
  # create properties using name of user-defined axes
  first_var = bvlist[0].split(',')
  for name_value in first_var
    bv[name_value.split("=")[0]] = []

  for variant in bvlist
    axis = variant.split(',')
    for a in axis
      nv = a.split('=')
      if bv[nv[0]].indexOf(nv[1]) == -1
        bv[nv[0]].push nv[1]

  console.log(JSON.stringify(bv))

  return bv

# check that Jenkins job name matches chat room name
jenkinsCheckChannel = (msg, job_name) ->
    channel = msg.envelope.room
    # Slack channels names should end with market names to correctly match with available Jenkins jobs
    market = channel.split('-').pop()
    return (job_name.indexOf(market) != -1 || channel.match("build-management"))

jenkinsBuild = (msg, buildWithEmptyParameters) ->
    platform = msg.match[1]
    variants = msg.match[2]
    # Get market name by getting the last word in Slack channel name. E.g. moonshine-usa --> market is usa
    market = msg.envelope.room.split('-').pop()
    job = "starbucks-#{platform}-#{market}"

    job_info = jobList[job]
    console.log("job info: " + JSON.stringify(job_info))

    # Get build variants and build out build parameter string
    if "build-variants" of job_info
      job_variants = job_info["build-variants"]
      bv = buildVariant(job_variants)
      params = ""
      if variants
        vars = variants.split(' ')
        upper_vars = vars.map((x) ->
          x.toUpperCase()
          )
        for name of bv
          console.log(name)
          for value in bv[name]
            console.log(value)
            if upper_vars.indexOf(value.toUpperCase()) != -1
              params += name.toUpperCase() + "V=" + value + "&"
      console.log(params)

    #   params = ""
    #   if variants
    #     vn = variants.split(' ')
    #     for v in job_variants
    #       console.log(v)
    #       axes = v.split(',')
    #       for axis in axes
    #         a = axis.split("=")
    #         if a[1].toUpperCase() is vn[0].toUpperCase()
    #           str = a[0].toUpperCase() + "V=" + a[1] + "&"
    #           if params.indexOf(str) == -1
    #             params += str
    #         else if (vn.length > 1 && (a[1].toUpperCase() is vn[vn.length - 1].toUpperCase()))
    #           str = a[0].toUpperCase() + "V=" + a[1] + "&"
    #           if params.indexOf(str) == -1
    #             params += str
    #   console.log(params)

    url = process.env.HUBOT_JENKINS_URL
    command = if buildWithEmptyParameters then "buildWithParameters" else "build"
    path = if params then "#{url}/job/#{job}/buildWithParameters?#{params}" else "#{url}/job/#{job}/#{command}"

    console.log(path)

    req = msg.http(path)

    if process.env.HUBOT_JENKINS_AUTH
      auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"

      req.header('Content-Length', 0)
      req.post() (err, res, body) ->
        if err
          msg.reply "Jenkins says: #{err}"
        else if 200 <= res.statusCode < 400 # Or, not an error code.
          msg.reply "(#{res.statusCode}) Build started for #{job} #{url}/job/#{job}"
        else if 400 == res.statusCode
          jenkinsBuild(msg, true)
        else
          msg.reply "Jenkins says: Status #{res.statusCode} #{body}"

jenkinsDescribe = (msg) ->
    url = process.env.HUBOT_JENKINS_URL
    platform = msg.match[1]
    # Get market name by getting the last word in Slack channel name. E.g. moonshine-usa --> market is usa
    market = msg.envelope.room.split('-').pop()
    job = "starbucks-#{platform}-#{market}"

    path = "#{url}/job/#{job}/api/json"

    req = msg.http(path)

    if process.env.HUBOT_JENKINS_AUTH
      auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.header('Content-Length', 0)
    req.get() (err, res, body) ->
        if err
          msg.send "Jenkins says: #{err}"
        else
          response = ""
          try
            content = JSON.parse(body)
            response += "JOB: #{content.displayName}\n"
            response += "URL: #{content.url}\n"

            if content.description
              response += "DESCRIPTION: #{content.description}\n"

            response += "ENABLED: #{content.buildable}\n"
            response += "STATUS: #{content.color}\n"

            tmpReport = ""
            if content.healthReport.length > 0
              for report in content.healthReport
                tmpReport += "\n  #{report.description}"
            else
              tmpReport = " unknown"
            response += "HEALTH: #{tmpReport}\n"

            parameters = ""
            for item in content.actions
              if item.parameterDefinitions
                for param in item.parameterDefinitions
                  tmpDescription = if param.description then " - #{param.description} " else ""
                  tmpDefault = if param.defaultParameterValue then " (default=#{param.defaultParameterValue.value})" else ""
                  parameters += "\n  #{param.name}#{tmpDescription}#{tmpDefault}"

            if parameters != ""
              response += "PARAMETERS: #{parameters}\n"

            msg.send response

            if not content.lastBuild
              return

            path = "#{url}/job/#{job}/#{content.lastBuild.number}/api/json"
            req = msg.http(path)
            if process.env.HUBOT_JENKINS_AUTH
              auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
              req.headers Authorization: "Basic #{auth}"

            req.header('Content-Length', 0)
            req.get() (err, res, body) ->
                if err
                  msg.send "Jenkins says: #{err}"
                else
                  response = ""
                  try
                    content = JSON.parse(body)
                    console.log(JSON.stringify(content, null, 4))
                    jobstatus = content.result || 'PENDING'
                    jobdate = new Date(content.timestamp);
                    response += "LAST JOB: #{jobstatus}, #{jobdate}\n"

                    msg.send response
                  catch error
                    msg.send error

          catch error
            msg.send error

jenkinsLast = (msg) ->
    url = process.env.HUBOT_JENKINS_URL
    platform = msg.match[1]
    market = msg.envelope.room.split('-').pop()
    job = "starbucks-#{platform}-#{market}"

    path = "#{url}/job/#{job}/lastBuild/api/json"

    req = msg.http(path)

    if process.env.HUBOT_JENKINS_AUTH
      auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.header('Content-Length', 0)
    req.get() (err, res, body) ->
        if err
          msg.send "Jenkins says: #{err}"
        else
          response = ""
          try
            content = JSON.parse(body)
            response += "NAME: #{content.fullDisplayName}\n"
            response += "URL: #{content.url}\n"

            if content.description
              response += "DESCRIPTION: #{content.description}\n"

            response += "BUILDING: #{content.building}\n"

            msg.send response

jenkinsList = (msg) ->
    url = process.env.HUBOT_JENKINS_URL
    filter = new RegExp(msg.match[2], 'i')
    req = msg.http("#{url}/api/json?depth=1&tree=jobs[name,activeConfigurations[name]]")

    if process.env.HUBOT_JENKINS_AUTH
      auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.get() (err, res, body) ->
        response = ""
        if err
          msg.send "Jenkins says: #{err}"
        else
          try
            content = JSON.parse(body)
            for job in content.jobs
              # Add the job to the jobList
              if !(job.name of jobList)
                jobList[job.name] = {}

                # Check platform
                if job.name.indexOf("ios") != -1
                  jobList[job.name]["platform"] = "ios"
                else if job.name.indexOf("android") != -1
                  jobList[job.name]["platform"] = "android"
                else
                  jobList[job.name]["platform"] = "na"  #not available if not ios/android

                # Check for build variants
                if job.activeConfigurations?
                  bv = []
                  for variant in job.activeConfigurations
                    if variant.name not in bv
                      bv.push variant.name
                  jobList[job.name]["build-variants"] = bv

              # Check job against channel name before adding it to the response
              if (jenkinsCheckChannel(msg, job.name))
               response += "#{job.name} \n"

            console.log(JSON.stringify(jobList))


            if response.length == 0
              msg.reply "There appears to be no jobs available for you. If you believe this is an error, please contact the build management team."
            else
              response += "\n Trigger a build by using the commands 'build android|ios'. To get more information, including build parameters, on a specifc job listed above, use the command 'describe android|ios'."
              msg.send response

          catch error
            msg.send error

# Calls upload log if platform type does not have any variants, otherwise, lists available variants and asks user to pass in build variant as command arg.
jenkinsBuildLog = (msg, robot) ->
    platform = msg.match[1]
    variant = msg.match[2]
    market = msg.envelope.room.split('-').pop()
    job = "starbucks-#{platform}-#{market}"
    msg.match[1] = job

    if "build-variants" of jobList[job]
      bv = buildVariant(jobList[job]["build-variants"])
      if !(variant?)
        lists = ""
        response = "Please choose one option from each list: "
        for type of bv
          lists += "    #{type}: " + bv[type] + "\n"
          response += " #{type},"
        response += " and use log command again. For example, 'log ios <choice> <choice>'. \n" + lists
        msg.reply response
      else
        bvstring = ""
        var_list = variant.split(' ')
        for v in var_list
          for name, value of bv
            if value.indexOf(v) != -1
              bvstring += "#{name}=#{v},"
        bvstring = bvstring.slice(0, -1)

        msg.match[2] = bvstring
        jenkinsUploadLog(msg, robot)
    else
      jenkinsUploadLog(msg, robot)

jenkinsUploadLog = (msg, robot) ->
    url = process.env.HUBOT_JENKINS_URL
    job = msg.match[1]
    variant = msg.match[2]
    build_num = msg.match[3]

    build = if build_num then "#{build_num}" else "lastBuild"
    path = if variant then "#{url}/job/#{job}/#{variant}/#{build}/consoleText" else "#{url}/job/#{job}/#{build}/consoleText"

    channel = ""
    log_file = "log-#{job}-#{build}-#{variant}.txt"
    req = msg.http(path)

    if process.env.HUBOT_JENKINS_AUTH
      auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
      req.headers Authorization: "Basic #{auth}"

    req.get() (err,res,body) ->
      if err
        msg.send "Whoops, something went wrong! #{err}"
      else if 400 <= res.statusCode
        msg.send "#{res.statusCode}: Build log not found for #{job}-#{variant}, try passing in a different build number after the job name? "
      else
        try
          fs.writeFile log_file, "#{body}", (error) ->
            if error
              console.error("Error writing file #{log_file}", error)
            else
              log_body = ->
                fs.readFile log_file, 'utf8', (error, body)->
                  console.log("something went wrong trying when trying to read in the log file") if error
                return body

              # get the slack channel id to pass to slack api upload file method
              for k of robot.channels
                channel_name = "#{robot.channels[k].name}"
                if channel_name.match msg.envelope.room
                  console.log("#{k} :#{robot.channels[k].name}")
                  channel += "#{k}"
              #check private groups if channel_name still empty
              if channel_name.match ""
                for j of robot.groups
                  group_name = "#{robot.groups[j].name}"
                  if group_name.match msg.envelope.room
                    console.log("#{j}: #{robot.groups[j].name}")
                    channel += "#{j}"
              api_token = process.env.HUBOT_SLACK_API_TOKEN
              options = {token: "#{api_token}", channels: "#{channel}", filename: "#{job}-#{variant}-#{build}-log.txt"}
              options["content"] = log_body()

              request.post "https://api.slack.com/api/files.upload", {form: options }, (error, response, body) ->
                if error
                  msg.send "something went wrong: #{error}"
                else
                  msg.send "Build file uploaded for #{job} #{variant}"
                  # Delete build log file after upload
                  fs.unlinkSync log_file

        catch error
          msg.send error

module.exports = (robot) ->
  robot.respond /build (android|ios)(?:\s)?([a-z\s]+)?/i, (msg) ->
    jenkinsBuild(msg)

  robot.respond /list( (.+))?/i, (msg) ->
    jenkinsList(msg)

  robot.respond /describe (android|ios)/i, (msg) ->
    jenkinsDescribe(msg)

  robot.respond /last (android|ios)/i, (msg) ->
    jenkinsLast(msg)

  robot.respond /log (android|ios)(?:\s)?([0-9a-z\s]+[0-9\.a-z\ ]+)?(?:-b)?(?:\s)?(\d+)?/i, (msg) ->
    slack_bot = robot.adapter.client
    jenkinsBuildLog(msg, slack_bot)

  robot.jenkins = {
    list: jenkinsList,
    build: jenkinsBuild,
    describe: jenkinsDescribe,
    last: jenkinsLast,
    log: jenkinsBuildLog
  }
