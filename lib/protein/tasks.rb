# -*- encoding : utf-8 -*-
namespace :protein do
  desc "Start as daemon"
  task :start => :configure do
    Protein.control.start
  end

  desc "Restart daemon"
  task :restart => :configure do
    Protein.control.restart
  end

  desc "Start in current process"
  task :run => :configure do
    Protein.control.run
  end

  desc "Stop"
  task :stop => :configure do
    Protein.control.stop
  end

  desc "Forcefully stop"
  task :kill => :configure do
    Protein.control.stop!
  end

  desc "Status"
  task :status => :configure do
    puts Protein.control.status_message
  end

  task :configure do
    require 'protein'

    rails_root = ENV['RAILS_ROOT']
    file       = ENV['CONFIG_FILE']
    Protein.config do |config|
      config.rails_root = rails_root if rails_root.present?
      config.config_files << file    if file.present?
    end
  end
end