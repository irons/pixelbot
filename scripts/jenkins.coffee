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
#   hubot build <jobNumber> - builds the job specified by [jobNumber]. List jobs to get number.
#   hubot describe <jobNumber> - Describes the specified Jenkins job by [jobNumber].
#   hubot last <jobNumber> - Details about the last build for the job specified by [jobNumber].
#   hubot log <jobNumber> -b <build number> (optional) - uploads Jenkins console log of job specified by [jobNumber]. List jobs to get number.
#
# Author:
# Jesse Chen

querystring = require 'querystring'
fs = require 'fs'
request = require 'request'

# Holds jobs and info on jobs as objects.
jobList = {}

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
      params = ""
      if variants
        vn = variants.split(' ')
        for v in job_variants
          console.log(v)
          axes = v.split(',')
          for axis in axes
            a = axis.split("=")
            if a[1].toUpperCase() is vn[0].toUpperCase()
              str = a[0].toUpperCase() + "V=" + a[1] + "&"
              if params.indexOf(str) == -1
                params += str
            else if (vn.length > 1 && (a[1].toUpperCase() is vn[vn.length - 1].toUpperCase()))
              str = a[0].toUpperCase() + "V=" + a[1] + "&"
              if params.indexOf(str) == -1
                params += str
      console.log(params)

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

jenkinsDescribeById = (msg) ->
    # Switch the index with the job name
    job = jobList[parseInt(msg.match[1])]

    if job
      if job.indexOf("build-variant") != -1
        info = job.split("build-variant: [")
        jobname = info[0].split(",")[0]
        variant = info[1].split("]")[0]
        msg.match[1] = jobname + "/" + variant
      else
        msg.match[1] = job
      jenkinsDescribe(msg)
    else
      msg.reply "I couldn't find that job. Try 'jenkins list' to get a list."


jenkinsDescribe = (msg) ->
    url = process.env.HUBOT_JENKINS_URL
    job = msg.match[1]

    if jenkinsCheckChannel(msg, job)
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
    else
      msg.reply "I'm sorry. I don't know the job you want me to describe."

jenkinsLastById = (msg) ->
    # Switch the index with the job name
    job = jobList[parseInt(msg.match[1])]

    if job
      if job.indexOf("build-variant") != -1
        info = job.split("build-variant: [")
        jobname = info[0].split(",")[0]
        variant = info[1].split("]")[0]
        msg.match[1] = jobname + "/" + variant
      else
        msg.match[1] = job
      jenkinsLast(msg)
    else
      msg.reply "I couldn't find that job. Try 'jenkins list' to get a list."

jenkinsLast = (msg) ->
    url = process.env.HUBOT_JENKINS_URL
    job = msg.match[1]

    if jenkinsCheckChannel(msg, job)
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
    else
      msg.reply "I'm sorry. I don't know the job you entered."

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
              response += "\n Trigger a build by using the commands 'build android|ios'. To get more information, including build parameters, on a specifc job listed above, use the command 'describe <job name>'."
              msg.send response

          catch error
            msg.send error

# check that Jenkins job name matches chat room name
jenkinsCheckChannel = (msg, job_name) ->
      channel = msg.envelope.room
      # splitting a string, e.g. android-hongkong, into an array, and getting the last element in that array, e.g. 'hongkong'.
      # Slack channels names should end with market names to correctly match with available Jenkins jobs
      market = channel.split('-').pop()
      return (job_name.indexOf(market) != -1 || channel.match("build-management"))

# Get build log by ID
jenkinsBuildLogById = (msg, robot) ->
    job = jobList[parseInt(msg.match[1]) ]
    build_num = msg.match[2]

    if build_num
      msg.match[2] = build_num

    if job
      if job.indexOf(",") != -1
        name = job.split(", ")
        #clean up to pass in the correct path to the console log on jenkins for the variant
        variant = name[1].split("[")[1].split("]")[0]
        msg.match[1] = name[0]
        msg.match[3] = variant
      else
        msg.match[1] = job
        # Ensure that if a build number was specified it's not mistaken for the build variant in jenkinsBuildLog
        msg.match[3] = null

      jenkinsBuildLog(msg, robot)
    else
      msg.send "I couldn't find that job. Try running 'jenkins list' for a list of available jobs."


jenkinsBuildLog = (msg, robot) ->
    url = process.env.HUBOT_JENKINS_URL
    job = msg.match[1]
    build_num = msg.match[2]
    variant = msg.match[3]

    if (jobList.length == 0)
      msg.send "I couldn't locate any jobs. Please try running 'jenkins list' for a list of available jobs."
    else
      if (!jenkinsCheckChannel(msg, job))
        msg.send "I can't upload build logs for that job. Are you in the correct Slack channel?"
      else
        build = if build_num then "#{build_num}" else "lastBuild"
        path = if variant then "#{url}/job/#{job}/#{variant}/#{build}/consoleText" else "#{url}/job/#{job}/#{build}/consoleText"

        channel = ""
        log_file = "log-#{job}-#{build}.txt"
        req = msg.http(path)

        if process.env.HUBOT_JENKINS_AUTH
          auth = new Buffer(process.env.HUBOT_JENKINS_AUTH).toString('base64')
          req.headers Authorization: "Basic #{auth}"

        req.get() (err,res,body) ->
          if err
            msg.send "Whoops, something went wrong! #{err}"
          else if 400 <= res.statusCode
            msg.send "#{res.statusCode}: Build log not found, try passing in a different build number after the job name? "
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
                  options = {token: "#{api_token}", channels: "#{channel}", filename: "#{job}-build-#{build}-log.txt"}
                  options["content"] = log_body()

                  request.post "https://api.slack.com/api/files.upload", {form: options }, (error, response, body) ->
                    if error
                      msg.send "something went wrong: #{error}"
                    else
                      msg.send "Build file uploaded."
                      # Delete build log file after upload
                      fs.unlinkSync log_file

            catch error
              msg.send error

module.exports = (robot) ->
  robot.respond /build (android|ios)(?:\s)?([a-z\s]+)?/i, (msg) ->
    jenkinsBuild(msg)

  robot.respond /list( (.+))?/i, (msg) ->
    jenkinsList(msg)

  robot.respond /describe (\d+)?/i, (msg) ->
    jenkinsDescribeById(msg)

  robot.respond /last (\d+)?/i, (msg) ->
    jenkinsLastById(msg)

  robot.respond /log (\d+)(?:[\,\-b ]+)?(\d+)?/i, (msg) ->
    slack_bot = robot.adapter.client
    jenkinsBuildLogById(msg, slack_bot)

  robot.jenkins = {
    list: jenkinsList,
    build: jenkinsBuild,
    describe: jenkinsDescribe,
    last: jenkinsLast,
    log: jenkinsBuildLog
  }
