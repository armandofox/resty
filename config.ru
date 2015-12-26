require 'rubygems'
require 'bundler'

Bundler.require

require './resty'
$stdout.sync = true
run Resty

