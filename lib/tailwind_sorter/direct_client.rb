require 'json'
require 'open3'
require 'timeout'
require 'tmpdir'
require 'fileutils'
require 'logger'
require 'digest'

module TailwindSorter
  # A client that communicates with the Tailwind CSS language server directly via stdin/stdout
  class DirectClient
    TAILWIND_CONFIG_PATTERNS = [
      # Root directory configs
      'tailwind.config.js',
      'tailwind.config.cjs',
      'tailwind.config.mjs',
      'tailwind.config.ts',
      # Config directory configs
      'config/tailwind.config.js',
      'config/tailwind.config.cjs',
      'config/tailwind.config.mjs',
      'config/tailwind.config.ts'
    ]

    CSS_FILE_PATTERNS = [
      'styles.css',
      'app/assets/stylesheets/application.tailwind.css', # Rails default
      'src/styles.css',  # Common frontend location
      'assets/css/styles.css'  # Another common location
    ]

    DEFAULT_CONFIG = <<~JS
      module.exports = {
        content: ['*.html'],
        theme: {
          extend: {},
        },
        plugins: [],
      }
    JS

    DEFAULT_CSS = <<~CSS
      @tailwind base;
      @tailwind components;
      @tailwind utilities;
    CSS

    def initialize(options = {})
      @server_path = find_server_path
      @request_id = 0
      @stdin = nil
      @stdout = nil
      @stderr = nil
      @wait_thread = nil
      @debug = options[:debug]
      @temp_dir = nil
      @logger = Logger.new($stderr)
      @logger.level = @debug ? Logger::DEBUG : Logger::WARN

      # Cache for config file state
      @config_cache = {
        mtime: nil,
        content: nil,
        path: nil
      }

      # Cache for sorted class strings
      @sort_cache = {}
      @sort_cache_time = {}
      @sort_cache_expires = options.fetch(:cache_expires, 5) # 5 second default

      # First find a project by detecting config files
      @project_root = find_project_root
      if @project_root
        @logger.debug("Found project root at: #{@project_root}")
        @config_path = find_tailwind_config
        @css_path = find_css_file if @config_path
      end

      @logger.debug("Initialized with:")
      @logger.debug("  Project Root: #{@project_root}")
      @logger.debug("  Config Path: #{@config_path}")
      @logger.debug("  CSS Path: #{@css_path}")
    end

    def start
      return if running?

      @logger.debug("Starting server...")

      # Create temporary directory if we don't have one, using unique name
      @temp_dir ||= Dir.mktmpdir(generate_temp_dir_name)
      @logger.debug("Created temp directory at: #{@temp_dir}")

      # Always ensure our virtual HTML file exists
      html_path = File.join(@temp_dir, "virtual.html")
      File.write(html_path, "<div><!-- virtual document for processing tailwind classes --></div>") unless File.exist?(html_path)

      if @project_root
        # Check if config has changed
        current_mtime = File.mtime(@config_path)
        if @config_cache[:path] != @config_path || @config_cache[:mtime] != current_mtime
          @logger.debug("Config file changed or new, copying to workspace")

          # Copy the project's config to our temp dir
          temp_config_path = File.join(@temp_dir, File.basename(@config_path))
          FileUtils.cp(@config_path, temp_config_path)

          # Update cache
          @config_cache = {
            mtime: current_mtime,
            content: File.read(@config_path),
            path: @config_path
          }

          # If we have a CSS file, copy it too (only needs to happen once)
          if @css_path && !File.exist?(File.join(@temp_dir, File.basename(@css_path)))
            temp_css_path = File.join(@temp_dir, File.basename(@css_path))
            FileUtils.cp(@css_path, temp_css_path)
            @css_path = temp_css_path
          end

          # Use the temp copy of the config
          @config_path = temp_config_path

          # Clear sort cache since config changed
          @sort_cache.clear
          @sort_cache_time.clear
        end
      else
        # No project found, create temporary config if needed
        unless File.exist?(File.join(@temp_dir, "tailwind.config.js"))
          @config_path = File.join(@temp_dir, "tailwind.config.js")
          File.write(@config_path, DEFAULT_CONFIG)
          @css_path = File.join(@temp_dir, "styles.css")
          File.write(@css_path, DEFAULT_CSS)
        end
      end

      # Only start the server if it's not running
      unless running?
        # Start the language server process
        @stdin, @stdout, @stderr, @wait_thread = Open3.popen3("#{@server_path} --stdio")

        # Initialize with our temp directory as root for a consistent workspace
        root_uri = "file://#{@temp_dir}"

        request_sync('initialize', {
          processId: Process.pid,
          clientInfo: {
            name: 'tailwind_sorter',
            version: '0.1.0'
          },
          rootUri: root_uri,
          workspaceFolders: [
            {
              uri: root_uri,
              name: "tailwind_sorter"
            }
          ],
          capabilities: {
            textDocument: {
              synchronization: {
                didOpen: true,
                didChange: true
              }
            },
            workspace: {
              configuration: true
            }
          }
        })

        # Send initialized notification
        send_notification('initialized', {})

        # Configure the Tailwind workspace
        send_notification('workspace/didChangeConfiguration', {
          settings: {
            tailwindCSS: {
              experimental: { classRegex: [] },
              validate: true
            }
          }
        })

        # Open the config file first - this is crucial for project detection
        send_notification('textDocument/didOpen', {
          textDocument: {
            uri: "file://#{@config_path}",
            languageId: "javascript",
            version: 1,
            text: File.read(@config_path)
          }
        })

        # Open CSS file if we have one
        if @css_path
          send_notification('textDocument/didOpen', {
            textDocument: {
              uri: "file://#{@css_path}",
              languageId: "css",
              version: 1,
              text: File.read(@css_path)
            }
          })
        end

        # Open our virtual HTML document
        send_notification('textDocument/didOpen', {
          textDocument: {
            uri: "file://#{html_path}",
            languageId: "html",
            version: 1,
            text: File.read(html_path)
          }
        })

        # Handle any initial configuration requests
        handle_pending_messages
      end
    end

    def stop
      return unless running?

      # Close our HTML document
      html_path = File.join(@temp_dir, "virtual.html")
      send_notification('textDocument/didClose', {
        textDocument: {
          uri: "file://#{html_path}"
        }
      })

      send_notification('exit', {})
      @stdin&.close
      @stdout&.close
      @stderr&.close
      @wait_thread&.kill
      @stdin = @stdout = @stderr = @wait_thread = nil

      # Don't clean up temp directory anymore - we'll reuse it
    end

    def sort_classes(classes)
      # Check cache first
      cache_key = Digest::MD5.hexdigest(classes)
      if @sort_cache.key?(cache_key)
        cache_time = @sort_cache_time[cache_key]
        if Time.now - cache_time < @sort_cache_expires
          @logger.debug("Cache hit for classes: #{classes}")
          return @sort_cache[cache_key]
        else
          # Cache expired
          @sort_cache.delete(cache_key)
          @sort_cache_time.delete(cache_key)
        end
      end

      start unless running?

      # Get path to our virtual HTML document
      html_path = File.join(@temp_dir, "virtual.html")

      # Update the virtual document with the classes to sort
      document_text = "<div class=\"#{classes}\"><!-- virtual document for processing tailwind classes --></div>"

      # Send the updated content to the Language Server
      send_notification('textDocument/didChange', {
        textDocument: {
          uri: "file://#{html_path}",
          version: 2
        },
        contentChanges: [
          {
            text: document_text
          }
        ]
      })

      # Sort the classes using the Language Server
      response = request_sync('@/tailwindCSS/sortSelection', {
        uri: "file://#{html_path}",
        classLists: [classes]
      })

      if response && error_message = response.dig("result", "error")
        raise Error, "Error sorting classes: #{error_message}"
      end

      result = response.dig("result", "classLists", 0) || classes

      # Normalize spaces: trim whitespace and ensure single spaces between classes
      result = result.strip.gsub(/\s+/, ' ')

      # Cache the result
      @sort_cache[cache_key] = result
      @sort_cache_time[cache_key] = Time.now

      result = "debug-sorting #{result}" if @debug
      result
    end

    def get_project
      start unless running?

      response = request_sync('@/tailwindCSS/getProject', {
        uri: "file://#{@config_path}"
      })

      if response && error_message = response.dig("result", "error")
        raise Error, "Error finding project: #{error_message}"
      end

      result = response.dig("result")
      result.nil? ? "No project found" : result
    end

    def running?
      @stdin && !@stdin.closed? &&
      @stdout && !@stdout.closed? &&
      @stderr && !@stderr.closed? &&
      @wait_thread && @wait_thread.alive?
    end

    private

    def find_project_root
      # Start from current directory and work up
      current_dir = Dir.pwd

      while current_dir != '/'
        TAILWIND_CONFIG_PATTERNS.each do |pattern|
          path = File.join(current_dir, pattern)
          if File.exist?(path)
            @logger.debug("Found config at #{path}, using project root: #{current_dir}")
            return current_dir
          end
        end

        # Move up one directory
        current_dir = File.dirname(current_dir)
      end

      @logger.debug("No project root found, will use temporary directory")
      nil
    end

    def find_tailwind_config
      return nil unless @project_root

      # Try each pattern in order - first match wins
      TAILWIND_CONFIG_PATTERNS.each do |pattern|
        path = File.join(@project_root, pattern)
        if File.exist?(path)
          @logger.debug("Found config at: #{path}")
          return path
        end
      end

      @logger.debug("No config file found in #{@project_root}")
      nil
    end

    def find_css_file
      return nil unless @project_root

      CSS_FILE_PATTERNS.each do |pattern|
        path = File.join(@project_root, pattern)
        if File.exist?(path)
          @logger.debug("Using CSS file: #{path}")
          return path
        end
      end

      @logger.debug("No CSS file found in #{@project_root}")
      nil
    end

    def request_sync(method, params, timeout_seconds = 5)
      request_id = @request_id += 1

      request = {
        jsonrpc: "2.0",
        id: request_id,
        method: method,
        params: params
      }

      @logger.debug("Sending request: #{request}")
      send_message(request)

      # Wait for and handle responses until we get the one for our request
      start_time = Time.now

      while Time.now - start_time < timeout_seconds
        response = read_message
        @logger.debug("Received response: #{response}")

        # If it's our response, return it
        if response["id"] == request_id
          return response
        end

        # Handle any server requests that come in while we're waiting
        handle_server_request(response) if response["method"]
      end

      raise Error, "Request timed out after #{timeout_seconds} seconds"
    end

    def send_notification(method, params)
      notification = {
        jsonrpc: "2.0",
        method: method,
        params: params
      }

      send_message(notification)
    end

    def send_message(message)
      json = JSON.generate(message)
      headers = "Content-Length: #{json.bytesize}\r\n\r\n"
      @stdin.write(headers + json)
      @stdin.flush
    end

    def read_message
      # Read headers
      headers = {}
      begin
        while line = Timeout.timeout(5) { @stdout.gets("\r\n") }
          line = line.strip
          break if line.empty?

          key, value = line.split(': ', 2)
          headers[key] = value
        end

        if !headers["Content-Length"]
          @logger.error("No Content-Length header received from server")
          raise Error, "Invalid response from language server: missing Content-Length header"
        end

        content_length = headers["Content-Length"].to_i

        # Read exactly content_length bytes to avoid waiting indefinitely
        content = ""
        bytes_read = 0
        while bytes_read < content_length
          chunk = Timeout.timeout(5) { @stdout.read(content_length - bytes_read) }
          if chunk.nil? || chunk.empty?
            # This indicates the server closed the connection or sent incomplete data
            @logger.error("Server sent incomplete response (got #{bytes_read} of #{content_length} bytes)")
            raise Error, "Server sent incomplete response. This might be caused by an issue with the Tailwind language server."
          end
          content += chunk
          bytes_read += chunk.bytesize
        end

        content.force_encoding('UTF-8')

        begin
          return JSON.parse(content)
        rescue JSON::ParserError => e
          @logger.error("JSON parse error: #{e.message}")
          @logger.error("Content received (#{content.bytesize} bytes): #{content.inspect}")
          raise Error, "Failed to parse server response: #{e.message}. Try restarting the Tailwind language server."
        end
      rescue Timeout::Error
        @logger.error("Timeout while reading from server")
        raise Error, "Timeout while reading from Tailwind language server. The server might be busy or unresponsive."
      rescue IOError, Errno::EPIPE => e
        @logger.error("IO error: #{e.message}")
        raise Error, "Connection to Tailwind language server lost: #{e.message}. Try restarting the application."
      end
    end

    def handle_pending_messages(timeout = 0.5)
      begin
        Timeout.timeout(timeout) do
          while true
            message = read_message
            handle_server_request(message)
          end
        end
      rescue Timeout::Error
        # Expected - there are no more pending messages
      end
    end

    def handle_server_request(message)
      # Only handle server requests, not responses
      return unless message["method"]

      case message["method"]
      when "workspace/configuration"
        section = message.dig("params", "items", 0, "section")

        result = if section == "tailwindCSS"
          [{
            experimental: { classRegex: [] },
            includeLanguages: {},
            validate: true
          }]
        else
          [{ tabSize: 4, insertSpaces: true }]
        end

        response = {
          jsonrpc: "2.0",
          id: message["id"],
          result: result
        }

        send_message(response)
      end
    end

    def find_server_path
      paths = [
        # Local node_modules path (relative to the gem)
        File.join(File.expand_path('../../..', __FILE__), 'node_modules', '.bin', 'tailwindcss-language-server'),
        # Project node_modules (if any)
        @project_root ? File.join(@project_root, 'node_modules', '.bin', 'tailwindcss-language-server') : nil,
        # Global yarn/npm installation
        `which tailwindcss-language-server 2>/dev/null`.strip,
        # Try npx as a fallback
        'npx tailwindcss-language-server'
      ].compact

      # Check each path
      path = paths.find do |p|
        if p.start_with?('npx ')
          # For npx, just check if npx is available
          system('which npx > /dev/null 2>&1')
        else
          !p.empty? && File.exist?(p) && File.executable?(p)
        end
      end

      # If no path found, try to auto-install dependencies
      if !path
        @logger.info("Tailwind CSS language server not found, attempting auto-installation...")
        if auto_install_dependencies
          # Re-check paths after installation
          path = paths.find do |p|
            next if p.start_with?('npx ') # Skip npx now that we've installed locally
            !p.empty? && File.exist?(p) && File.executable?(p)
          end
        end
      end

      unless path
        error_message = <<~ERROR
          Tailwind CSS language server not found. You can install it with any of these methods:

          # Option 1: Use the helper method in your code:
          require 'tailwind_sorter'
          TailwindSorter.setup_dependencies

          # Option 2: Run the setup script directly:
          cd #{File.expand_path('../../..', __FILE__)} && bin/setup

          # Option 3: Install the npm packages manually:
          yarn add @tailwindcss/language-server@^0.14.8 tailwindcss

          # If using npm instead of yarn:
          npm install @tailwindcss/language-server@^0.14.8 tailwindcss

          IMPORTANT: You MUST use version 0.14.8 or higher of the language server.

          You might need to restart your application after installation.
        ERROR

        @logger.error(error_message)
        raise Error, error_message
      end

      # If using npx, just return the command
      return path if path.start_with?('npx ')

      # Check if the server is executable
      unless File.executable?(path)
        @logger.error("Found server at #{path} but it is not executable")
        raise Error, "Found Tailwind CSS language server at #{path} but it is not executable. Try: chmod +x #{path}"
      end

      # Check if the server is the correct version
      check_server_version(path)

      path
    end

    # Check if the server meets the minimum version requirement
    def check_server_version(server_path)
      begin
        # Extract just the server command without any path or arguments
        server_cmd = if server_path.start_with?('npx ')
          'npx tailwindcss-language-server'
        else
          server_path
        end

        # Run the server with --version
        version_output = `#{server_cmd} --version 2>&1`.strip
        @logger.debug("Server version output: #{version_output}")

        # Parse the version
        if version_output =~ /(\d+)\.(\d+)\.(\d+)/
          major = $1.to_i
          minor = $2.to_i
          patch = $3.to_i

          # Check if version is less than 0.14.8
          if major < 0 || (major == 0 && minor < 14) || (major == 0 && minor == 14 && patch < 8)
            @logger.warn("Tailwind CSS language server version #{version_output} is less than required version 0.14.8")
            @logger.warn("Some features may not work properly. Consider upgrading with: yarn add @tailwindcss/language-server@^0.14.8")
          else
            @logger.debug("Tailwind CSS language server version #{version_output} is OK")
          end
        else
          @logger.warn("Could not determine Tailwind CSS language server version from: #{version_output}")
        end
      rescue => e
        # Don't fail on version check error, just warn
        @logger.warn("Failed to check Tailwind CSS language server version: #{e.message}")
      end
    end

    # Attempt to automatically install dependencies
    def auto_install_dependencies
      gem_root = File.expand_path('../../..', __FILE__)
      package_json_path = File.join(gem_root, 'package.json')

      return false unless File.exist?(package_json_path)

      @logger.info("Installing JavaScript dependencies...")

      # Determine which package manager to use
      package_manager = if system('which yarn > /dev/null 2>&1')
        'yarn'
      elsif system('which npm > /dev/null 2>&1')
        'npm'
      else
        @logger.error("Neither yarn nor npm found.")
        return false
      end

      # Run installation
      Dir.chdir(gem_root) do
        cmd = "#{package_manager} install"
        @logger.info("Running: #{cmd}")
        result = system(cmd)

        unless result
          @logger.error("Failed to install JavaScript dependencies.")
          return false
        end

        # Make executable if needed
        server_path = File.join(gem_root, 'node_modules', '.bin', 'tailwindcss-language-server')
        if File.exist?(server_path) && !File.executable?(server_path)
          File.chmod(0755, server_path)
        end

        @logger.info("Successfully installed JavaScript dependencies.")
        return true
      end
    rescue => e
      @logger.error("Error during dependency installation: #{e.message}")
      return false
    end

    # only being called in one test right now.
    def cleanup
      # Clean up temp directory when explicitly requested
      if @temp_dir && Dir.exist?(@temp_dir)
        stop if running?
        FileUtils.remove_entry(@temp_dir)
        @temp_dir = nil
      end

      # Clear caches
      @sort_cache.clear
      @sort_cache_time.clear
      @config_cache = {
        mtime: nil,
        content: nil,
        path: nil
      }
    end

    def generate_temp_dir_name
      # Create a unique hash based on project path and config content
      components = []

      if @project_root
        # Use last two parts of the project path to help identify in temp dir
        path_parts = @project_root.split(File::SEPARATOR).last(2)
        components << path_parts.join('-')
      end

      if @config_path && File.exist?(@config_path)
        # Add hash of config content for uniqueness
        config_content = File.read(@config_path)
        config_hash = Digest::MD5.hexdigest(config_content)[0..7]
        components << config_hash
      end

      # Add a timestamp for complete uniqueness
      components << Time.now.to_i.to_s

      # Join all components
      "tailwind_sorter-#{components.join('-')}"
    end
  end
end
