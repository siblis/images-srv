# config/app.rb
configure do
  enable :logging
  disable :sessions

  # run on puma
  set :server, :puma

  # main server api
  set :back_host, ENV.fetch('BACK_HOST') { 'http://localhost:3000' }

  # Public dir
  set :public_dir, ENV.fetch('PUBLIC_DIR') { File.expand_path('../public', settings.root) }

  # Images dir
  set :images_sub, ENV.fetch('IMAGES_SUB') { '/images' }
  set :images_dir, File.join(settings.public_dir, settings.images_sub)

  set :resources, %w[models vehicles]

  # Image sizes
  set :images_sizes, ENV.fetch('IMAGES_SIZES') { '500x400,400x300' }
end
