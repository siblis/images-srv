# frozen_string_literal: true

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

IMAGES_MASK = '*.{bmp,gif,jpeg,jpg,png,tif,tiff}'
IMAGES_REGEX = /.(bmp|gif|jpeg|jpg|png|tif|tiff)$/.freeze
IMAGES_FORMAT = 'jpeg'

# ничего лучше не придумал :)
class AppError < StandardError
  attr_reader :status

  def initialize(status = :internal_server_error, message = nil)
    super message if message
    @status = status
  end
end

before do
  # без origin никак, нужна настройка
  response.headers['Access-Control-Allow-Origin'] = '*'

  # проверка аутентификации (авторизации)
  auth! unless request.request_method == 'OPTIONS' || settings.development?
end

# обработка метода OPTIONS
options '/*' do
  response.headers['Access-Control-Allow-Methods'] = 'OPTIONS,GET,POST,DELETE'
  response.headers['Access-Control-Allow-Headers'] = 'X-USER-EMAIL,X-USER-TOKEN,X-Requested-With,Accept'

  status :ok
end

# редикерт на картинки
get '/' do
  redirect to('/images')
end

# вывести весь список картинок
get '/images' do
  images = Dir["#{settings.images_dir}/*/"].inject([]) do |res_acc, res_dir|
    resource = res_dir.split('/').last
    next res_acc unless settings.resources.include?(resource)

    res_acc + Dir["#{res_dir}/*/"].inject([]) do |id_acc, id_dir|
      id = id_dir.split('/').last.to_i
      next id_acc unless id.positive?

      sizes = Dir["#{id_dir}/*/"].map { |d| d.split('/').last }.select { |d| d.match(/^\d+x\d+$/) }
      files = Dir["#{id_dir}/#{IMAGES_MASK}"].map { |d| d.split('/').last }
      id_acc + files.map do |file|
        {
          resource: resource,
          resource_id: id,
          path: "#{settings.images_sub}/#{resource}/#{id}",
          filename: file,
          sizes: sizes.select { |size| File.file? "#{id_dir}/#{size}/#{file}" }
        }
      end
    end
  end
  json(images: images.sort_by { |image| image[:path] })
end

# список картинок/форма загрузки для сущности resource/id
get '/images/:resource/:id' do
  resource = params[:resource]
  id = params[:id].to_i
  raise AppError.new :not_acceptable, 'Неверный ресурс!' unless settings.resources.include?(resource) && id.positive?

  images_path = request.path_info
  images_dir = File.join(settings.images_dir, "/#{resource}/#{id}")

  sizes = Dir["#{images_dir}/*/"].map { |d| d.split('/').last }.select { |d| d.match(/^\d+x\d+$/) }
  files = Dir["#{images_dir}/#{IMAGES_MASK}"].map { |d| d.split('/').last }

  images = files.map do |file|
    {
      resource: resource,
      resource_id: id,
      path: images_path,
      filename: file,
      sizes: sizes.select { |size| File.file? "#{images_dir}/#{size}/#{file}" }
    }
  end
  # logger.info request.preferred_type.inspect
  # стандартный (для многих JS-фреймворков) ajax-запрос или заголовок accept пуст или предпочтение application/json
  if request.xhr? || request.accept.empty? || request.preferred_type.include?('application/json')
    # вывести в json формате
    json(images: images.sort_by { |image| image[:path] })
  else
    # вывести в html
    images_path = images_dir.gsub(settings.public_dir, '')
    # images = Dir["#{images_dir}/**/#{IMAGES_MASK}"].map { |f| f.gsub("#{images_dir}/", '') }.sort
    slim :upload, locals: { images_path: images_path, images: images }
  end
end

# обработка запроса загрузки кратинки
post '/images/:resource/:id' do
  resource = params[:resource]
  id = params[:id].to_i
  raise AppError.new :not_acceptable, 'Неверный ресурс!' unless settings.resources.include?(resource) && id.positive?

  raise AppError.new :unprocessable_entity, 'Файл не выбран!' unless params[:file]

  tempfile = params[:file][:tempfile].path
  filename = params[:file][:filename].gsub(IMAGES_REGEX, ".#{IMAGES_FORMAT}")

  target_dir = File.join(settings.images_dir, "/#{resource}/#{id}")
  FileUtils.mkdir_p(target_dir) unless File.exist?(target_dir)
  target_file = File.join(target_dir, "/#{filename}")

  image = MiniMagick::Image.open(tempfile)

  # raises exception MiniMagick::Invalid
  image.validate!

  # crops
  if params[:offsets]
    offsets = params[:offsets].scan(/[+-]\d+[+-]\d+/)
    offsets.each { |offset| image.crop offset }
  end
  # convert & save
  image.format IMAGES_FORMAT
  image.strip
  image.write target_file

  settings.images_sizes.split(',').each do |image_size|
    image = MiniMagick::Image.open(target_file) # should reload source image (cropped)

    processed_dir = File.join(target_dir, "/#{image_size}")
    processed_file = File.join(processed_dir, "/#{filename}")
    FileUtils.mkdir_p(processed_dir) unless File.exist?(processed_dir)

    # resize to fill
    image.combine_options do |opt|
      opt.resize "#{image_size}^"
      opt.gravity 'center'
      opt.extent image_size
    end
    # image.format IMAGES_FORMAT
    # save
    image.strip
    image.write processed_file
  end

  json message: 'Картинка успешно загружена!'
rescue MiniMagick::Invalid
  raise AppError.new :unprocessable_entity, 'Неизвестный формат файла!'
rescue Errno::EACCES
  raise AppError.new :service_unavailable, 'Ошибка доступа к хранилищу!'
end

# обработка запроса удаления всех кратинок ресурса
delete '/images/:resource/:id' do
  resource = params[:resource]
  id = params[:id].to_i
  raise AppError.new :not_acceptable, 'Неверный ресурс!' unless settings.resources.include?(resource) && id.positive?

  images_dir = File.join(settings.images_dir, "/#{resource}/#{id}")
  FileUtils.remove_dir(images_dir)

  json message: 'Все картинки успешно удалены!'
rescue Errno::ENOENT
  raise AppError.new :not_found, 'Картинки не найдены!'
rescue Errno::EACCES, Errno::ENOTEMPTY
  raise AppError.new :service_unavailable, 'Ошибка доступа к хранилищу!'
end

# обработка запроса удаления выбранной кратинки ресурса
delete '/images/:resource/:id/:filename' do
  resource = params[:resource]
  id = params[:id].to_i
  raise AppError.new :not_acceptable, 'Неверный ресурс!' unless settings.resources.include?(resource) && id.positive?

  filename = params[:filename]
  images_dir = File.join(settings.images_dir, "/#{resource}/#{id}")

  # удалить оригинал и все размеры
  files = Dir["#{images_dir}/**/#{filename}"].select { |file| File.file? file }
  raise AppError.new :not_found, 'Картинка не найдена!' if files.nil? || files.empty?

  files.each { |file| FileUtils.remove_file(file) }

  json message: 'Картинка успешно удалена!'
rescue Errno::EACCES
  raise AppError.new :service_unavailable, 'Ошибка доступа к хранилищу!'
end

# обработка ошибок
not_found do
  status :not_found
  json error: { message: 'Неверный запрос!' }
end

error do |error|
  status error.status if error.respond_to? :status
  json error: { message: error.message }
end

private

# проверить токен на главном бэкенде
def auth!
  email = request.env['HTTP_X_USER_EMAIL']
  token = request.env['HTTP_X_USER_TOKEN']
  raise AppError.new :unauthorized, 'Неверные данные авторизации!' unless email && token

  result = Faraday.get do |req|
    req.url "#{settings.back_host}/auth/check_in"
    req.headers['Accept'] = 'application/json'
    req.headers['X-USER-EMAIL'] = email
    req.headers['X-USER-TOKEN'] = token
  end
  raise AppError.new :unauthorized, 'Недействительный токен!' unless result&.success?

  user = JSON.parse(result.body, symbolize_names: true)[:user]
  raise AppError.new :unauthorized, 'Отсутствуют права доступа!' unless user && user[:role] == 'admin'

  result.status
rescue Faraday::ConnectionFailed
  raise AppError.new :service_unavailable, 'Ошибка соединения с сервером авторизации!'
end
