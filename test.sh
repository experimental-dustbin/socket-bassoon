#!/bin/bash
function test {
  source "client.sh"
  rm -f /tmp/store /tmp/store.yaml
  sleep 1
  start &> /dev/null &
  sleep 1
  set -x
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
