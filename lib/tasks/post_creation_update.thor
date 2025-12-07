require "thor"

module PostCreation
  module Process
    class Cmd < Thor
      def self.exit_on_failure?
        false
      end

      include Thor::Actions

      namespace "update"

      desc "app", "Run script to update the app"

      # bundle exec thor update:app
      def app
        adapter_name = `bin/rails runner 'puts ActiveRecord::Base.connection.adapter_name'`

        # run("bin/web start", capture: false)

        run("bin/rails g scaffold user name:string --force")

        # Due to trailing whitespace in the Rails service-worker.js file, we need to skip the TrailingWhitespace hook
        # run "sed -i '' 's/[ \t]*$//' app/views/pwa/service-worker.js"
        # Those line will be removed in the future, once the trailing whitespace is fixed in the Rails service-worker.js file

        run("bin/web migrate")
        # run("bin/web schema_dump")
        commit message: "Add scaffold user"

        run("bin/rails g scaffold post title:string body:text user:references --force")
        run("bin/web migrate")
        # run("bin/web schema_dump")
        commit message: "Add scaffold post"

        run_with_clean_bundler_env("git apply patches/posts_controller.rb.patch")
        commit message: "Update posts controller"

        run_with_clean_bundler_env("git apply patches/user.rb.patch")
        commit message: "Update user model"

        run_with_clean_bundler_env("git apply patches/_post_partial.html.erb.patch")
        commit message: "Update post partial"

        run_with_clean_bundler_env("git apply patches/post_form.erb.patch")
        commit message: "Update post form partial"

        append_to_file "db/seeds.rb", <<~RUBY
          user = User.find_or_create_by!(name: "John Doe")
          Post.find_or_create_by!(title: "Hello World", body: "This is a test post", user: user)
        RUBY
        commit message: "Seed content"

        %w[development production].each do |env|
          run("RAILS_ENV=#{env} bin/rails db:create")
          run("RAILS_ENV=#{env} bin/rails db:migrate")
          run("RAILS_ENV=#{env} bin/rails db:seed")
        end

        # if adapter_name =~ /Mysql2/
        #   current_directory_name = File.basename(Dir.pwd)
        #   say "Creating MySQL databases for #{current_directory_name}_development and #{current_directory_name}_test"
        #   run("docker exec mysql-container bash -c \"mysql -u root -e 'CREATE DATABASE IF NOT EXISTS #{current_directory_name}_development;'\"")
        #   run("docker exec mysql-container bash -c \"mysql -u root -e 'CREATE DATABASE IF NOT EXISTS #{current_directory_name}_test;'\"")
        #   run("db:migrate db:seed db:schema:dump")
        # else
        #   run("bin/setup")
        #   run("bin/rails db:seed")
        # end
        # run("bin/rails db:seed")
        # commit message: "Seed content"

        say("Adding foreman to the Gemfile")
        run("bundle add foreman")
        commit message: "Add foreman to the Gemfile"

        1.upto(8) do |i|
          run_with_clean_bundler_env("git apply patches/fix_test_suite-#{i}.patch")
          commit message: "Fix Test Suite #{i}"
        end

        insert_into_file "app/models/post.rb", "  validates :title, presence: true\n", after: "belongs_to :user\n"
        commit message: "Add validation to post model"

        run("mkdir -p spec/system")
        run("cp -v patches/posts_spec.rb spec/system/posts_spec.rb")
        commit message: "Add posts system spec"

        say("Re-Build Docker image with last changes")
        run("bin/web build")
        commit message: "Build Docker image with last changes"

        # say("Migrate the database.")
        # run("bin/web migrate")
        # commit message: "Migrate database"

        # say("Seed the database with initial data.")
        # run("bin/rails db:seed")

        if adapter_name.include?("PostgreSQL")
          say("DB_PORT=5433 bin/dev")
        else
          say("bin/dev")
        end
      end

      private

      def commit(message:, skips: ["RailsSchemaUpToDate"])
        skip_command = ""
        skip_command = "SKIP=#{skips.join(",")}" unless skips.empty?

        puts "| #{"-" * 15}#{"-" * message.length}#{"-" * skip_command.length} |"
        puts "| Committing: #{skip_command} [#{message}] |"
        puts "| #{"-" * 15}#{"-" * message.length}#{"-" * skip_command.length} |"

        run("rubocop -A", capture: true)
        run("rubocop --regenerate-todo", capture: true)

        run_with_clean_bundler_env("git add .")
        run_with_clean_bundler_env("#{skip_command} overcommit --run")

        if run_with_clean_bundler_env("#{skip_command} git commit -m '#{message}'")
          puts "✅ Git commit successful."
        else
          puts "❌ Git commit failed."
        end
      end

      def run_with_clean_bundler_env(cmd)
        success = if defined?(Bundler)
                    Bundler.with_original_env { run(cmd) }
                  else
                    run(cmd)
                  end

        return true if success

        puts "Command failed, exiting: #{cmd}"
        exit(1)
      end
    end
  end
end
