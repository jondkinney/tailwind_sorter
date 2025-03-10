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

      # Create temporary directory if we don't have one
      @temp_dir ||= Dir.mktmpdir("tailwind_sorter")

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
      while line = @stdout.gets("\r\n")
        line = line.strip
        break if line.empty?

        key, value = line.split(': ', 2)
        headers[key] = value
      end

      content_length = headers["Content-Length"].to_i
      content = @stdout.read(content_length).force_encoding('UTF-8')

      JSON.parse(content)
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
        # Local node_modules path
        File.join(File.expand_path('../../..', __FILE__), 'node_modules', '.bin', 'tailwindcss-language-server'),
        # Global yarn/npm installation
        `which tailwindcss-language-server`.strip
      ]

      path = paths.find { |p| !p.empty? && File.exist?(p) && File.executable?(p) }
      raise Error, "Tailwind CSS language server not found. Please install it with: bin/setup" unless path

      path
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
  end
end
