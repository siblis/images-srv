# app.rb
require 'rubygems'
require 'bundler/setup' # If you're using bundler, you will need to add this
require 'dotenv/load'
require 'sinatra'
require 'sinatra/json'
require 'slim'
require 'fileutils'
require 'faraday'
require 'mini_magick'
require_relative 'config/app'
IMAGES_MASK = '*.{bmp,gif,jpeg,jpg,png,tif,tiff}'.freeze
IMAGES_REGEX = /.(bmp|gif|jpg|png|tif|tiff)$/.freeze

# проверка аутентификации (авторизации)
before do
  auth!
end

# редикерт на картинки
get '/' do
  redirect to('/images')
end

# вывести весь список картинок
get '/images' do
  images = []
  Dir["#{settings.images_dir}/*/"].map do |resource_dir|
    resource = resource_dir.split('/').last
    next unless settings.resources.include?(resource)

    Dir["#{resource_dir}/*/"].map do |id_dir|
      id = id_dir.split('/').last.to_i
      next unless id > 0

      sizes = Dir["#{id_dir}/*/"].map { |d| d.split('/').last }.select { |d| d.match(/^\d+x\d+$/) }
      files = Dir["#{id_dir}/#{IMAGES_MASK}"].map { |d| d.split('/').last }
      files.each do |file|
        images << {
          resource: resource,
          resource_id: id,
          sizes: sizes.select { |size| File.file? "#{id_dir}/#{size}/#{file}" },
          image_path: "#{settings.images_sub}/#{resource}/#{id}/#{file}"
        }
      end
    end
  end
  json(images.sort_by { |image| image[:image_path] })
end

# простенькая форма загрузки картинок
get '/images/:resource/:id' do
  if settings.resources.include?(params[:resource]) && params[:id].to_i > 0
    images_dir = File.join(settings.images_dir, "/#{params[:resource]}/#{params[:id]}")
    images_path = images_dir.gsub(settings.public_dir, '')
    images = Dir["#{images_dir}/**/#{IMAGES_MASK}"].map { |f| f.gsub("#{images_dir}/", '') }.sort
  end
  slim :upload, locals: { images_path: images_path, images: images }
end

# обработка загрузки
post '/images/:resource/:id/upload' do
  if params[:file]
    tempfile = params[:file][:tempfile]
    filename = params[:file][:filename]
    if settings.resources.include?(params[:resource])
      target_dir = File.join(settings.images_dir, "/#{params[:resource]}/#{params[:id]}")
    end
    if target_dir
      FileUtils.mkdir_p(target_dir) unless File.exist?(target_dir)
      target_file = File.join(target_dir, "/#{filename}")
      FileUtils.cp(tempfile.path, target_file)
      File.chmod(0o644, target_file) # чтоб раздавать картинки через nginx
      # \/ crop & resize images
      settings.images_sizes.split(',').each do |image_size|
        processed_dir = File.join(target_dir, "/#{image_size}")
        processed_file = File.join(processed_dir, "/#{filename}")
        FileUtils.mkdir_p(processed_dir) unless File.exist?(processed_dir)

        image = MiniMagick::Image.open(tempfile.path)
        # crop
        offsets = params[:offsets].scan(/[+-]\d+[+-]\d+/) if params[:offsets]
        offsets.each { |offset| image.crop offset }
        # resize
        image.combine_options do |opt|
          opt.resize "#{image_size}^"
          opt.gravity 'center'
          opt.extent image_size
        end
        # save
        image.format 'jpeg'
        image.write processed_file.gsub(IMAGES_REGEX, '.jpeg')
      end
      # /\ resize & crop image
      json message: 'Готово!'
    else
      json error: 'Неверный ресурс!', status: :unprocessable_entity
    end
  else
    json error: 'Файл не выбран!', status: :unprocessable_entity
  end
end

not_found do
  halt 404, { error: 'Неверный запрос!' }.to_json
end

# проверить токен на главном бэкенде
def auth!
  result = nil
  email = request.env['HTTP_X_USER_EMAIL']
  token = request.env['HTTP_X_USER_TOKEN']
  if email && token
    result = Faraday.get do |req|
      req.url "#{settings.back_host}/auth/check"
      req.headers['Content-Type'] = 'application/json'
      req.headers['X-USER-EMAIL'] = email
      req.headers['X-USER-TOKEN'] = token
    end
  end
  # user = JSON.parse(result.body, symbolize_names: true)[:user] if result && result.success?
  halt 401, { error: 'Недействительный токен и/или отсутствуют права доступа!' }.to_json unless result \
                                                                                             && result.success?
  # && user[:role] == 'admin'
end
