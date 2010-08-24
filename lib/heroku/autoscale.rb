
require "eventmachine"
require "heroku"
require "rack"

class Random
  def self.rand n
    super(n)
  end
end unless defined?(Random)

module Heroku
  class Autoscale

    VERSION = "0.2.2"

    attr_reader :app, :options, :last_accumulated

    def initialize(app, options={})
      @app = app
      @options = default_options.merge(options)
      @accumulator = 0
      # rand is here to make race condition less likely to happen
      @last_accumulated = Time.now + Random.rand(60)
      check_options!
    end

    def call(env)
      if options[:defer]
        EventMachine.defer { autoscale(env) }
      else
        autoscale(env)
      end

    ensure
      return app.call(env)
    end

private ######################################################################

    def autoscale(env)
      # dont do anything if we scaled too frequently ago
      return if (Time.now - last_accumulated) < options[:min_frequency]
      @last_accumulated = Time.now

      wait = queue_wait(env)
      @accumulator += wait
      @accumulator = (0.99 * @accumulator).floor

      if            wait >= options[:queue_wait_high]
        dynos = current_dynos + 1


      elsif         wait <= options[:queue_wait_low] &&
            @accumulator <= options[:queue_wait_low]

        dynos = current_dynos - 1

      else
        return
      end

      dynos = options[:min_dynos] if dynos < options[:min_dynos]
      dynos = options[:max_dynos] if dynos > options[:max_dynos]
      dynos = 1 if dynos < 1

      set_dynos(env, dynos)

    rescue Exception => e
      log(env, 'error', e)
    end

    def check_options!
      errors = []
      errors << "Must supply :username to Heroku::Autoscale" unless options[:username]
      errors << "Must supply :password to Heroku::Autoscale" unless options[:password]
      errors << "Must supply :app_name to Heroku::Autoscale" unless options[:app_name]
      raise errors.join(" / ") unless errors.empty?
    end

    def current_dynos
      heroku.info(options[:app_name])[:dynos].to_i
    end

    def default_options
      {
        :defer           => true,
        :min_dynos       => 1,
        :max_dynos       => 1,
        :queue_wait_high => 5000, # milliseconds
        :queue_wait_low  => 0,    # milliseconds
        :min_frequency   => 10    # seconds
      }
    end

    def heroku
      @heroku ||= Heroku::Client.new(options[:username], options[:password])
    end

    def queue_wait(env)
      env["HTTP_X_HEROKU_QUEUE_WAIT_TIME"].to_i
    end

    def set_dynos(env, count)
      log(env, 'warn', "set dynos to #{count}")

      heroku.set_dynos(options[:app_name], count)
    end

    def log env, kind, string
      return unless env['rack.logger']
      env['rack.logger'].send(
        kind, "#{kind.upcase}: Heroku::Autoscale: #{string}")
    end
  end
end
