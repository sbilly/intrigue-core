#!/usr/bin/env ruby
require 'thor'
require 'json'
require 'rest-client'
require 'intrigue_api_client'
require 'pry' #DEBUG

class CoreCli < Thor

  def initialize(*args)
    super
    $intrigue_basedir = File.dirname(__FILE__)
    $config = JSON.parse File.open("#{$intrigue_basedir}/config/config.json").read
    @server_uri = ENV.fetch("INTRIGUE_API_URI", "http://intrigue:#{$config["password"]}@127.0.0.1:7777/v1")
    @delim = "#"
    @debug = true
    # Connect to Intrigue API
    @api = IntrigueApi.new(@server_uri)
  end

  desc "list", "List all available tasks"
  def list
    puts "Available tasks:"
    tasks_hash = JSON.parse(RestClient.get("#{@server_uri}/tasks.json"))
    tasks_hash.each do |task|
      task_name = task["name"]
      task_description = task["description"]
      puts "Task: #{task_name} - #{task_description}"
    end
  end

  desc "info [Task]", "Show detailed about a task"
  def info(task_name)

    begin
      task_info = JSON.parse(RestClient.get("#{@server_uri}/tasks/#{task_name}.json"))

      puts "Name: #{task_info["name"]} (#{task_info["pretty_name"]})"
      puts "Description: #{task_info["description"]}"
      puts "Authors: #{task_info["authors"].join(", ")}"
      puts "---"
      puts "Allowed Types: #{task_info["allowed_types"].join(", ")}"

      puts "Options: "
      task_info["allowed_options"].each do |opt|
        puts " - #{opt["name"]} (#{opt["type"]})"
      end

      puts "Example Entities:"

      task_info["example_entities"].each do |x|
        puts " - #{x["type"]}:#{x["details"]["name"]}"
      end

      puts "Creates: #{task_info["created_types"].join(", ")}"

    rescue RestClient::InternalServerError => e
      puts "No task found"
      puts "Exception #{e}"
      return
    end
  end

  desc "background [Task] [Type#Entity] [Option1=Value1#...#...] [Handlers]", "Start and background a single task. Returns the ID"
  def background(task_name,entity,option_string,handler_string)

    entity_hash = _parse_entity entity
    options_list = _parse_options option_string
    handler_list = _parse_handlers handler_string
    project_name = "Default"

    ### Construct the request
    task_id = @api.start_and_background(project_name,task_name,entity_hash,options_list,handler_list)

    unless task_id # technically a nil is returned , but becomes an empty string
      puts "[-] Task not started. Unknown Error. Exiting"
      return
    end

  puts "[+] Started task: #{task_id}"
  end

  desc "start [Task] [Type#Entity] [Option1=Value1#...#...] [Handlers]", "Start a single task. Returns the result"
  def start(task_name,entity_string,option_string=nil, handler_string=nil)
    single(task_name,entity_string,option_string,handler_string)
  end

  desc "single [Task] [Type#Entity] [Option1=Value1#...#...] [Handlers]", "Start a single task. Returns the result"
  def single(task_name,entity_string,option_string=nil, handler_string=nil)

    # Do the setup
    entity_hash = _parse_entity entity_string
    options_list = _parse_options option_string
    handler_list = _parse_handlers handler_string
    project_name = "Default"

    # Get the response from the API
    #puts "[+] Starting Task."
    response = @api.start(project_name,task_name,entity_hash,options_list,handler_list)
    #puts "[D] Got response: #{response}" if @debug
    return "Error retrieving response. Failing. Response was: #{response}" unless  response
    #puts "[+] Task complete!"

    # Parse the response
    #puts "[+] Start Results"
    response["entities"].each do |entity|
      puts "  [x] #{entity["type"]}#{@delim}#{entity["name"]}"
    end
    #puts "[+] End Results"

    # Print the task log
    puts "[+] Task Log:\n"
    response["log"].each_line{|x| puts "  #{x}" }
  end

  desc "scan [Project Name] [Scan Type] [Type#Entity] [Option1=Value1#...#...] [Handlers]", "Start a recursive scan. Returns the result"
  def scan(scan_type,entity_string,option_string=nil,handler_string="")
    entity_hash  = _parse_entity entity_string
    options_list = _parse_options option_string
    handler_list = _parse_handlers handler_string
    project_name = "Default"

    @api.start_scan_and_background(project_name,scan_type,entity_hash,options_list,handler_list)
  end


  ###
  ### XXX - rewrite this so it uses the API
  ###
  desc "load [Task] [File] [Option1=Value1#...#...] [Handlers]", "Load entities from a file and run task on each of them"
  def load(task_name,filename,options_string=nil,handler_string="")

    # Load in the main core file for direct access to TaskFactory and the Tasks
    # This makes this super speedy.
    require_relative 'core'

    lines = File.open(filename,"r").readlines

    project_name = "#{task_name} on #{filename} - #{Time.now.strftime("%Y%m%d%H%M")}"
    p = Intrigue::Model::Project.create(:name => project_name)

    lines.each do |line|
      line.chomp!

      entity = _parse_entity line
      options = _parse_options options_string
      handlers = _parse_handlers handler_string

      payload = {
        "task" => task_name,
        "entity" => entity,
        "options" => options,
      }

      task_result_id = SecureRandom.uuid

      # Check if the entity already exists, and if not, create a new entity
      e = Intrigue::Model::Entity.first(:name => entity["details"]["name"])
      unless e
        e = Intrigue::Model::Entity.create({
          :type => "Intrigue::Entity::#{entity["type"]}",
          :name => entity["details"]["name"],
          :details => entity["details"],
          :project => p
        })
      end

      # Create a new task result
      task_result = Intrigue::Model::TaskResult.create({
        :name => task_name,
        :task_name => task_name,
        :base_entity => e,
        :options => options,
        :logger => Intrigue::Model::Logger.create(:project => p),
        :project => p
      })

      # XXX - Create the task
      task = Intrigue::TaskFactory.create_by_name(task_name)
      jid = task.class.perform_async task_result.id, handlers

      puts "Created task #{task_result.id} for entity #{e}"
    end
  end

private


  # parse out entity from the cli
  def _parse_entity(entity_string)
    entity_type = entity_string.split(@delim).first
    entity_name = entity_string.split(@delim).last

    entity_hash = {
      "type" => entity_type,
      "name" => entity_name,
      "details" => { "name" => entity_name}
    }

    puts "Got entity: #{entity_hash}" if @debug

  entity_hash
  end

  # Parse out options from cli
  def _parse_options(option_string)

      return [] unless option_string

      options_list = []
      options_list = option_string.split(@delim).map do |option|
        { "name" => option.split("=").first, "value" => option.split("=").last }
      end

      puts "Got options: #{options_list}" if @debug

  options_list
  end

  # Parse out options from cli
  def _parse_handlers(handler_string)

      return [] unless handler_string

      handler_list = []
      handler_list = handler_string.split(",")

      puts "Got handlers: #{handler_list}" if @debug

  handler_list
  end

end # end class

CoreCli.start
