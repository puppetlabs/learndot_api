require 'httparty'
require 'json'
require 'logger'

class Learndot::API
  attr_writer :logger

  def initialize(token = nil, debug = false, staging = false)
    @logger           = Logger.new(STDOUT)
    @logger.level     = debug ? Logger::DEBUG : Logger::WARN
    @logger.formatter = proc { |level, date, name, msg|
      "#{level}: #{msg}\n"
    }

    token   ||= get_token
    debug   ||= false
    staging ||= false

    # Set the base_url to the staging or production endpoint
    case staging
    when 'production', false
      @base_url = "https://learn.puppet.com/api/rest/v2"
    when 'staging', true
      @base_url = "https://puppetlabs-staging.trainingrocket.com/api/rest/v2"
    when 'sandbox'
      @base_url = "https://puppetlabs-sandbox.trainingrocket.com/api/rest/v2"
    end

    @headers  = {
      "TrainingRocket-Authorization"      => token,
      "Learndot Enterprise-Authorization" => token,
      "Content-Type" => "application/json",
      "Accept"       => "application/json; charset=utf-8"
    }
  end

  def search(entity, conditions = {}, query = {})
    endpoint       = "/manage/#{entity}/search"
    query[:asc]  ||= false
    query[:or]   ||= false

    if query.include? 'page'
      api_post(endpoint, conditions, query)
    else
      page do |count|
        query[:page] = count
        api_post(endpoint, conditions, query)
      end
    end
  end

  def count(entity, conditions = {})
    endpoint = "/manage/#{entity}/search"

    num_records = api_post(endpoint, conditions)['size']
    num_records.is_a?(Integer) ? num_records : 0
  end

  # keep seperate from create to avoid accidental record creation
  def update(entity, conditions, id)
    endpoint = "/manage/#{entity}/#{id}"
    api_post(endpoint, conditions)
  end

  def create(entity, conditions)
    endpoint = "/manage/#{entity}"
    api_post(endpoint, conditions)
  end

  ############### Private methods ###############
  def get_token
    return ENV['LEARNDOT_TOKEN'] if ENV.include? 'LEARNDOT_TOKEN'
    path = File.expand_path('~/.learndot_token')
    
    begin
      return File.read(path).strip
    rescue => e
      raise "API token (in env variable or #{path}) not readable. Exiting."
    end
  end

  def api_post(endpoint, conditions = {}, query = {})
    url = @base_url + endpoint
    @logger.debug "POST: #{url}"
    @logger.debug "  * Query params: #{query.inspect}"
    @logger.debug "  * Conditions: #{conditions.inspect}"


    response = HTTParty.post(url, {
      headers: @headers,
      query: query,
      body: conditions.to_json,
    })
    @logger.debug "#{response.code}: #{response.message}"
    raise response.message unless response.code == 200

    sleep 1 # dear god learndot
    response
  end

  def api_get(endpoint, query = {})
    url = @base_url + endpoint
    @logger.debug "GET: #{url}"
    @logger.debug "  * Query params: #{query.inspect}"
    @logger.debug "  * Conditions: #{conditions.inspect}"

    response = HTTParty.get(url, { headers: @headers, query: query })
    @logger.debug "#{response.code}: #{response.message}"
    raise response.message unless response.code == 200

    sleep 1 # dear god learndot
    response
  end

  def hash_response(response)
    result_hash = {}
    if response['size'].is_a?(Integer)
      response['results'].each do | result |
        result_hash[result['id']] = result
      end
    end
    return result_hash
  end

  # Call a method provided as a block until there's no more data to get back
  def page
    raise 'page() requires a block' unless block_given?

    response    = yield(1)
    num_records = response['size']

    if num_records.is_a?(Integer) && num_records > 25
      pages = (num_records / 25) + 1
      # start at 2 since first call returned first page
      for counter in 2..pages
        @logger.debug "Retrieving page #{counter} of #{pages}"
        results = yield(counter)['results']
        response['results'].concat(results) if results
      end
    end

    hash_response(response)
  end
  private :api_post, :api_get, :hash_response, :get_token, :page
  ############### End private methods ###############

end
