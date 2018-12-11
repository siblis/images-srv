# frozen_string_literal: true

source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# Sinatra as is
github 'sinatra/sinatra' do
  gem 'sinatra'
  gem 'sinatra-contrib'
end

# Use Puma as the app server
gem 'puma'

# Slim is a template language whose goal is reduce the syntax to the essential parts without becoming cryptic.
gem 'slim'

# Loads environment variables from `.env`.
gem 'dotenv'

# HTTP/REST API client library.
gem 'faraday'

# ruby-vips is a binding for the vips image processing library.
# It is extremely fast and it can process huge images without loading the whole image in memory.
# gem 'ruby-vips'

# Set of higher-level helper methods for image processing.
# gem 'image_processing'

# Manipulate images with minimal use of memory via ImageMagick / GraphicsMagick
gem 'mini_magick'

group :development, :test do
  gem 'rack-test'
  gem 'rspec'
end
