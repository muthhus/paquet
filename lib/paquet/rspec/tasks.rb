# encoding: utf-8
require "bundler"
require "rake"
require "rake/tasklib"
require "fileutils"
require "net/http"

#
# Uses bundler/fetcher to download stuff
module Paquet
  class Gem
    RUBYGEMS_URI = "https://rubygems.org/downloads"

    attr_reader :gems

    def initialize(target_path)
      @target_path = target_path
      @gems = []
    end

    def add(name)
      @gems << name
    end

    def pack
      FileUtils.rm_rf(@target_path)
      FileUtils.mkdir_p(@target_path)

      # need to get the current version and dependencies
      required_gems = collect_required_gems
      download_gems(required_gems)
    end

    def size
      @gems.size
    end

    private
    class Dependency
      attr_reader :name, :version, :platform

      def initialize(name, version, platform)
        @name = name
        @version = version
        @platform = platform
      end

      def to_s
        "#{name}-#{version}"
      end

      def ruby?
        platform == "ruby"
      end
    end

    def collect_required_gems()
      candidates = []
      @gems.each do |name|
        candidates += resolve_dependencies(name)
      end
      candidates.flatten
    end

    def resolve_dependencies(name)
      spec = ::Gem::Specification.find_by_name(name)
      current_dependency = Dependency.new(name, spec.version, spec.platform)
      dependencies = spec.dependencies.select { |dep| dep.type == :runtime }

      if dependencies.size == 0
        [current_dependency]
      else
        [dependencies.collect { |spec| resolve_dependencies(spec.name) }, current_dependency].flatten.uniq { |s| s.name }
      end
    end

    def download_gems(required_gems)
      required_gems.each do |gem|
        name = if gem.ruby?
                 "#{gem.name}-#{gem.version}.gem"
               else
                 "#{gem.name}-#{gem.version}-#{gem.platform}.gem"
               end

        source = "#{RUBYGEMS_URI}/#{name}"
        destination = File.join(@target_path, name)

        puts "Vendoring: #{gem}, downloading: #{source}"
        download_file(source, destination)
      end
    end

    def download_file(source, destination)
      f = File.open(destination, "w")

      begin
        uri = URI.parse(source)
        Net::HTTP.start(uri.host, uri.port) do |http|
          http.request_get(uri.path) do |response|
            response.read_body do |chunk|
              f.write(chunk)
            end
          end
        end
      ensure
        f.close
      end
    end
  end

  class Task < Rake::TaskLib
    def initialize(target_path, &block)
      @gem = Gem.new(target_path)

      instance_eval(&block)

      namespace :paquet do
        desc "Build a pack with #{@gem.size} gems: #{@gem.gems.join(",")}"
        task :vendor do
          @gem.pack
        end
      end
    end

    def pack(name)
      @gem.add(name)
    end
  end
end
