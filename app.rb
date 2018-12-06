# app.rb
require 'rubygems'
require 'bundler/setup' # If you're using bundler, you will need to add this
require 'dotenv/load'
require 'sinatra'
require 'sinatra/json'
require 'fileutils'
require 'faraday'
#
require_relative 'config/app'
#
# include FileUtils::Verbose

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
  images_list = Dir.glob(settings.images_dir + '/**/*.{png,jpg,jpeg,gif,svg}').map { |f| f.gsub(settings.public_dir, '') }
  images_sub = settings.images_dir.gsub(settings.public_dir, '') + '/'
  images = images_list.map do |image_path|
    arr = image_path.gsub(images_sub, '').split('/')
    {
      resource: arr.size >=2 && arr[0].is_a?(String) && settings.resources.include?(arr[0]) ? arr[0] : nil,
      resource_id: arr.size >= 3 && arr[1].to_i > 0 ? arr[1].to_i : nil,
      image_path: image_path
    }
  end
  json images
end

# простенькая форма загрузки
get '/images/:resource/:id/upload' do
  erb :upload, locals: { action: "/images/#{params[:resource]}/#{params[:id]}/upload" }
end

# обработка загрузки
post '/images/:resource/:id/upload' do
  if params[:file]
    tempfile = params[:file][:tempfile] 
    filename = params[:file][:filename] 
    target_dir = File.join(settings.images_dir, "/#{params[:resource]}/#{params[:id]}") if settings.resources.include?(params[:resource])
    FileUtils.mkdir_p(target_dir) unless File.exists?(target_dir)
    target_file = File.join(target_dir, "/#{filename}")
    FileUtils.cp(tempfile.path, target_file)
    File.chmod(0644, target_file) # чтоб можно было выдавать картинки через nginx
    json message: 'Готово!'
  else
    json error: 'Файл не выбран!', status: :unprocessable_entity
  end
end

# проверяем токен на главном бэкенде
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
  user = JSON.parse(result.body, { symbolize_names: true })[:user] if result && result.success?
  # logger.info '#' * 80
  # logger.info user
  # logger.info '#' * 80
  halt 401, { error: 'Недействительный токен и/или отсутствуют права доступа.' }.to_json unless result && result.success? # && user[:role] == 'admin'
end
