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
