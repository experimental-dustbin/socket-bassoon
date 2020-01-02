#!/usr/bin/env ruby
require 'yaml/store'
require 'socket'
require 'base64'

# Helper function/lambda for "(de)serializing" client commands.
deserialize = ->(value) { Base64.decode64(value) }
serialize = ->(value) { Base64.encode64(value) }
# Our key/value store is backed by a YAML file.
store = YAML::Store.new('/tmp/store.yaml')
# Hardcoded socket path for convenience.
UNIXServer.open('/tmp/store') do |server|
  # Start the server loop.
  loop do
    # Get the client connection.
    client = server.accept
    # Deserialize the command so we can figure out what the client wants.
    command = deserialize[client.readline]
    # Start making sense of the command.
    case command
    when /^store:/ # Client wants us to store a value.
      # Find the point that delimits the key from the value.
      key_start = 6
      key_end = command.index(/[^\\]:/, key_start)
      key, value = command[key_start..key_end], command[(key_end + 2)..-1]
      # Unescape ':' in the value before storing it.
      value.gsub!('\:', ':')
      # Put the key/value in the store.
      store.transaction do
        store[key] = value
      end
    when /^get:/ # Client wants us to retrieve a value.
      key = command[4..-1]
      # Grab the value and send it back.
      client.write serialize[store.transaction { store[key] } || '']
    when /^done/ # Client wants us to shut down.
      client.close
      break
    end
    # Close the connection. Long lived connections are an
    # exercise/extension left for the reader.
    client.close
  end
end
