#!/usr/bin/env ruby

require 'rubygems'
require 'wukong'
require 'ankusa'
require 'ankusa/cassandra_storage'
require 'configliere' ; Configliere.use(:commandline, :env_var, :define)

Settings.define :class_field, :type => Integer, :default  => 0,      :description => "Field number to use as class name when training"
Settings.define :text_field,  :type => Integer, :required => true,   :description => "Field number to use as text"
Settings.define :storage,     :default => "cassandra",               :description => "Which storage backend to use? (cassandra or hbase)"
Settings.define :host,        :type => String,  :required => true,   :description => "Initial host to use (cassandra or hbase)"
Settings.define :port,        :type => String,  :default  => "9160", :description => "Port to use (cassandra or hbase)"
Settings.define :train,       :default => false
Settings.resolve!

#
# Streams records through either training classifier on any two fields (class_field,text_field)
# or classifying a single field (text_field).
#
# Example command for training (uses hadoop streaming):
#
# ./streaming_classifier.rb --run --train --host=199.168.1.119 --class_field=0 --text_field=1 /path/to/input /path/to/output
#
# Example command for classifying (uses hadoop steaming):
#
# ./streaming_classifier.rb --run --host=199.168.1.119 --text_field=1 /path/to/input /path/to/output
#
# The class is simply pre-pended to the record.
#
class TextMapper < Wukong::Streamer::RecordStreamer

  def initialize *args
    case Settings.storage
    when "cassandra" then
      @storage = Ankusa::CassandraStorage.new Settings.host, Settings.port
    when "hbase" then
      @storage = Ankusa::HBaseStorage.new Settings.host, Settings.port
    end
    @storage.init_tables
    @classifier = Ankusa::Classifier.new @storage
    super(*args)
  end
  
  def process *args
    if Settings.train
      train args[Settings.class_field], args[Settings.text_field]
      yield args
    else
      yield [classify(args[Settings.text_field]), args]
    end
  end

  def train klass, text
    @classifier.train klass, text
  end

  def classify text
    @classifier.classify text
  end

  def after_stream
    @storage.close
  end
  
end

Wukong::Script.new(TextMapper, nil).run

