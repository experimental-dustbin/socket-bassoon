# Unix domain sockets, serializers, deserializers, and protocol parsers

Programmers often talk about using the right/composable tool for the job but if you're like me that advice is probably way too high level and abstract. It's hard to get a handle on what "right tool" and "composable" mean abstractly so let's make it all concrete by building a simple key/value store in Ruby with an equally simple protocol for setting and retrieving keys and their associated values. At the end of this you should have a more concrete handle on what "right tool" and "composable" mean in the context of a basic key/value store and how such things can be built/composed from more simple building blocks like sockets, serializers, deserializers, and protocol parsers.

# Problem statement
We'd like to track/record/update some kind of information as our code is executing and we'd like to use a central repository for doing this. We'll use a unix domain socket as the handle for this central repository and our API will consist of 4 methods: start, stop, set, get.

If you squint a little bit you'll notice this is how most web applications are structured. There's a database and our code talks to it through a connection string. Behind the scenes there are protocols and associated parsers/serializers/deserializers that help with shuttling the data back and forth between the database and the process running the code. So we are really recreating a toy version of this pattern in order to better understand it and its association with "right tool" and "composable".

# Unix domain sockets, server loops, serializers, deserializers, and protocol parsers

I think unix domain sockets are a really handy tool. They're a standard part of all POSIX compliant operating systems but they're surprisingly underutilized for structuring software systems and enforcing abstraction boundaries. I haven't had many opportunities to use them directly but they're a good way to enforce a rigorous separation between processes and components. Using a socket forces you to think about the protocol for the interface and is a worthwhile exercise even if you decide to keep everything in a single process.

I'm going to present the code all in one go with comments and then explain each part as we write the client and test code

```ruby
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
```

From a very high level we have a very simple structure. We have a loop that accepts client connections, deserializes the request from the client, parses the deserialized request to figure out what the client wants, and finally performs the request by either retrieving or storing a value in the key/value store.

I'm using base 64 to emulate the serialization/deserialization process. In real world applications this can get pretty complicated but the basic idea remains the same: the message is encoded and then sent over the wire/socket. I recommend looking into other encoding schemes like ASN.1, Protobuf, MessagePack, etc.

From the above code sample you should have also guessed what our protocol format looks like (`done`, `get:key`, `store:key:value`). We're using ":" as a delimiter so we'll have to be careful when ":" appears and escape it in a way that will not mess up our parsing process. The code assumes that we escape ":" with "\\:". We could have put more information into the format and avoided escaping but then the serialization process would have been slightly more complicated. If you want to know what that would look like I recommend looking into prefix encoding schemes where the format includes a header with lengths for different parts of the message.

The other half of this exercise consists of the client code and we'll write that in bash because that will also demonstrate how composing a few command line utilities can allow us to communicate with a socket based server and completely ignore the fact that the server is written in Ruby.

I'll again present the code in one go and then explain what each part is doing and how it relates to the server code

```bash
#!/bin/bash
function start {
  pushd "$( dirname "${BASH_SOURCE[0]}" )"
    ruby kv.rb
  popd
}

function get {
  local -r socket="/tmp/store"
  local -r key="$1"
  local -r k="$( printf "%s" "${key}" | sed 's/:/\\:/g' )"
  local -r command="$( printf "get:%s" "${k}" | base64 -w0 - )"
  printf "%s\n" "${command}" | nc -U "${socket}" | base64 -d -w0 -
}

function store {
  local -r socket="/tmp/store"
  local -r key="$1"
  local -r value="$2"
  local -r k="$( printf "%s" "${key}" | sed 's/:/\\:/g' )"
  local -r v="$( printf "%s" "${value}" | sed 's/:/\\:/g' )"
  local -r command="$( printf "store:%s:%s" "${k}" "${v}" | base64 -w0 - )"
  printf "%s\n" "${command}" | nc -U "${socket}"
}

function stop {
  local -r socket="/tmp/store"
  local -r command="$( printf "done" | base64 -w0 - )"
  printf "%s\n" "${command}" | nc -U "${socket}"
}
```

The above fills in the blanks for the client code and allows us to start testing things. We'll write the tests as another bash script (test.sh). The test script assumes that both the client script (client.sh) and server script (kv.rb) live in the same directory as the test script (test.sh).

```bash
#!/bin/bash
function test {
  source "client.sh"
  rm -f /tmp/store /tmp/store.yaml
  sleep 1
  start &> /dev/null &
  sleep 1
  store "1" "2"
  store "3" "4"
  store "5" "6"
  store "abc:def" "qrs:tuv"
  store "abc\ndef" "qrs\ntuv"
  sleep 1
  get "1"; echo
  get "3"; echo
  get "5"; echo
  get "6"; echo
  get "abc:def"; echo
  get "abc\ndef"; echo
  cat /tmp/store.yaml
  stop
}
test
```

I haven't added any assertions because I just wanted to visually inspect and make sure everything was working properly. The output I get when I run the test script is below

```bash
$ bash test.sh
2
4
6

qrs:tuv
qrs\ntuv
---
'1': '2'
'3': '4'
'5': '6'
abc\:def: qrs:tuv
abc\ndef: qrs\ntuv
```

It seems correct to me and I'll leave adding assertions or converting the test script into a framework of your choice up to you.

Let's trace through the logic of a get and store request to see what is going on in the client and the server. Things are easy on the client side because all we have to do is add "set -x" to the test script

```
# Store "abc:def" "qrs:tuv"
+ store abc:def qrs:tuv
+ local -r socket=/tmp/store
+ local -r key=abc:def
+ local -r value=qrs:tuv
++ printf %s abc:def
++ sed 's/:/\\:/g'
+ local -r 'k=abc\:def'
++ printf %s qrs:tuv
++ sed 's/:/\\:/g'
+ local -r 'v=qrs\:tuv'
++ printf store:%s:%s 'abc\:def' 'qrs\:tuv'
++ base64 -w0 -
+ local -r command=c3RvcmU6YWJjXDpkZWY6cXJzXDp0dXY=
+ printf '%s\n' c3RvcmU6YWJjXDpkZWY6cXJzXDp0dXY=
+ nc -U /tmp/store
```
```
# Get abc:def
+ get abc:def
+ local -r socket=/tmp/store
+ local -r key=abc:def
++ printf %s abc:def
++ sed 's/:/\\:/g'
+ local -r 'k=abc\:def'
++ printf get:%s 'abc\:def'
++ base64 -w0 -
+ local -r command=Z2V0OmFiY1w6ZGVm
+ printf '%s\n' Z2V0OmFiY1w6ZGVm
+ nc -U /tmp/store
+ base64 -d -w0 -
```

I chose the more complicated cases to trace and the sequence of operations should make it clear what is going on. After escaping all special characters and properly formatting our request to conform to the protocol we encode it and send it over the socket to the server.

Tracing the logic on the server is slightly more complicated but not by much. I'll trace the logic for storing "abc:def" "qrs:tuv" because that is the most complicated case and leave tracing the logic for getting "abc:def" as an exercise

```
# Storing "abc:def" "qrs:tuv"
+ client = server.accept
+ client.readline
++ "c3RvcmU6YWJjXDpkZWY6cXJzXDp0dXY=\n"
+ command = deserialize["c3RvcmU6YWJjXDpkZWY6cXJzXDp0dXY=\n"]
++ command = "store:abc\\:def:qrs\\:tuv"
+ case "store:abc\\:def:qrs\\:tuv"
+ when /^store:/
+ key_start = 6
+ key_end = command.index(/[^\\]:/, 6)
++ key_end = 13
+ key, value = command[6..13], command[(13 + 2)..-1]
++ key = "abc\\:def"
++ value = "qrs\\:tuv"
+ value.gsub!('\:', ':')
++ value = "qrs:tuv"
+ store.transaction do store["abc:\\:tuv"] = "qrs:tuv" end
```

# Exercises and extensions

So what did we accomplish? We wrote a basic server and associated client and verified that it works as expected by writing a few tests and tracing through the logic of the encoding and decoding process. If you got this far then you might enjoy taking this in a few different directions.

One direction is to look into binary protocols or prefix/length encoding schemes. Make the changes to the encoding and decoding process and see if it is more or less complicated than using base 64.

Another direction is stress testing the protocol with generative testing and figuring out which edge cases we did not cover. I suspect there are a few land mines and finding those edge cases is a worthwhile exercise.

Yet another direction is re-implementing the server in a language of your choice and seeing how it compares to the Ruby version. If you do this right then the client code won't change.

Probably a few more things I didn't think of so if you think of anything then let me know.
