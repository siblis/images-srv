# frozen_string_literal: true

# config.ru
require 'bundler/setup'
require './app'

run Sinatra::Application
