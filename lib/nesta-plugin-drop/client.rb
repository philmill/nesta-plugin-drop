require 'fileutils'
require 'rest_client'
require 'yajl'
module Nesta
  module Plugin
    module Drop
      class Client
        def self.host(key = nil)
          if key
            "https://#{key}:@api.nestadrop.io"
          else
            "https://api.nestadrop.io"
          end
        end

        def self.confirm_linked!
          return true if File.exists?("/tmp/.nestadropped")
          File.open("/tmp/.nestadropped", "w+") do |f|
            f.write "linked"
          end
        end

        def self.nestadrop_configured?
          return true if File.exists?("/tmp/.nestadropped")
          false
        end

        def self.bounce_server!
          puts "Restarting server..."
          ppid = Process.ppid
          Process.kill("HUP", ppid)
        end

        def self.files
          files = RestClient.get "#{host(ENV["NDROP_KEY"])}/files", { accept: :json }
          Yajl::Parser.parse files
        rescue RestClient::Unauthorized
          return []
        end

        def self.cache_file(file)
          confirm_linked!
          local_path = [Nesta::App.root, file].join("/")
          puts "Caching: #{local_path}"
          FileUtils.mkdir_p(File.dirname(local_path))
          file_contents = open("#{host}/file?file=#{URI.encode(file)}",
            http_basic_authentication: [ENV["NDROP_KEY"], ""]).read
          File.open(local_path, 'w') do |fo|
            fo.write file_contents
          end
          bounce_server!
        rescue OpenURI::HTTPError => ex
          puts ex
        rescue RuntimeError => ex
          puts ex
        end

        def self.cache_files
          threads = []
          filenames = Client.files
          return unless filenames.size > 0
          slice_size = filenames.size/3
          puts "Slice size is: #{slice_size}"
          filenames.each_slice(slice_size).each do |slice|
            threads << Thread.new do
              slice.each do |file, status|
                cache_file(file)
              end
            end
          end
          threads.each(&:join)
        end

        def self.remove_file(file)
          local_path = [Nesta::App.root, file].join("/")
          FileUtils.rm_r(File.dirname(local_path), secure: true)
          bounce_server!
        end

        def self.bootstrap!
          unless nestadrop_configured?
            cache_files
          end
        end
      end
    end
  end
end