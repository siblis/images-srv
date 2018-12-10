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

# надеюсь меня за это не побьют палками, но ничего лучше не придумал :)
class AppError < StandardError
  attr_reader :status

  def initialize(status = :internal_server_error, message = nil)
    super message if message
    @status = status
  end
end

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
  Dir["#{settings.images_dir}/*/"].each do |resource_dir|
    resource = resource_dir.split('/').last
    next unless settings.resources.include?(resource)

    Dir["#{resource_dir}/*/"].each do |id_dir|
      id = id_dir.split('/').last.to_i
      next unless id.positive?

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
  raise AppError.new :not_acceptable, 'Неверный ресурс!' unless settings.resources.include?(params[:resource]) \
                                                                && params[:id].positive?

  images_dir = File.join(settings.images_dir, "/#{params[:resource]}/#{params[:id]}")
  images_path = images_dir.gsub(settings.public_dir, '')
  images = Dir["#{images_dir}/**/#{IMAGES_MASK}"].map { |f| f.gsub("#{images_dir}/", '') }.sort
  slim :upload, locals: { images_path: images_path, images: images }
end

# обработка загрузки
post '/images/:resource/:id/upload' do
  raise AppError.new :unprocessable_entity, 'Файл не выбран!' unless params[:file]

  tempfile = params[:file][:tempfile]
  filename = params[:file][:filename].gsub(IMAGES_REGEX, ".#{IMAGES_FORMAT}")
  raise AppError.new :not_acceptable, 'Неверный ресурс!' unless settings.resources.include?(params[:resource])

  target_dir = File.join(settings.images_dir, "/#{params[:resource]}/#{params[:id]}")
  FileUtils.mkdir_p(target_dir) unless File.exist?(target_dir)
  target_file = File.join(target_dir, "/#{filename}")

  image = MiniMagick::Image.open(tempfile.path)

  # raises exception: MiniMagick::Invalid
  image.validate!

  # convert & save with original size
  image.format IMAGES_FORMAT
  image.strip
  image.write target_file

  settings.images_sizes.split(',').each do |image_size|
    image = MiniMagick::Image.open(tempfile.path) # reload original image

    processed_dir = File.join(target_dir, "/#{image_size}")
    processed_file = File.join(processed_dir, "/#{filename}")
    FileUtils.mkdir_p(processed_dir) unless File.exist?(processed_dir)

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
    image.format IMAGES_FORMAT
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
  result = if email && token
             Faraday.get do |req|
               req.url "#{settings.back_host}/auth/check"
               req.headers['Content-Type'] = 'application/json'
               req.headers['X-USER-EMAIL'] = email
               req.headers['X-USER-TOKEN'] = token
             end
           end
  logger.info "result: #{result}"
  raise AppError.new :unauthorized, 'Недействительный токен и/или отсутствуют права доступа!' unless result&.success?

  # && user[:role] == 'admin'
  result.status
rescue Faraday::ConnectionFailed
  raise AppError.new :service_unavailable, 'Ошибка соединения с сервером авторизации!'
end
