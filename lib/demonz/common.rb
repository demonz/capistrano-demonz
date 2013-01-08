# Prompts user entry
# Params:
# +prompt+
def text_prompt(prompt="Value: ")
  Capistrano::CLI.ui.ask(prompt) { |q| q.echo = true }
end

# Check if a local file exists
def local_file_exists?(full_path)
  File.exists?(full_path)
end

# Check if a local directory exists
def local_dir_exists?(full_path)
  File.directory?(full_path)
end

# From http://stackoverflow.com/a/1662001/356237
# Needs full remote path
def remote_file_exists?(full_path)
  'true' ==  capture("if [ -e #{full_path} ]; then echo 'true'; fi").strip
end

# Sames as above but with directories
def remote_dir_exists?(dir_path)
  'true' == capture("if [[ -d #{dir_path} ]]; then echo 'true'; fi").strip
end

# Recursively set file permissions in a directory
def set_perms_files(dir_path, perm = 644)
  try_sudo "find #{dir_path} -type f -exec chmod #{perm} {} \\;"
end
def create_database
    create_sql = <<-SQL
      CREATE DATABASE #{db_name};
    SQL

    run "mysql --user=#{db_admin_user} --password=#{db_admin_password} --execute=\"#{create_sql}\""
  end
# Recursively set directory permissions in a directory
def set_perms_dirs(dir_path, perm = 755)
  try_sudo "find #{dir_path} -type d -exec chmod #{perm} {} \\;"
end

# Get release history from server as string
def get_release_history(release_file)
  release_history = remote_file_exists?(release_file) ? capture("cat #{release_file}").strip : ''
  release_history
end

# Remove a particular release from history
def remove_release_from_history(release, release_file)
  release_history = capture("cat #{release_file}").split

  # Remove release if it exists
  release_history.delete_at release_history.index(release) unless release_history.index(release).nil?

  # Save
  release_history.join("\n")
  try_sudo "echo #{release_history} > #{release_file}"
end

# Get the database name given an application and release name
def get_db_name(application, release)
  db_name = "#{application}__#{release_name}"
  # Remove characters that may cause MySQL issues
  db_name.downcase.gsub(/([\.\-\/])/, '_')
end

# Get the regex pattern to extract details from the mysql connection string
def db_string_regex(type)
  "--#{type}='?([a-zA-Z0-9!@\#$%^&*-=+]+)'?\s"
end

# Check if a MySQL database exists
# Modified from http://www.grahambrooks.com/blog/create-mysql-database-with-capistrano/
def database_exists?(connection_string, db_name)
  exists = false

  run "#{connection_string} --execute=\"show databases;\"" do |channel, stream, data|
    exists = exists || data.include?(db_name)
  end

  exists
end

# Create a MySQL database
# From http://www.grahambrooks.com/blog/create-mysql-database-with-capistrano/
def create_database(connection_string, db_name)
  create_sql = <<-SQL
    CREATE DATABASE #{db_name};
  SQL

  run "#{connection_string} --execute=\"#{create_sql}\""
end

# Delete a MySQL database
def delete_database(connection_string, db_name)
  drop_sql = <<-SQL
    DROP DATABASE #{db_name};
  SQL

  run "#{connection_string} --execute=\"#{drop_sql}\""
end

# Set permissions for a MySQL database
# From http://www.grahambrooks.com/blog/create-mysql-database-with-capistrano/
def setup_database_permissions(connection_string, db_name)
  # We tack on a space at the end to help regex matches
  connection_string += " "

  db_admin_user = connection_string.match db_string_regex('user')
  db_admin_user = db_admin_user[1]

  db_admin_password = connection_string.match db_string_regex('password')
  db_admin_password = db_admin_password[1]

  grant_sql = <<-SQL
    GRANT ALL PRIVILEGES ON #{db_name}.* TO #{db_admin_user}@localhost IDENTIFIED BY '#{db_admin_password}';
  SQL

  run "#{connection_string} --execute=\"#{grant_sql}\""
end

# Updates the Drupal settings file with the new database name
def update_db_in_settings_file(settings_file, db_name)
  run "sed -ri \"/^[ \\t]*(#|\\*|\\/)/! s/'database' => ''/'database' => '#{db_name}'/1\" #{settings_file}"
end
