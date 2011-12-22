require 'rubygems'
require 'oauth'
require 'json'
require 'sqlite3'
require 'active_support/core_ext/object/blank'

# Get your key here. http://www.instapaper.com/main/request_oauth_consumer_token
required_params = %w(INSTAPAPER_CONSUMER_KEY INSTAPAPER_CONSUMER_SECRET INSTAPAPER_USERNAME INSTAPAPER_PASSWORD KINDLEGEN)

class Instapaper
  Url = "http://www.instapaper.com"

  def initialize(consumer_key, consumer_secret)
    @consumer_key    = consumer_key
    @consumer_secret = consumer_secret
  end

  def authorize(username, password)
    @consumer = OAuth::Consumer.new(@consumer_key, @consumer_secret, {
        :site              => "https://www.instapaper.com",
        :access_token_path => "/api/1/oauth/access_token",
        :http_method => :post
      })

    access_token = @consumer.get_access_token(nil, {}, {
        :x_auth_username => username,
        :x_auth_password => password,
        :x_auth_mode     => "client_auth",
      })

    @access_token = OAuth::AccessToken.new(@consumer, access_token.token, access_token.secret)
  end

  def request(path, params={})
    @access_token.request(:post, "#{Url}#{path}", params)
  end
end

required_params.each do |key|
  raise "must have #{key} in your environment variables to use" if ENV[key].blank?
end

$instapaper = Instapaper.new(ENV['INSTAPAPER_CONSUMER_KEY'], ENV['INSTAPAPER_CONSUMER_SECRET'])
$instapaper.authorize(ENV['INSTAPAPER_USERNAME'], ENV['INSTAPAPER_PASSWORD'])


$db = SQLite3::Database.new('i2ksync.db')
$db.results_as_hash = true

# status 1. download, 2. still_there 3. archived
$db.execute(%{
   create table if not exists bookmarks (
                id integer PRIMARY KEY,
                title text,
                status text,
                UNIQUE(id))
})

# Create the path if it doesn't exist
path = File.join("/Volumes/Kindle/documents", "_instapaper")
Dir.mkdir(path) unless File.exists?(path)

num_not_there = 0
still_there_ids = []

still_there = $db.execute("select * from bookmarks where status = 2")
still_there.each do |bookmark|
  unless File.exists?(File.join(path, "#{bookmark['title']}.mobi"))
    $instapaper.request("/api/1/bookmarks/archive?bookmark_id=#{bookmark['id']}")
    $db.execute("update bookmarks set status = 3 where id = #{bookmark['id']}")

    num_not_there += 1
  else
    still_there_ids << bookmark['id']
  end
end

articles = JSON.parse($instapaper.request("/api/1/bookmarks/list?limit=#{25 - num_not_there}&have=#{still_there_ids.join(',')}").body)

puts "found #{articles.length}"
#puts "found details: #{articles.inspect}"

articles.each do |article|
  next unless article.has_key?('title')

  filename = article['title']
  filename = "Article #{article['bookmark_id']}" unless article['title']

  file_path = "#{filename}.html"

  File.open(File.join(path, file_path.gsub('/','_')), 'w') do |f|
    f << $instapaper.request("/api/1/bookmarks/get_text?bookmark_id=#{article['bookmark_id']}").body
  end

  $db.execute("insert or ignore into bookmarks (id, title, status) values (?,?,?)", article['bookmark_id'], filename, 2)
end

#puts "cd #{path} && find . -name \"*html\" -exec #{ENV['KINDLEGEN']} {} \\;"
`cd #{path} && find . -name "*html" -exec #{ENV['KINDLEGEN']} {} \\;`

#remove old files
`cd #{path} && find . -name "*html" -exec rm {} \\;`
