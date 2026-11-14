# frozen_string_literal: true

return if ENV["DISABLE_SIMPLECOV"] == "true"

begin
  require "simplecov"
rescue LoadError
  return
end

return if SimpleCov.running

gem_root = File.expand_path("..", __dir__)

SimpleCov.start do
  enable_coverage :branch
  command_name ENV.fetch("SIMPLECOV_COMMAND_NAME", "gem")
  root gem_root
  coverage_dir File.join(gem_root, "coverage")
  merge_timeout 7200
  # Count every engine file, including ones a single process never loads.
  # Gem and dummy runs merge into this directory under separate command names.
  track_files "{app,lib}/**/*.rb"

  add_filter do |source|
    relative = source.filename.to_s.delete_prefix("#{gem_root}/")
    !(relative.start_with?("app/") || relative.start_with?("lib/"))
  end
end
