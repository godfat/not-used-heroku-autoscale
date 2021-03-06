require "spec_helper"
require "heroku/autoscale"

describe Heroku::Autoscale do

  include Rack::Test::Methods

  def noop
    lambda {|env| 'ok'}
  end

  describe "option validation" do
    it "requires username" do
      lambda { Heroku::Autoscale.new(noop) }.should raise_error(/Must supply :username/)
    end

    it "requires password" do
      lambda { Heroku::Autoscale.new(noop) }.should raise_error(/Must supply :password/)
    end

    it "requires app_name" do
      lambda { Heroku::Autoscale.new(noop) }.should raise_error(/Must supply :app_name/)
    end
  end

  describe "with valid options" do
    let(:app) do
      frequency = 10
      mock(Random).rand(60).once{ -frequency*2 }
      Heroku::Autoscale.new noop,
        :defer => false,
        :username => "test_username",
        :password => "test_password",
        :app_name => "test_app_name",
        :min_dynos       => 1,
        :max_dynos       => 10,
        :queue_wait_low  => 10,
        :queue_wait_high => 100,
        :min_frequency   => frequency
    end

    it 'wont blow' do
      mock(app).current_dynos{ raise 'boom' }
      mock(logger = Object.new).send('error', 'ERROR: Heroku::Autoscale: boom')

      app.call({'rack.logger' => logger}).should == 'ok'
    end

    it "scales up" do
      heroku = mock(Heroku::Client)
      heroku.info("test_app_name") { { :dynos => 1 } }
      heroku.set_dynos("test_app_name", 2)

      mock(app).heroku.times(any_times) { heroku }
      app.call({ "HTTP_X_HEROKU_QUEUE_WAIT_TIME" => 101 })
    end

    it "scales down" do
      heroku = mock(Heroku::Client)
      heroku.info("test_app_name") { { :dynos => 3 } }
      heroku.set_dynos("test_app_name", 2)

      mock(app).heroku.times(any_times) { heroku }
      app.call({ "HTTP_X_HEROKU_QUEUE_WAIT_TIME" => 9 })
    end

    it "wont go below one dyno" do
      heroku = mock(Heroku::Client)
      heroku.info("test_app_name") { { :dynos => 1 } }
      heroku.set_dynos.times(0)

      mock(app).heroku.times(any_times) { heroku }
      app.call({ "HTTP_X_HEROKU_QUEUE_WAIT_TIME" => 9 })
    end

    it "respects max dynos" do
      heroku = mock(Heroku::Client)
      heroku.info("test_app_name") { { :dynos => 10 } }
      heroku.set_dynos.times(0)

      mock(app).heroku.times(any_times) { heroku }
      app.call({ "HTTP_X_HEROKU_QUEUE_WAIT_TIME" => 101 })
    end

    it "respects min dynos" do
      app.options[:min_dynos] = 2
      heroku = mock(Heroku::Client)
      heroku.info("test_app_name") { { :dynos => 2 } }
      heroku.set_dynos.times(0)

      mock(app).heroku.times(any_times) { heroku }
      app.call({ "HTTP_X_HEROKU_QUEUE_WAIT_TIME" => 9 })
    end

    it "doesn't flap" do
      heroku = mock(Heroku::Client)
      heroku.info("test_app_name").once { { :dynos => 5 } }
      heroku.set_dynos.with_any_args.once

      mock(app).heroku.times(any_times) { heroku }
      app.call({ "HTTP_X_HEROKU_QUEUE_WAIT_TIME" => 9 })
      app.call({ "HTTP_X_HEROKU_QUEUE_WAIT_TIME" => 9 })
    end
  end

end
