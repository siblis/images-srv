# config/app.rb
configure do
  enable :logging

  # run on puma
  set :server, :puma

  # main server api
  set :back_host, ENV.fetch('BACK_HOST') { 'http://localhost:3000' }

  # Public dir
  set :public_dir, ENV.fetch('PUBLIC_DIR') { File.expand_path("../public", settings.root) }

  # Images dir
  set :images_dir, File.join(settings.public_dir, "/images")
  set :resources, [ 'models', 'vehicles' ]
end
