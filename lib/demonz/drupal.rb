# Require our base library.
require 'demonz/base'
require 'railsless-deploy'

configuration = Capistrano::Configuration.respond_to?(:instance) ?
  Capistrano::Configuration.instance(:must_exist) :
  Capistrano.configuration(:must_exist)

configuration.load do

  # --------------------------------------------
  # Setting defaults
  # --------------------------------------------
  set :drush_bin, "drush"
  _cset :dump_options,    "" # blank options b/c of MYISAM engine (unless anyone knows options that should be included)

  # Boost module support (Drupal)
  set :uses_boost, true

  # --------------------------------------------
  # Calling our Methods
  # --------------------------------------------
  after "deploy:setup", "deploy:setup_local"
  after "deploy:finalize_update", "demonz:fixperms"
  before "deploy:create_symlink", "drupal:symlink"
  before "deploy:create_symlink", "drupal:protect"
  before "deploy:create_symlink", "drupal:backup_files_dir"
  before "deploy:create_symlink", "drupal:migrate"
  before "deploy:create_symlink", "drupal:clearcache"

  after "deploy:cleanup", "drupal:cleanup_files_backups"

  # rollback the database and files directory during a rollback too
  before "deploy:rollback:revision", "drupal:rollback_db"
  after "drupal:rollback_db", "drupal:rollback_files_dir"

  # --------------------------------------------
  # Overloaded Methods
  # --------------------------------------------
  namespace :deploy do
    desc "Setup local files necessary for deployment"
    task :setup_local do
      logger.important "make sure you copy over your files directory and settings files now"
      # attempt to create files needed for proper deployment
      if local_file_exists?('.htaccess')
        system("cp .htaccess htaccess.dist")
        system("git add htaccess.dist")
        puts "Please commit htaccess.dist to your source control repository."
      end
    end

    desc "Setup shared application directories and permissions after initial setup"
    task :setup_shared do
      uses_boost = fetch(:uses_boost, false)

      # remove Capistrano specific directories
      run "#{try_sudo} rm -Rf #{shared_path}/log"
      run "#{try_sudo} rm -Rf #{shared_path}/pids"
      run "#{try_sudo} rm -Rf #{shared_path}/system"

      # create shared directories
      run "#{try_sudo} mkdir -p #{shared_path}/default/files"
      if uses_boost
        run "#{try_sudo} mkdir -p #{shared_path}/boost/cache/normal"
      end

      # set correct permissions
      run "#{try_sudo} chmod -R 777 #{shared_path}/*"
    end

    desc "[internal] Touches up the released code. This is called by update_code after the basic deploy finishes."
    task :finalize_update, :roles => :web, :except => { :no_release => true } do
      run "#{try_sudo} rm -Rf #{latest_release}/sites/default/files"
    end

    namespace :web do
      desc "Disable the application and show a message screen"
      task :disable, :roles => :web do
        run "#{drush_bin} -r #{latest_release} vset --yes site_offline 1"
      end

      desc "Enable the application and remove the message screen"
      task :enable, :roles => :web do
        run "#{drush_bin} -r #{latest_release} vdel --yes site_offline"
      end
    end
  end

  # --------------------------------------------
  # Remote/Local database migration tasks
  # --------------------------------------------
  namespace :db do
    task :local_export do
      mysqldump     = fetch(:mysqldump, "mysqldump")
      dump_options  = fetch(:dump_options, "")

      system "#{mysqldump} #{dump_options} --opt -h#{db_local_host} -u#{db_local_user} -p#{db_local_pass} #{db_local_name} | gzip -c --best > #{db_local_name}.sql.gz"
    end

    desc "Create a compressed MySQL dumpfile of the remote database"
    task :remote_export, :roles => :db do
      mysqldump     = fetch(:mysqldump, "mysqldump")
      dump_options  = fetch(:dump_options, "")

      run "#{mysqldump} #{dump_options} --opt -h#{db_remote_host} -u#{db_remote_user} -p#{db_remote_pass} #{db_remote_name} | gzip -c --best > #{deploy_to}/#{db_remote_name}.sql.gz"
    end

  end

  namespace :backup do
    desc "Perform a backup of database files"
    task :db, :roles => :db do
      if releases.last.nil?
        logger.important "no previous release to backup; backup of database skipped"
      else
        logger.info "Backing up the database now and putting dump file in the previous release directory"
        # define the filename (include the current_path so the dump file will be within the directory)
        filename = "#{current_path}/default_dump-#{Time.now.to_s.gsub(/ /, "_")}.sql.gz"
        # dump the database for the proper environment
        run "#{drush_bin} -r #{current_path} sql-dump | gzip -c --best > #{filename}"
      end
    end
  end

  # --------------------------------------------
  # Drupal-specific methods
  # --------------------------------------------
  namespace :drupal do
    desc "Create database"
    task :create_db, :roles => :web, :except => { :no_release => true } do
      drupal_app_site_dir = File.join(latest_release, 'sites', 'default')
      settings_file = File.join(drupal_app_site_dir, 'settings.php')

      # Check if the base settings.php file exists first (we need this for db details)
      if !remote_file_exists?(settings_file)
        raise Capistrano::Error, "A settings.php file was not found, please create one before continuing. See previous errors for more info."
      end

      # Get database name
      set :clean_db_name, get_db_name(application, release_name)

      # Get MySQL connection string from drush (don't need a full bootstrap)
      mysql_connection = capture("#{drush_bin} -r #{latest_release} sql-connect").chomp

      # Only create if database doesn't exist
      if !database_exists?(mysql_connection, clean_db_name)
        # Remove DB on rollback
        on_rollback { delete_database(mysql_connection, clean_db_name) }

        create_database(mysql_connection, clean_db_name)
        setup_database_permissions(mysql_connection, clean_db_name)
      end

      # Add the database name to the settings file.
      update_db_in_settings_file(settings_file, clean_db_name)
    end

    desc "Copy old database to new one"
    task :copy_old_to_new_db, :roles => :web, :except => { :no_release => true } do
      if releases.last.nil?
        # Ask user to upload a gzipped SQL file
        logger.important "no previous release found, please specify a (gzipped) sql file I can use instead"
        db_file_path = text_prompt("Full path to SQL file: ")

        # Error out if file doesn't exist
        raise Capistrano::Error, "File '#{db_file_path}' not found" unless local_file_exists?(db_file_path)

        db_file_parts = File.split(db_file_path)
        db_file = db_file_parts[1]

        # Upload file to temp directory
        remote_db_file = File.join(tmp_backups_path, db_file)
        top.upload(db_file_path, remote_db_file)

        # Just incase the command after fails, remove the upload file
        on_rollback { run "#{try_sudo} rm #{remote_db_file}" }

        run "gzip -fd #{remote_db_file} -c | #{drush_bin} -r #{latest_release} sqlc"

        # We don't need the upload file anymore
        run "#{try_sudo} rm #{remote_db_file}"
      else
        # Use current release as base
        run "#{drush_bin} -r #{current_release} sql-dump | #{drush_bin} -r #{latest_release} sqlc"
      end
    end

    desc "Run any update scripts for this release"
    task :run_update_scripts, :roles => :web, :except => { :no_release => true } do
      update_script_file = File.join(latest_release, 'sites', 'all', 'scripts', release_name, 'update.sh')

      if remote_file_exists?(update_script_file)
        run update_script_file
      end
    end

    desc "Symlink shared directories"
    task :symlink, :roles => :web, :except => { :no_release => true } do
      uses_boost = fetch(:uses_boost, false)
      # copies the appropriate environment's settings.php file
      copy_config_file

      run "#{try_sudo} ln -nfs #{shared_path}/default/files #{latest_release}/sites/default/files"
      # run "#{drush_bin} -r #{latest_release} vset --yes file_directory_path sites/default/files"

      # Symlink boost cache directory
      if uses_boost
        run "#{try_sudo} ln -nfs #{shared_path}/boost/cache #{latest_release}/cache"
      end
    end

    desc <<-DESC
      Copies the appropriate environment's settings file within the proper sites directory

      Assumes the environment's settings file will be in the following format:
        settings.<environment>.php
    DESC
    task :copy_config_file, :roles => :web, :except => { :no_release => true} do
      drupal_app_site_dir = " #{latest_release}/sites/default"

      case true
        when remote_file_exists?("#{shared_path}/settings.#{stage}.php")
          run "#{try_sudo} cp -fL #{shared_path}/settings.#{stage}.php #{drupal_app_site_dir}/settings.php"
        when remote_file_exists?("#{drupal_app_site_dir}/settings.#{stage}.php")
          run "#{try_sudo} cp -fL #{drupal_app_site_dir}/settings.#{stage}.php #{drupal_app_site_dir}/settings.php"
        else
          logger.important "Failed to symlink the settings.php file in #{drupal_app_site_dir} because an unknown pattern was used"
      end
    end

    desc "Migrate old database to new release"
    task :migrate, :roles => :web, :except => { :no_release => true } do
      create_db
      copy_old_to_new_db
      run_update_scripts
      # Run drush updb just incase
      run "#{drush_bin} -r #{latest_release} updb"
    end

    desc "Backup the shared 'files' directory"
    task :backup_files_dir, :roles => :web, :except => { :no_release => true } do
      set :archive_name, "files_before_#{release_name}.tar.gz"
      set :files_dir_location, File.join(shared_path, 'default')
      logger.debug "Creating a Tarball of the files directory in #{backups_path}/#{archive_name}"
      run "cd #{files_dir_location} && tar -cvpf - files | gzip -c --best > #{backups_path}/#{archive_name}"
    end

    desc "Clear all Drupal cache"
    task :clearcache, :roles => :web, :except => { :no_release => true } do
      run "#{drush_bin} -r #{latest_release} cache-clear all"
      # Remove the 'styles' imagecache directory
      image_styles_path = File.join(shared_path, 'default', 'files', 'styles')
      run "#{try_sudo} rm -rf #{image_styles_path}" if remote_dir_exists?(image_styles_path)
      # Also clear boost cache if set
      boost_path = File.join(shared_path, 'boost', 'cache', 'normal', '*')
      run "#{try_sudo} rm -rf #{boost_path}" if fetch(:uses_boost, false)
    end

    desc "Protect system files"
    task :protect, :roles => :web, :except => { :no_release => true } do
      run "#{try_sudo} chmod 644 #{latest_release}/sites/default/settings.php*"
    end

    desc "[internal] Delete latest version of DB"
    task :rollback_db, :except => { :no_release => true } do
      if previous_release
        clean_db_name = get_db_name(application, releases.last)
        mysql_connection = capture("#{drush_bin} -r #{latest_release} sql-connect").chomp
        delete_database(mysql_connection, clean_db_name)
      else
        abort "could not rollback the code because there is no prior release"
      end
    end

    desc "[internal] Rollback shared files directory"
    task :rollback_files_dir, :except => { :no_release => true } do
      if previous_release
        old_release = releases.last
        files_backup_file = File.join(backups_path, "files_before_#{old_release}.tar.gz")

        if remote_file_exists?(files_backup_file)
          files_dir_location = File.join(shared_path, 'default')
          files_dir = File.join(files_dir_location, 'files')
          files_dir_backup_archive = "files_after_#{old_release}_OLD"

          on_rollback {
            run "#{try_sudo} rm #{files_dir}" if remote_file_exists?(files_dir_backup_archive) && remote_dir_exists?(files_dir)
            run "#{try_sudo} tar -xvzf #{files_dir_backup_archive} -C #{files_dir_location}" if remote_file_exists?(files_dir_backup_archive)
          }

          run "cd #{files_dir_location} && tar -cvpf - files | gzip -c --best > #{backups_path}/#{files_dir_backup_archive}"
          run "#{try_sudo} tar -xvzf #{files_backup_file} -C #{files_dir_location}"
        end
      else
        abort "could not rollback the code because there is no prior release"
      end
    end

    desc "[internal] Remove old file directory backups"
    task :cleanup_files_backups, :roles => :web, :except => { :no_release => true } do
      if variables.include?(:cleanup_releases)
        cleanup_releases = fetch(:cleanup_releases, nil)

        if !cleanup_releases.nil?
          files_backups = cleanup_releases.map { |release|
            File.join(backups_path, "file_before_#{release}.tar.gz") }.join(" ")
          try_sudo "rm -rf #{files_backups}"
        end
      end
    end
  end
end
