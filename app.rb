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

# проверка аутентификации (авторизации)
before do
  # без origin никак, нужна настройка
  response.headers["Access-Control-Allow-Origin"] = '*'

  auth! unless settings.development?
end

# обработка метода OPTIONS
options '/*' do
  response.headers["Access-Control-Allow-Methods"] = "OPTIONS,GET,HEAD,POST"
  response.headers["Access-Control-Allow-Headers"] = "X-USER-EMAIL,X-USER-TOKEN,Accept"

  status :ok
end

# редикерт на картинки
get '/' do
  redirect to('/images')
end

# вывести весь список картинок
get '/images' do
  logger.info request.env.inspect
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
          sizes: sizes.select { |size| File.file? "#{id_dir}/#{size}/#{file}" },
          path: "#{settings.images_sub}/#{resource}/#{id}/#{file}"
        }
      end
    end
  end
  json(images: images.sort_by { |image| image[:path] })
end

# список картинок/форма загрузки для resource/id
get '/images/:resource/:id' do
  logger.info request.env.inspect
  resource, id = params[:resource], params[:id].to_i
  raise AppError.new :not_acceptable, 'Неверный ресурс!' unless settings.resources.include?(resource) \
                                                                && id.positive?

  images_dir = File.join(settings.images_dir, "/#{resource}/#{id}")
  accepts = request.env['HTTP_ACCEPT'].split(/\s*,\s*/)
  if accepts.any? { |accept| accept =~ /\/json/ }
    # вывести в json формате
    sizes = Dir["#{images_dir}/*/"].map { |d| d.split('/').last }.select { |d| d.match(/^\d+x\d+$/) }
    files = Dir["#{images_dir}/#{IMAGES_MASK}"].map { |d| d.split('/').last }
    images = files.map do |file|
      {
        resource: resource,
        resource_id: id,
        sizes: sizes.select { |size| File.file? "#{images_dir}/#{size}/#{file}" },
        path: "#{settings.images_sub}/#{resource}/#{id}/#{file}"
      }
    end
    json(images: images.sort_by { |image| image[:path] })
  else
    # вывести в html
    images_path = images_dir.gsub(settings.public_dir, '')
    images = Dir["#{images_dir}/**/#{IMAGES_MASK}"].map { |f| f.gsub("#{images_dir}/", '') }.sort
    slim :upload, locals: { images_path: images_path, images: images }
  end
end

# обработка загрузки
post '/images/:resource/:id/upload' do
  raise AppError.new :unprocessable_entity, 'Файл не выбран!' unless params[:file]

  tempfile = params[:file][:tempfile].path
  filename = params[:file][:filename].gsub(IMAGES_REGEX, ".#{IMAGES_FORMAT}")
  raise AppError.new :not_acceptable, 'Неверный ресурс!' unless settings.resources.include?(params[:resource])

  target_dir = File.join(settings.images_dir, "/#{params[:resource]}/#{params[:id]}")
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

  json message: 'Готово!'
rescue MiniMagick::Invalid
  raise AppError.new :unprocessable_entity, 'Неизвестный формат файла!'
rescue Errno::EACCES
  raise AppError.new :service_unavailable, 'Ошибка доступа к хранилищу!'
end

not_found do
  status :not_found
  json error: { message: 'Неверный запрос!' }
end

error do |error|
  logger.info error.inspect
  status error.status if error.respond_to? :status
  json error: { message: error.message }
end

# проверить токен на главном бэкенде
def auth!
  email = request.env['HTTP_X_USER_EMAIL']
  token = request.env['HTTP_X_USER_TOKEN']
  raise AppError.new :unauthorized, 'Неверные данные авторизации!' unless email && token

  result = Faraday.get do |req|
    req.url "#{settings.back_host}/auth/check"
    req.headers['Accept'] = 'application/json'
    req.headers['X-USER-EMAIL'] = email
    req.headers['X-USER-TOKEN'] = token
  end
  raise AppError.new :unauthorized, 'Недействительный токен!' unless result&.success?

  # user = JSON.parse(result.body, symbolize_names: true)[:user]
  # raise AppError.new :unauthorized, 'Отсутствуют права доступа!' unless user && user[:role] == 'admin'

  result.status
rescue Faraday::ConnectionFailed
  raise AppError.new :service_unavailable, 'Ошибка соединения с сервером авторизации!'
end
