# Capistrano::Demonz

Capistrano recipes developed for use by [Demonz Media](http://demonzmedia.com).

## Installation

Make sure you have ruby and RubyGems installed, then run (you may need to prefix this with `sudo`):

    $ gem install capistrano-demonz

## Usage
### Installation of settings files
This is to be run once per project, to set up the capistrano-demonz speficic data including environment information (UAT, Live server...)

In your Drupal application's directory, run:

    $ capify .

This will create two files, a `Capfile` in the root and `config/deploy.rb`.

Open up the `Capfile` and replace it with:

```ruby
require 'rubygems'
require 'railsless-deploy'
load 'deploy' if respond_to?(:namespace)
load 'config/deploy'
require 'capistrano/ext/multistage'
require 'demonz/drupal'
```

Open up `config/deploy.rb` and replace with:

```ruby
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
```

Edit this according to your specific project. Importnant values are `:application`, `:repository`, `:branch` amongst others. It should be fairly self-explanatory.

Then, create a folder at `config/deploy` in your project's root:

    $ mkdir config/deploy

And according to the number of application stages you defined previously in `:stages`, create applicable config files. For example, in the case above:

    $ touch config/deploy/staging.rb
    $ touch config/deploy/production.rb

Then, in each of the above files, enter a variation of the following:

```ruby
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
```

Make sure to set your SSH server and user (`:user`)—if this user isn't root, set `:use_sudo` to `true`.

If you have seperate web and database servers, comment out the `server` line and uncomment each of the `role` lines. Set these to their respective servers. In Drupal's case the `role :web` and `role :app` lines should be identical.

Once all of that's done, run the following command (**note: this will create a folder on the remote server at /var/www/mysite.com**, make sure this doesn't conflict with anything):

    $ cap deploy:setup

When that finishes, log on to (each of?) the remote server(s). Copy your site's files directory to `/var/www/mysite.com/shared/default/files` and put a copy of your site's settings file at `/var/www/mysite.com/shared/settings.{stage}.php`. Replace `{stage}` with the stage that this server represents (staging, production, etc.).


### Usual deployment

Run a deployment with:

    $ cap deploy -S tag="mygittag"

If you do not specify a Git tag, it will use the HEAD revision of your current repository and prompt you to create a tag.

Additionally, if this is the first deployment, the script will prompt you for a gzipped SQL dump, try and have this ready. An easy way to do this is:

    $ drush sql-dump --result-file --gzip

Deployment will run, if available, a specific release script located here `/var/www/mysite.com/releases/<mygittag>/sites/all/scripts/<mygittag>/update.sh`

To delete completely a delivered release:

    $ cap deploy:delete_release RELEASE='mygittag'
    
And that's it!

### Deploying to a different environment

If you want to deploy to production instead of staging, run:

```bash
cap production deploy -S tag="gittag"
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
