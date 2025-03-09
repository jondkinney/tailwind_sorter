require 'spec_helper'
require 'tailwind_sorter/server_manager'

RSpec.describe TailwindSorter::ServerManager do
  let(:server_manager) { described_class.new }
  let(:server_path) { '/path/to/mock/tailwindcss-language-server' } # Use a consistent path

  # These tests are structured to avoid actually starting the server
  describe '#initialize' do
    before do
      allow(server_manager).to receive(:find_server_path).and_return(server_path)
    end

    it 'tries to find the server path' do
      expect(server_manager).to receive(:find_server_path)
      server_manager.send(:initialize)
    end
  end

  describe '#running?' do
    it 'returns false if pid is nil' do
      allow(server_manager).to receive(:pid).and_return(nil)
      expect(server_manager.running?).to be false
    end
  end

  context 'with mocked process management' do
    before do
      allow(server_manager).to receive(:find_server_path).and_return(server_path)
      allow(Open3).to receive(:popen3).and_return([
        double('stdin'),
        double('stdout'),
        double('stderr', read: ''),
        double('wait_thread', pid: 12345)
      ])
      allow(Process).to receive(:kill)
    end

    describe '#start' do
      it 'starts the server process' do
        allow(server_manager).to receive(:running?).and_return(false, true)
        expect(Open3).to receive(:popen3).with("#{server_path} --stdio")
        server_manager.start
      end

      it 'does nothing if the server is already running' do
        allow(server_manager).to receive(:running?).and_return(true)
        expect(Open3).not_to receive(:popen3)
        server_manager.start
      end
    end

    describe '#stop' do
      it 'stops the server if it is running' do
        # Set the pid directly on the instance variable
        server_manager.instance_variable_set(:@pid, 12345)
        allow(server_manager).to receive(:running?).and_return(true)
        expect(Process).to receive(:kill).with('TERM', 12345)
        server_manager.stop
      end

      it 'does nothing if the server is not running' do
        allow(server_manager).to receive(:running?).and_return(false)
        expect(Process).not_to receive(:kill)
        server_manager.stop
      end
    end
  end
end
