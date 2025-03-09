require "tailwind_sorter/version"
require "tailwind_sorter/server_manager"
require "tailwind_sorter/direct_client"

module TailwindSorter
  class Error < StandardError; end

  @server_manager = nil
  @direct_client = nil
  @use_direct_client = true  # Set to true to use the direct client by default
  @debug = false

  class << self
    attr_accessor :debug
  end

  # Ensure the Tailwind language server is running
  # @return [Boolean] true if server was started or was already running
  def self.ensure_server_running
    @server_manager ||= ServerManager.new
    @server_manager.start unless @server_manager.running?
    true
  end

  # Explicitly stop the server if it was started by this process
  def self.stop_server
    @server_manager&.stop
  end

  # Sort tailwind classes using the language server
  # @param classes [String] Space-separated tailwind classes
  # @return [String] Sorted tailwind classes
  def self.sort(classes)
    # Use direct stdin/stdout client
    @direct_client ||= DirectClient.new(debug: @debug)
    return @direct_client.sort_classes(classes)
  end

  def self.get_project
    # Use direct stdin/stdout client
    @direct_client ||= DirectClient.new(debug: @debug)
    return @direct_client.get_project
  end

  # Enable or disable auto-starting the server
  # @param value [Boolean] Whether to auto-start the server
  def self.auto_start=(value)
    @auto_start = value
  end

  # Get the current auto-start setting
  # @return [Boolean] Whether auto-start is enabled
  def self.auto_start
    @auto_start.nil? ? true : @auto_start
  end

  # Enable or disable direct client mode
  # @param value [Boolean] Whether to use the direct client
  def self.use_direct_client=(value)
    @use_direct_client = value
  end

  # Get the current direct client setting
  # @return [Boolean] Whether direct client is enabled
  def self.use_direct_client
    @use_direct_client
  end

  # Set auto-start to true by default
  self.auto_start = true
end
