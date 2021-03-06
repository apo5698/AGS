require 'barnes'

workers Integer(ENV['WEB_CONCURRENCY'] || 2)
threads_count = Integer(ENV['RAILS_MAX_THREADS'] || 5)
threads threads_count, threads_count

preload_app!

rackup DefaultRackup
port ENV['PORT'] || 3000
environment ENV['RACK_ENV'] || 'development'

on_worker_boot do
  # Worker specific setup for Rails 4.1+
  # See: https://devcenter.heroku.com/articles/deploying-rails-applications-with-the-puma-web-server#on-worker-boot
  config = ActiveRecord::Base.configurations[Rails.env] || Rails.application.config.database_configuration[Rails.env]
  config['pool'] ||= ENV.fetch('WEB_CONCURRENCY', 2).to_i * ENV.fetch('RAILS_MAX_THREADS', 5).to_i
  config['checkout_timeout'] ||= 20
  ActiveRecord::Base.establish_connection(config)
end

before_fork do
  Barnes.start
end
