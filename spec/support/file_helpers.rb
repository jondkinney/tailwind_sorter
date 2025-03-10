module FileHelpers
  def cleanup_test_files(*paths)
    paths.each do |path|
      next unless path
      begin
        if File.directory?(path)
          FileUtils.rm_rf(path)
        else
          FileUtils.rm_f(path)
          # Also clean up parent directories if they're empty
          dir = File.dirname(path)
          while dir != "." && dir != "/" && Dir.exist?(dir)
            begin
              Dir.rmdir(dir)
              dir = File.dirname(dir)
            rescue Errno::ENOTEMPTY, Errno::ENOENT, Errno::EACCES
              break
            end
          end
        end
      rescue Errno::ENOENT, Errno::EACCES => e
        # Ignore errors from files that don't exist or can't be accessed
      end
    end
  end
end