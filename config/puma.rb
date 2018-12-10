# frozen_string_literal: true

# config/puma.rb
app_dir = Dir.getwd.to_s

# Run as daemon?
run_as_daemon = ENV.fetch('DAEMON') { false }

# Specifies the `environment` that Puma will run in.
environment ENV.fetch('APP_ENV') { 'development' }

# Logging
stdout_redirect "#{app_dir}/log/puma.stdout.log", "#{app_dir}/log/puma.stderr.log", true if run_as_daemon

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
# port ENV.fetch('PORT') { 3333 }

# Unix socket bind
bind "unix://#{app_dir}/tmp/puma.socket"

# Set master PID and state locations
pidfile "#{app_dir}/tmp/puma.pid"
state_path "#{app_dir}/tmp/puma.state"

rackup "#{app_dir}/config.ru"

threads 0, 5

activate_control_app

# Daemonize the server into the background. Highly suggest that
# this be combined with “pidfile” and “stdout_redirect”.
# The default is “false”.
daemonize true if run_as_daemon
