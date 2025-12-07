#!/usr/bin/env ruby

require "thor"
require "shellwords"

class Web < Thor
  include Thor::Actions

  def self.exit_on_failure?
    false
  end

  desc "build", "Build the docker container"
  def build(capture: false)
    say "Building the docker container"

    run(
      <<~CMD.gsub(/\s+/, " ").strip,
        docker build . \
          --tag workanywhere/veridian-app:latest \
          -f Dockerfile
      CMD
      capture:
    )

    run(
      <<~CMD.gsub(/\s+/, " ").strip,
          docker build . \
            --tag workanywhere/wait:2.12.1 \
            -f dockerfiles/Dockerfile-wait
      CMD
      capture:
    )
  end

  desc "setup", "Setup the web service"
  def setup(capture: false)
    build
    say "Setting up the web service"

    run("docker network create network.docker-shared-services", capture: true)
  end

  desc "prepare", "Prepare the web service"
  def prepare(capture: false)
    # Check if the docker image exists
    unless system("docker image inspect workanywhere/veridian-app:latest > /dev/null 2>&1")
      say "Docker image workanywhere/veridian-app:latest not found, please run `bin/web setup` first."
      exit 1
    end

    # say "Preparing the web service"

    # start(capture:)

    # exec("bin/rails", "db:migrate")
  end

  desc "start", "Start the web service"
  def start(capture: false)
    # prepare(capture:)
    # Check if the docker image exists
    unless system("docker image inspect workanywhere/veridian-app:latest > /dev/null 2>&1")
      say "Docker image workanywhere/veridian-app:latest not found, please run `bin/web setup` first."
      exit 1
    end

    say "Starting the web service"

    db_port = ENV.fetch("DB_PORT", 3306)

    run(
      <<~CMD.gsub(/\s+/, " ").strip,
        docker run --rm --detach \
          --name veridian-app \
          --publish 8080:9292 \
          --env DB_HOST=veridian-db \
          --env DB_PORT=#{db_port} \
          --env RAILS_MASTER_KEY=$(cat config/master.key) \
          --env RAILS_ENV=production \
          --env RAILS_LOG_TO_STDOUT=true \
          --env RAILS_SERVE_STATIC_FILES=true \
          --env MYSQL_USER=root \
          --env MYSQL_PASSWORD="" \
          --network network.docker-shared-services \
          --volume $(pwd)/certs/mysql/ca.pem:/run/secrets/mysql-ca.pem:ro \
          --label traefik.enable=true \
          --label 'traefik.http.routers.workanywhere.rule=Host(`veridian.workanywhere.docker`)' \
          --label traefik.http.routers.workanywhere.entrypoints=websecure \
          --label traefik.http.routers.workanywhere.tls=true \
          --label traefik.http.services.workanywhere.loadbalancer.server.port=9292 \
          --label traefik.docker.network=network.docker-shared-services \
          workanywhere/veridian-app:latest bin/rails s -p 9292 -b 0.0.0.0
      CMD
      capture:
    )

    say "Waiting for the web service to be ready"

    run(
      <<~CMD.gsub(/\s+/, " ").strip,
        docker run --rm \
        --name veridian-wait \
        --network network.docker-shared-services \
        --env WAIT_HOSTS=veridian-app:9292 \
        --env WAIT_TIMEOUT=10 \
        --env WAIT_BEFORE=1 \
        --env WAIT_SLEEP_INTERVAL=2 \
        --env WAIT_COMMAND="/health_check.sh" \
        --env WAIT_LOGGER_LEVEL=debug \
        workanywhere/wait:2.12.1
      CMD
      capture:
    )

    run("docker logs veridian-app", capture: false)

    say "Re-attaching to the web service"
    run("docker attach veridian-app", capture: false)
  end

  desc "stop", "Stops the web service"
  def stop(capture: false)
    say "Stopping the web service"

    run("docker stop veridian-app", capture:)
  end

  desc "teardown", "Teardown the web service"
  def teardown(capture: false)
    stop(capture: true)
    say "Tearing down the web service"

    run("docker image rm workanywhere/veridian-app:latest", capture:)
  end

  desc "schema_dump", "Dumps the Rails schema inside the db container and copies it to host"
  def schema_dump
    say "Running db:schema:dump"
    app_container = "veridian-app"

    if container_running?(app_container)
      exec("bin/rails", "db:schema:dump")
      copy_schema_from_container(app_container)
    else
      say "Container #{app_container} not running. Creating a temporary container for schema dump."
      schema_dump_with_temporary_container
    end

    say "Schema copied to db/schema.rb"
  end

  desc "migrate", "Runs bin/rails db:migrate inside the db container"
  def migrate
    exec("bin/rails", "db:migrate")
  end

  desc "exec CMD...", "Executes a command inside the app container (args safely escaped)"
  def exec(*command_parts,
           container_name: "veridian-app",
           reuse_existing_container: true,
           new_container_name: nil,
           new_container_remove: true,
           new_container_detach: true)
    if command_parts.empty?
      say "No command provided", :red
      exit(1)
    end

    # unless system("docker ps -a --format '{{.Names}}' | grep -q '^veridian-app$'")
    #   say "Container veridian-app not running. Start it first (app start).", :red
    #   exit(1)
    # end

    escaped = command_parts.map { |p| Shellwords.escape(p) }.join(" ")

    say "Executing inside container: #{escaped}"

    if reuse_existing_container && container_running?(container_name)
      say "Reusing existing container #{container_name}"
      run(%Q{docker exec -it #{container_name} sh -c #{Shellwords.escape(escaped)}}, capture: false)
    else
      container_info = new_container_name ? " (#{new_container_name})" : ""
      say "Starting a new container to run the command#{container_info}"

      db_port = ENV.fetch("DB_PORT", 3306)
      docker_flags = []
      docker_flags << "--name #{new_container_name}" if new_container_name
      docker_flags << "--rm" if new_container_remove
      docker_flags << "--detach" if new_container_detach

      run(
        <<~CMD.gsub(/\s+/, " ").strip,
          docker run #{docker_flags.join(" ")} \
            --env DB_HOST=veridian-db \
            --env DB_PORT=#{db_port} \
            --env RAILS_MASTER_KEY=$(cat config/master.key) \
            --env RAILS_ENV=production \
            --env RAILS_LOG_TO_STDOUT=true \
            --env RAILS_SERVE_STATIC_FILES=true \
            --env MYSQL_USER=root \
            --env MYSQL_PASSWORD="" \
            --network network.docker-shared-services \
            --volume $(pwd)/certs/mysql/ca.pem:/run/secrets/mysql-ca.pem:ro \
            workanywhere/veridian-app:latest sh -c #{Shellwords.escape(escaped)}
        CMD
        capture: false
      )
    end
  end

  private

  def container_running?(name)
    system("docker ps --format '{{.Names}}' | grep -q '^#{name}$'")
  end

  def container_exists?(name)
    system("docker ps -a --format '{{.Names}}' | grep -q '^#{name}$'")
  end

  def copy_schema_from_container(container_name)
    run("docker cp #{container_name}:/rails/db/schema.rb db/schema.rb", capture: false)
  end

  def schema_dump_with_temporary_container
    temp_container = "veridian-schema-dump-#{Process.pid}-#{rand(1_000_000)}"

    begin
      exec(
        "bin/rails", "db:schema:dump",
        reuse_existing_container: false,
        new_container_name: temp_container,
        new_container_remove: false,
        new_container_detach: false
      )

      copy_schema_from_container(temp_container)
    ensure
      run("docker rm #{temp_container}", capture: false) if container_exists?(temp_container)
    end
  end

end

Web.start(ARGV)
