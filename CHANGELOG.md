**Current version:** 0.0.14

## Changes ##
### 0.0.14 ###
* Moved changelog into CHANGELOG.md
* Update script ('sites/all/scripts/{release}/update.sh') is now executable by owner
* Release name ('site_release_name') is now set properly.
* Added build script.

### 0.0.13 ###
* Fixes stupid issue where 'chmod' wasn't included in previous fix.

### 0.0.12 (yanked) ###
* Fixed issue where update scripts weren't executable by the group.

### 0.0.11 ###
* Fixed 'current' symlink deletion in deploy:delete_release.

### 0.0.10 ###
* Fixed issue where incorrect database names were being generated.

### 0.0.9 ###
* Release name is now set in a Drupal variable ('site_release_name') post-migrate.

### 0.0.8 ###
* Added 'deploy:delete_release' for the Drupal recipe, lets you remove a specific release (and cleanup as required). Run with (replace 'MYRELEASE'):

    $ cap deploy:delete_release RELEASE="MYRELEASE"

### 0.0.6/0.0.7
* Fixed a number of bugs and default settings issues.
* Added automated Compass (SASS) compilation

### 0.0.5
* Initial stable release

Only includes a Drupal recipe for now.
