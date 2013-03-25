# Capistrano2 differentiator
load 'deploy' if respond_to?(:namespace)
Dir['vendor/plugins/*/recipes/*.rb'].each { |plugin| load(plugin) }

# Required gems/libraries
require 'rubygems'
require 'demonz/common'
require 'capistrano/ext/multistage'

# Bootstrap Capistrano instance
configuration = Capistrano::Configuration.respond_to?(:instance) ?
  Capistrano::Configuration.instance(:must_exist) :
  Capistrano.configuration(:must_exist)

configuration.load do

  # Set shared path to be inside app directory
  set :shared_path, File.join(deploy_to, 'shared')

  # --------------------------------------------
  # Task chains
  # --------------------------------------------
  after "multistage:ensure", "demonz:set_release_history"
  before "deploy", "demonz:set_release_info"
  before "deploy:finalize_update", "demonz:add_release_tracking"
  after "deploy:setup", "deploy:setup_shared"
  after "deploy:setup_shared", "deploy:setup_backup"
  after "deploy:finalize_update", "demonz:htaccess"
  after "deploy", "deploy:cleanup"
  after "deploy:cleanup", "demonz:cleanup_release_tracking"
  before "deploy:rollback", "demonz:set_rollback_release"
  after "deploy:rollback", "demonz:update_release_tracking_for_rollback"

  # --------------------------------------------
  # Default variables
  # --------------------------------------------
  # SSH
  set :user,              proc{text_prompt("SSH username: ")}
  set :password,          proc{Capistrano::CLI.password_prompt("SSH password for '#{user}':")}

  # Database
  # set :dbuser,            proc{text_prompt("Database username: ")}
  # set :dbpass,            proc{Capistrano::CLI.password_prompt("Database password for '#{dbuser}':")}
  # set :dbname,            proc{text_prompt("Database name: ")}
  _cset :mysqldump,       "mysqldump"
  _cset :dump_options,    "--single-transaction --create-options --quick"

  # Source Control
  set :group_writable,    true
  set :use_sudo,          false
  set :scm,               :git
  set :scm_verbose,       true
  set :scm_username,      proc{text_prompt("Git username: ")}
  set :scm_password,      proc{Capistrano::CLI.password_prompt("Git password for '#{scm_username}': ")}
  set :deploy_via,        :remote_cache
  set :copy_strategy,     :checkout
  set :copy_compression,  :bz2
  set :copy_exclude,      [".svn", ".DS_Store", "*.sample", "LICENSE*", "Capfile",
    "RELEASE*", "*.sql", "nbproject", "_template", "*.sublime*"]

  # Backups Path
  _cset(:backups_path)      { File.join(deploy_to, "backups") }
  _cset(:tmp_backups_path)  { File.join("#{backups_path}", "tmp") }
  _cset(:backups)           { capture("ls -x #{backups_path}", :except => { :no_release => true }).split.sort }

  # Define which files or directories you want to exclude from being backed up
  _cset(:backup_exclude)  { [] }
  set :exclude_string,    ''

  # show password requests on windows
  # (http://weblog.jamisbuck.org/2007/10/14/capistrano-2-1)
  default_run_options[:pty] = true

  # Release tracking
  set :release_file,       File.join(shared_path, "RELEASES")

  # Add a dependency on compass and :themes if required
  uses_sass = fetch(:uses_sass, false)
  if uses_sass
    depend :remote, :gem, "compass", ">=0.12"
    _cset(:themes) { abort "Please specify themes on this site, set :themes, ['theme1', 'theme2']" }
  end

  # We need PHP and gzip
  depend :remote, :command, "php"
  depend :remote, :command, "gzip"

  # --------------------------------------------
  # Overloaded tasks
  # --------------------------------------------
  namespace :deploy do
    desc <<-DESC
      Prepares one or more servers for deployment. Before you can use any \
      of the Capistrano deployment tasks with your project, you will need to \
      make sure all of your servers have been prepared with `cap deploy:setup'. When \
      you add a new server to your cluster, you can easily run the setup task \
      on just that server by specifying the HOSTS environment variable:

        $ cap HOSTS=new.server.com deploy:setup

      It is safe to run this task on servers that have already been set up; it \
      will not destroy any deployed revisions or data.
    DESC
    task :setup, :except => { :no_release => true } do
      dirs = [deploy_to, releases_path, shared_path]
      dirs += shared_children.map { |d| File.join(shared_path, d.split('/').last) }
      run "#{try_sudo} mkdir -p #{dirs.join(' ')}"
      run "#{try_sudo} chmod 775 #{dirs.join(' ')}" if fetch(:group_writable, true)
      run "#{try_sudo} touch #{release_file}"
      run "#{try_sudo} chmod g+w #{release_file}" if fetch(:group_writable, true)
      run "#{try_sudo} chown -R #{user}:#{group} #{deploy_to}"
    end

    desc "Setup backup directory for database and web files"
    task :setup_backup, :except => { :no_release => true } do
      run "#{try_sudo} mkdir -p #{backups_path} #{tmp_backups_path} && #{try_sudo} chmod 775 #{backups_path} && #{try_sudo} chmod 775 #{tmp_backups_path} && #{try_sudo} chown -R #{user}:#{group} #{backups_path}"
    end

    desc <<-DESC
      Clean up old releases. By default, the last 5 releases are kept on each \
      server (though you can change this with the keep_releases variable). All \
      other deployed revisions are removed from the servers. By default, this \
      will use sudo to clean up the old releases, but if sudo is not available \
      for your environment, set the :use_sudo variable to false instead. \

      Overridden to set/reset file and directory permissions
    DESC
    task :cleanup, :except => { :no_release => true } do
      count = fetch(:keep_releases, 5).to_i
      local_releases = get_release_history(release_file).split
      if count >= local_releases.length
        logger.important "no old releases to clean up"
      else
        logger.info "keeping #{count} of #{local_releases.length} deployed releases"
        set :cleanup_releases, (local_releases - local_releases.last(count))
        directories = cleanup_releases.map { |release|
          File.join(releases_path, release) }.join(" ")

        directories.split(" ").each do |dir|
          set_perms_dirs(dir)
          set_perms_files(dir)
        end

        try_sudo "rm -rf #{directories}"
      end
    end

    desc "Show deployment release history"
    task :history do
      logger.important "Previous deployments (in ascending order)"
      history = get_release_history(release_file)

      if history.empty?
        logger.info "No previous deployments found"
      else
        logger.info history
      end
    end
  end

  # --------------------------------------------
  # Demonz tasks
  # --------------------------------------------
  namespace :demonz do
    desc "[internal] Set release history"
    task :set_release_history, :roles => :web, :except => { :no_release => true } do
      set :releases, get_release_history(release_file).split
    end

    desc "Set standard permissions for Demonz servers"
    task :fixperms, :roles => :web, :except => { :no_release => true } do
      # chmod the files and directories.
      set_perms_dirs("#{latest_release}")
      set_perms_files("#{latest_release}")
    end

    desc "Test: Task used to verify Capistrano is working. Prints operating system name."
    task :uname do
      run "uname -a"
    end

    desc "Test: Task used to verify Capistrano is working. Prints environment of Capistrano user."
    task :getpath do
      run "echo $PATH"
    end

    desc 'Copy distribution htaccess file'
    task :htaccess, :roles => :web do
      case true
      when remote_file_exists?("#{latest_release}/htaccess.#{stage}.dist")
        run "#{try_sudo} mv #{latest_release}/htaccess.#{stage}.dist #{latest_release}/.htaccess"
      when remote_file_exists?("#{latest_release}/htaccess.#{stage}")
        run "#{try_sudo} mv #{latest_release}/htaccess.#{stage} #{latest_release}/.htaccess"
      when remote_file_exists?("#{latest_release}/htaccess.dist")
        run "#{try_sudo} mv #{latest_release}/htaccess.dist #{latest_release}/.htaccess"
      else
        logger.important "Failed to move the .htaccess file in #{latest_release} because an unknown pattern was used"
      end
    end

    # Modified from https://gist.github.com/2016396
    desc "Push local changes to Git repository"
    task :push do
      # Check we are on the right branch, so we can't forget to merge before deploying
      branch = %x(git branch --no-color 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \\(.*\\)/\\1/').chomp
      if branch != "#{branch}" && !ENV["IGNORE_BRANCH"]
        raise Capistrano::Error, "Not on #{branch} branch (set IGNORE_BRANCH=1 to ignore)"
      end

      # Push the changes
      if ! system "git push --tags #{fetch(:repository)} #{branch}"
        raise Capistrano::Error, "Failed to push changes to #{fetch(:repository)}"
      end
    end

    desc "[internal] Set release info (such as release name and git tag)"
    task :set_release_info, :roles => :web, :except => { :no_release => true } do
      # Get all Git tags from local repository
      all_tags = %x[git for-each-ref --sort='*authordate' --format='%(refname:short)' refs/tags].split

      # Error out if not tags
      # if all_tags.empty?
      #   raise Capistrano::Error, "No Git tags found, please define some before attempting deployment"
      # end

      # We're not using pure timestamps to track deployment anymore
      set :deploy_timestamped, false

      if variables.include?(:tag) && !all_tags.empty? && all_tags.include?(tag)
        logger.info "deploying using Git tag '#{tag}'"

        # Set revision to the commit that :tag points to
        set :revision, run_locally("git rev-list #{tag} | head -n 1")

        # Slashes are bad in directory names
        clean_tag = tag.gsub("/", "-")
      else
        logger.important "no valid Git tag specified, continuing with HEAD instead"

        # Get tag from user
        tag = text_prompt("Please specify a tag name for this release (this will be created): ")
        logger.info "setting release tag to #{tag}"

        # Slashes are bad in directory names
        clean_tag = tag.gsub("/", "-")

        # Try to add tag to git
        if ! system "git tag #{clean_tag}"
          raise Capistrano::Error, "Failed to Git tag: #{clean_tag}"
        end
      end

      # If the release directory already exists, append timestamp
      if remote_file_exists?(File.join(releases_path, clean_tag, 'REVISION'))
        clean_tag += '-' + Time.now.utc.strftime("%Y%m%d%H%M%S")
        logger.important "previous deployment with this tag found, setting current release name to #{clean_tag}"
      end

      set :release_name, clean_tag
      set :latest_release, release_path
    end

    desc "[internal] Keep track of the current release"
    task :add_release_tracking, :roles => :web, :except => { :no_release => true } do
      on_rollback { remove_release_from_history(release_name, release_file) }
      run "#{try_sudo} echo #{release_name} >> #{release_file}"
    end

    desc "[internal] Cleanup release tracking"
    task :cleanup_release_tracking, :roles => :web, :except => { :no_release => true } do
      if variables.include?(:cleanup_releases)
        cleanup_releases = fetch(:cleanup_releases, nil)

        if !cleanup_releases.nil?
          files_backups = cleanup_releases.map { |release|
            remove_release_from_history(release, release_file) }
        end
      end
    end

    desc "[internal] Set last release name for rollback"
    task :set_rollback_release, :except => { :no_release => true } do
      set :release_name, releases.last
    end

    desc "[internal] Remove rollback release from release tracking"
    task :update_release_tracking_for_rollback, :except => { :no_release => true } do
      remove_release_from_history(release_name, release_file)
    end
  end

  # --------------------------------------------
  # PHP tasks
  # --------------------------------------------
  namespace :php do
    namespace :apc do
      desc "Disable the APC administrative panel"
      task :disable, :roles => :web, :except => { :no_release => true } do
        run "#{try_sudo} rm #{current_path}/apc.php"
      end

      desc "Enable the APC administrative panel"
      task :enable, :roles => :web, :except => { :no_release => true } do
        run "#{try_sudo} ln -s /usr/local/lib/php/apc.php #{current_path}/apc.php"
      end
    end
  end

  # --------------------------------------------
  # Remote/Local database migration tasks
  # --------------------------------------------
  namespace :db do
    desc "Migrate remote application database to local server"
    task :to_local, :roles => :db, :except => { :no_release => true } do
      remote_export
      remote_download
      local_import
    end

    desc "Migrate local application database to remote server"
    task :to_remote, :roles => :db, :except => { :no_release => true } do
      local_export
      local_upload
      remote_import
    end

    desc "Handles importing a MySQL database dump file. Uncompresses the file, does regex replacements, and imports."
    task :local_import, :roles => :db do
      # check for compressed file and decompress
      if local_file_exists?("#{db_remote_name}.sql.gz")
        system "gunzip -f #{db_remote_name}.sql.gz"
      end

      if local_file_exists?("#{db_remote_name}.sql")
        # import into database
        system "mysql -h#{db_local_host} -u#{db_local_user} -p#{db_local_pass} #{db_local_name} < #{db_remote_name}.sql"
        # remove used file
        run "#{try_sudo} rm -f #{deploy_to}/#{db_remote_name}.sql.gz"
        system "#{try_sudo} rm -f #{db_remote_name}.sql"
      end
    end

    task :local_export do
      mysqldump     = fetch(:mysqldump, "mysqldump")
      dump_options  = fetch(:dump_options, "--single-transaction --create-options --quick")

      system "#{try_sudo} #{mysqldump} #{dump_options} --opt -h#{db_local_host} -u#{db_local_user} -p#{db_local_pass} #{db_local_name} | gzip -c --best > #{db_local_name}.sql.gz"
    end

    desc "Upload locally created MySQL dumpfile to remote server via SCP"
    task :local_upload, :roles => :db do
      upload "#{db_local_name}.sql.gz", "#{deploy_to}/#{db_local_name}.sql.gz", :via => :scp
    end

    desc "Handles importing a MySQL database dump file. Uncompresses the file, does regex replacements, and imports."
    task :remote_import, :roles => :db do
      # check for compressed file and decompress
      if remote_file_exists?("#{deploy_to}/#{db_local_name}.sql.gz")
        run "gunzip -f #{deploy_to}/#{db_local_name}.sql.gz"
      end

      if remote_file_exists?("#{deploy_to}/#{db_local_name}.sql")
        # import into database
        run "mysql -h#{db_remote_host} -u#{db_remote_user} -p#{db_remote_pass} #{db_remote_name} < #{deploy_to}/#{db_local_name}.sql"
        # remove used file
        run "#{try_sudo} rm -f #{deploy_to}/#{db_local_name}.sql"
        system "#{try_sudo} rm -rf #{db_local_name}.sql.gz"
      end
    end

    desc "Create a compressed MySQL dumpfile of the remote database"
    task :remote_export, :roles => :db do
      mysqldump     = fetch(:mysqldump, "mysqldump")
      dump_options  = fetch(:dump_options, "--single-transaction --create-options --quick")

      run "#{try_sudo} #{mysqldump} #{dump_options} --opt -h#{db_remote_host} -u#{db_remote_user} -p#{db_remote_pass} #{db_remote_name} | gzip -c --best > #{deploy_to}/#{db_remote_name}.sql.gz"
    end

    desc "Download remotely created MySQL dumpfile to local machine via SCP"
    task :remote_download, :roles => :db do
      download "#{deploy_to}/#{db_remote_name}.sql.gz", "#{db_remote_name}.sql.gz", :via => :scp
    end
  end

  # --------------------------------------------
  # Backup tasks
  # --------------------------------------------
  namespace :backup do
    desc "Perform a backup of web and database files"
    task :default do
      deploy.setup_backup
      db
      web
      cleanup
    end

    desc <<-DESC
      Requires the rsync package to be installed.

      Performs a file-level backup of the application and any assets \
      from the shared directory that have been symlinked into the \
      applications root or sub-directories.

      You can specify which files or directories to exclude from being \
      backed up (i.e., log files, sessions, cache) by setting the \
      :backup_exclude variable
          set(:backup_exclude) { [ "var/", "tmp/", logs/debug.log ] }
    DESC
    task :web, :roles => :web do
      if previous_release
        logger.info "Backing up web files (user uploaded content and previous release)"

        if !backup_exclude.nil? && !backup_exclude.empty?
          logger.debug "processing backup exclusions..."
          backup_exclude.each do |pattern|
            exclude_string << "--exclude '#{pattern}' "
          end
          logger.debug "Exclude string = #{exclude_string}"
        end

        # Copy the previous release to the /tmp directory
        logger.debug "Copying previous release to the #{tmp_backups_path}/#{release_name} directory"
        run "rsync -avzrtpL #{exclude_string} #{current_path}/ #{tmp_backups_path}/#{release_name}/"

        # --------------------------
        # SET/RESET PERMISSIONS
        # --------------------------
        group_writable = fetch(:group_writable, true)
        file_permissions = group_writable ? 775 : 755;
        dir_permissions = group_writable ? 664 : 644;

        set_perms_dirs("#{tmp_backups_path}/#{release_name}", file_permissions)
        set_perms_files("#{tmp_backups_path}/#{release_name}", dir_permissions)

        # create the tarball of the previous release
        set :archive_name, "release_B4_#{release_name}.tar.gz"
        logger.debug "Creating a Tarball of the previous release in #{backups_path}/#{archive_name}"
        run "cd #{tmp_backups_path} && tar -cvpf - ./#{release_name}/ | gzip -c --best > #{backups_path}/#{archive_name}"

        # remove the the temporary copy
        logger.debug "Removing the tempory copy"
        run "rm -rf #{tmp_backups_path}/#{release_name}"
      else
        logger.important "no previous release to backup; backup of files skipped"
      end
    end

    desc "Perform a backup of database files"
    task :db, :roles => :db do
      if previous_release
        mysqldump     = fetch(:mysqldump, "mysqldump")
        dump_options  = fetch(:dump_options, "--single-transaction --create-options --quick")

        logger.info "Backing up the database now and putting dump file in the previous release directory"
        # define the filename (include the current_path so the dump file will be within the directory)
        filename = "#{current_path}/#{dbname}_dump-#{Time.now.to_s.gsub(/ /, "_")}.sql.gz"
        # dump the database for the proper environment
        run "#{mysqldump} #{dump_options} -u #{dbuser} -p #{dbname} | gzip -c --best > #{filename}" do |ch, stream, out|
            ch.send_data "#{dbpass}\n" if out =~ /^Enter password:/
        end
      else
        logger.important "no previous release to backup to; backup of database skipped"
      end
    end

    desc <<-DESC
      Clean up old backups. By default, the last 10 backups are kept on each \
      server (though you can change this with the keep_backups variable). All \
      other backups are removed from the servers. By default, this \
      will use sudo to clean up the old backups, but if sudo is not available \
      for your environment, set the :use_sudo variable to false instead.
    DESC
    task :cleanup, :except => { :no_release => true } do
      count = fetch(:keep_backups, 10).to_i
      if count >= backups.length
        logger.important "no old backups to clean up"
      else
        logger.info "keeping #{count} of #{backups.length} backups"

        archives = (backups - backups.last(count)).map { |backup|
          File.join(backups_path, backup) }.join(" ")

        # fix permissions on the the files and directories before removing them
        group_writable = fetch(:group_writable, true)
        file_permissions = group_writable ? 775 : 755;
        dir_permissions = group_writable ? 664 : 644;

        archives.split(" ").each do |backup|
          set_perms_dirs("#{backup}", dir_permissions)
          set_perms_files("#{backup}", file_permissions)
        end

        try_sudo "rm -rf #{archives}"
      end
    end
  end

  # --------------------------------------------
  # Remote File/Directory test tasks
  # --------------------------------------------
  namespace :remote do
    namespace :file do
      desc "Test: Task to test existence of missing file"
      task :missing do
        if remote_file_exists?('/dev/mull')
          logger.info "FAIL - Why does the '/dev/mull' path exist???"
        else
          logger.info "GOOD - Verified the '/dev/mull' path does not exist!"
        end
      end

      desc "Test: Task used to test existence of a present file"
      task :exists do
        if remote_file_exists?('/dev/null')
          logger.info "GOOD - Verified the '/dev/null' path exists!"
        else
          logger.info "FAIL - WHAT happened to the '/dev/null' path???"
        end
      end
    end

    namespace :dir do
      desc "Test: Task to test existence of missing dir"
      task :missing do
        if remote_dir_exists?('/etc/fake_dir')
          logger.info "FAIL - Why does the '/etc/fake_dir' dir exist???"
        else
          logger.info "GOOD - Verified the '/etc/fake_dir' dir does not exist!"
        end
      end

      desc "Test: Task used to test existence of an existing directory"
      task :exists do
        if remote_dir_exists?('/etc')
          logger.info "GOOD - Verified the '/etc' dir exists!"
        else
          logger.info "FAIL - WHAT happened to the '/etc' dir???"
        end
      end
    end
  end
end
