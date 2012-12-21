# Capistrano::Demonz

Capistrano recipes developed for use by [Demonz Media](http://demonzmedia.com).

**Current version:** 0.0.5

Only includes a Drupal recipe for now.

## Installation

Make sure you have ruby and RubyGems installed, then run (you may need to prefix this with `sudo`):

    $ gem install capistrano-demonz

## Usage

In your Drupal application's directory, run:

    $ gem capify .

This will create two files, a `Capfile` in the root and `config/deploy.rb`.

Open up the `Capfile` and replace it with:

    require 'rubygems'
    require 'railsless-deploy'
    load 'deploy' if respond_to?(:namespace)
    load 'config/deploy'
    require 'capistrano/ext/multistage'
    require 'demonz/drupal'

Open up `deploy.rb` and replace with:

    set :stages, %w(production staging)
    set :default_stage, "staging"
    set :application, "mysite.com"

    set :repository,  "git@github.com:demonz/mydrupalproject.git"
    set :scm, :git
    set :branch, ""
    set :deploy_via, :remote_cache
    set :deploy_to, "/var/www/#{application}"
    # @see Demonz Base Stack/Configure user permissions
    set :group, 'www-pub'
    set :group_writable, true

    # Set to true if boost (the Drupal module) is installed
    set :uses_boost, false

    # For automated SASS compilation
    set :uses_sass, false
    set :themes, []

    set :keep_releases, 5
    set :keep_backups, 7 # only keep 3 backups (default is 10)

    # Set Excluded directories/files (relative to the application's root path)
    set(:backup_exclude) { [ "var/", "tmp/" ] }

Edit this according to your specific project. Importnant values are `:application`, `:repository`, `:branch` amongst others. It should be fairly self-explanatory.

Then, create a folder at `config/deploy` in your project's root:

    $ mkdir config/deploy

And according to the number of application stages you defined previously in `:stages`, create applicable config files. For example, in the case above:

    $ touch config/deploy/staging.rb
    $ touch config/deploy/production.rb

Then, in each of the above files, enter a variation of the following:

    server 'myserver.com', :app, :web, :primary => true
    # role :web, "mywebserver.com"
    # role :app, "mywebserver.com"
    # role :db,  "mydatabaseserver.com", :primary => true
    set :user, 'root'
    set :use_sudo, false

    set :ssh_options, {
      :forward_agent => true,
      # :keys => ["#{ENV['HOME']}/.ssh/your-ec2-key.pem"],
      :keys => [File.join(ENV["HOME"], ".ssh", "id_rsa")],
      :port => 2992
    }

Make sure to set your SSH server and user (`:user`)—if this user isn't root, set `:use_sudo` to `true`.

If you have seperate web and database servers, comment out the `server` line and uncomment each of the `role` lines. Set these to their respective servers. In Drupal's case the `role :web` and `role :app` lines should be identical.



## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
