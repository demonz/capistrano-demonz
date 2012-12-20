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

# Recursively set directory permissions in a directory
def set_perms_dirs(dir_path, perm = 755)
  try_sudo "find #{dir_path} -type d -exec chmod #{perm} {} \\;"
end

# Get release history from server as string
def get_release_history(release_file)
  release_history = ""
  release_history = capture("cat #{release_file}")
  release_history
end

# Remove a particular release from history
def remove_release_from_history(release, release_file)
  release_history = capture("cat #{release_file}").split

  # Remove release if it exists
  release_history.delete_at release_history.index(release) unless release_history.index(release).nill?

  # Save
  release_history.join("\n")
  try_sudo "echo #{release_history} > #{release_file}"
end
