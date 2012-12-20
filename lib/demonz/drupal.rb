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
  # after "deploy:create_symlink", "drupal:symlink"

  # workaround for issues with capistrano v2.13.3 and
  # before/after callbacks not firing for 'deploy:symlink'
  # or 'deploy:create_symlink'
  after "deploy", "drupal:symlink"
  after "drupal:symlink","drupal:protect"
  after "drupal:symlink", "drupal:clearcache"
  after "deploy", "deploy:cleanup"

  # --------------------------------------------
  # Overloaded Methods
  # --------------------------------------------
  namespace :deploy do
    desc "Setup local files necessary for deployment"
    task :setup_local do
      # attempt to create files needed for proper deployment
      system("cp .htaccess htaccess.dist")
      system("git add htaccess.dist")
      puts "Please commit htaccess.dist to your source control repository."
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
        run "#{try_sudo} mkdir -p #{shared_path}/cache/normal"
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
        run "#{drush_bin} -l default -r #{latest_release} vset --yes site_offline 1"
      end

      desc "Enable the application and remove the message screen"
      task :enable, :roles => :web do
        run "#{drush_bin} -l default -r #{latest_release} vdel --yes site_offline"
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
      if previous_release
        puts "Backing up the database now and putting dump file in the previous release directory"
        # define the filename (include the current_path so the dump file will be within the directory)
        filename = "#{current_path}/default_dump-#{Time.now.to_s.gsub(/ /, "_")}.sql.gz"
        # dump the database for the proper environment
        run "#{drush_bin} -l default -r #{current_path} sql-dump | gzip -c --best > #{filename}"
      else
        logger.important "no previous release to backup; backup of database skipped"
      end
    end
  end

  # --------------------------------------------
  # Drupal-specific methods
  # --------------------------------------------
  namespace :drupal do
    desc "Symlink shared directories"
    task :symlink, :roles => :web, :except => { :no_release => true } do
      # symlinks the appropriate environment's settings.php file
      symlink_config_file

      run "#{try_sudo} ln -nfs #{shared_path}/default/files #{latest_release}/sites/default/files"
      run "#{drush_bin} -l default -r #{current_path} vset --yes file_directory_path sites/default/files"
    end

    desc <<-DESC
      Symlinks the appropriate environment's settings file within the proper sites directory

      Assumes the environment's settings file will be in one of two formats:
        settings.<environment>.php    => new default
        settings.php.<environment>    => deprecated
    DESC
    task :symlink_config_file, :roles => :web, :except => { :no_release => true} do
      drupal_app_site_dir = " #{latest_release}/sites/default"

      case true
        when remote_file_exists?("#{drupal_app_site_dir}/settings.#{stage}.php")
          run "#{try_sudo} ln -nfs #{drupal_app_site_dir}/settings.#{stage}.php #{drupal_app_site_dir}/settings.php"
        when remote_file_exists?("#{drupal_app_site_dir}/settings.php.#{stage}")
          run "#{try_sudo} ln -nfs #{drupal_app_site_dir}/settings.php.#{stage} #{drupal_app_site_dir}/settings.php"
        else
          logger.important "Failed to symlink the settings.php file in #{drupal_app_site_dir} because an unknown pattern was used"
      end
    end

    desc "Replace local database paths with remote paths"
    task :updatedb, :roles => :web, :except => { :no_release => true } do
     run "#{drush_bin} -l default -r #{current_path} sqlq \"UPDATE {files} SET filepath = REPLACE(filepath,'sites/#{folder}/files','sites/default/files');\""
    end

    desc "Clear all Drupal cache"
    task :clearcache, :roles => :web, :except => { :no_release => true } do
      run "#{drush_bin} -l default -r #{current_path} cache-clear all"
    end

    desc "Protect system files"
    task :protect, :roles => :web, :except => { :no_release => true } do
      run "#{try_sudo} chmod 644 #{latest_release}/sites/default/settings.php*"
    end
  end
end
