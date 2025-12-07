#!/usr/bin/env ruby

require "thor"

class Local < Thor
  include Thor::Actions

  def self.exit_on_failure?
    false
  end

  desc "prepare", "Prepare the web service"
  def prepare(capture: false)
    say "Preparing the web service"

    run("RAILS_ENV=development bin/rails db:migrate db:seed", capture:)
  end

  desc "start", "Start the web service"
  def start(capture: false)
    run("PORT=9292 bin/dev", capture:)
  end

end

Local.start(ARGV)
