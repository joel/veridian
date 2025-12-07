#!/usr/bin/env ruby

require "thor"
require "shellwords"

# https://hub.docker.com/_/mysql

class Db < Thor
  include Thor::Actions

  def self.exit_on_failure?
    false
  end

  desc "start", "Starts the db service"
  method_option :publish, type: :boolean, default: false, desc: 'Publish the port'
  def start(capture: false)
    say "Starting db service"

    db_port = ENV.fetch("DB_PORT", 3306)

    say "Starting db service on port #{db_port}"

    sub_command = ["docker run --rm --detach --name veridian-db"]
    sub_command << "--env MYSQL_ALLOW_EMPTY_PASSWORD=yes"
    sub_command << "--network network.docker-shared-services"
    sub_command << "--volume veridian-data-volume:/var/lib/mysql"
    sub_command << "--volume $(pwd)/certs/mysql/ca.pem:/etc/mysql/certs/ca.pem:ro"
    sub_command << "--volume $(pwd)/certs/mysql/server-cert.pem:/etc/mysql/certs/server-cert.pem:ro"
    sub_command << "--volume $(pwd)/certs/mysql/server-key.pem:/etc/mysql/certs/server-key.pem:ro"
    sub_command << "--volume $(pwd)/config/mysql/ssl.cnf:/etc/mysql/conf.d/ssl.cnf:ro"
    sub_command << "--volume $(pwd)/config/mysql/init.sql:/docker-entrypoint-initdb.d/001-init.sql:ro"
    sub_command << "--publish #{db_port}:3306" # if options[:publish]
    sub_command << "mysql:latest"

    run(sub_command.join(" "), capture: )

    wait_for_db_ready("veridian-db")
  end

  desc "stop", "Stops the db service"
  def stop(capture: false)
    if system("docker ps -a --format '{{.Names}}' | grep -q '^veridian-db$'")
      say "Stopping db service"
      run("docker stop veridian-db", capture: )
    else
      say "Container veridian-db not running/found, skipping stop."
    end
  end

  desc "setup", "Sets up the db service"
  def setup(capture: false)
    # Create network if missing
    unless system("docker network inspect network.docker-shared-services >/dev/null 2>&1")
      run("docker network create network.docker-shared-services", capture: )
    else
      say "Docker network 'network.docker-shared-services' already exists, skipping."
    end

    # Create volume if missing
    unless system("docker volume inspect veridian-data-volume >/dev/null 2>&1")
      run("docker volume create veridian-data-volume", capture: )
    else
      say "Docker volume 'veridian-data-volume' already exists, skipping."
    end

    unless Dir.exist?("certs/mysql")
      say "Generating MySQL TLS certificates..."
      run("bin/mysql.certificates.pre-build.sh", capture: true)
    else
      say "MySQL TLS certificates directory exists, skipping generation."
    end
  end

  desc "prepare", "Creates the database and loads the schema"
  def prepare
    setup(capture: true)
    start(capture: true)

    # fallback to "root" if unset OR empty
    db_user = ENV["MYSQL_USER"]
    db_user = "root" if db_user.nil? || db_user.empty?
    db_user_escaped = Shellwords.escape(db_user)

    say "Using database user: [#{db_user_escaped}]"

    # import: force TCP + absolute path (inside container)
    # run(%Q{docker exec -i veridian-db sh -c "mysql \
    #   --protocol=TCP -h 127.0.0.1 -P 3306 -u #{db_user_escaped} < /production.sql"}, capture: false)

    # show databases: also force TCP
    run(%Q{docker exec veridian-db sh -c "mysql \
      --protocol=TCP -h 127.0.0.1 -P 3306 -u #{db_user_escaped} -e 'SHOW DATABASES;'"},
      capture: false)
  end

  desc "teardown", "Stops and removes the db service"
  def teardown
    stop
    if system("docker network inspect network.docker-shared-services >/dev/null 2>&1")
      run("docker network rm network.docker-shared-services", capture: true)
    else
      say "Docker network 'network.docker-shared-services' not found, skipping removal."
    end

    if system("docker volume inspect veridian-data-volume >/dev/null 2>&1")
      run("docker volume rm veridian-data-volume", capture: true)
    else
      say "Docker volume 'veridian-data-volume' not found, skipping removal."
    end
  end

  desc "console", "Opens a mysql console"
  def console
    run("docker exec -it veridian-db mysql -u root", capture: false)
  end

  desc "exec CMD...", "Executes a command inside the db container (args safely escaped)"
  def exec(*command_parts)
    if command_parts.empty?
      say "No command provided", :red
      exit(1)
    end

    unless system("docker ps -a --format '{{.Names}}' | grep -q '^veridian-db$'")
      say "Container veridian-db not running. Start it first (db start).", :red
      exit(1)
    end

    escaped = command_parts.map { |p| Shellwords.escape(p) }.join(" ")
    say "Executing inside container: #{escaped}"
    run(%Q{docker exec -it veridian-db sh -c #{Shellwords.escape(escaped)}}, capture: false)
  end

  private

  # Wait until MySQL is accepting connections, or time out
  def wait_for_db_ready(container_name)
    max_attempts = 30
    say "Waiting for MySQL in '#{container_name}' to be ready..."

    max_attempts.times do |attempt|
      ok = system(%Q{
        docker exec #{container_name} sh -c "mysqladmin ping \
          --protocol=TCP -h 127.0.0.1 -P 3306 -u root --silent"
      })
      if ok
        say "MySQL is ready!"
        return
      else
        say "Attempt #{attempt + 1}/#{max_attempts}: Not ready yet. Retrying in 1s..."
        sleep 1
      end
    end

    say "ERROR: MySQL did not become ready after #{max_attempts} attempts."
    exit(1)
  end
end

Db.start(ARGV)
