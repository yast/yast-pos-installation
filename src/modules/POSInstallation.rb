# encoding: utf-8

# Package:	POS Installation
# Summary:	Data used during POS installation or upgrade
# Authors:	Jiri Suchomel <jsuchome@suse.cz>
require "yast"

module Yast
  class POSInstallationClass < Module
    def main
      textdomain "slepos-installation"

      # name of SLEPOS script for detecting deployment type
      @get_type_cmd = "/usr/lib/SLEPOS/migration/slepos11_get_deploy_type.sh"

      # name of SLEPOS script for data migration
      @migrate_cmd = "/usr/lib/SLEPOS/migration/slepos_migrate.sh"

      # Path to BS configuration file
      @bs_config_file = "/etc/SLEPOS/branchserver.conf"

      # BS initialization script
      @bs_init_cmd = "/usr/sbin/posInitBranchserver"

      # Path to synchronization script
      @sync_cmd = "/usr/sbin/possyncimages"

      # Detection if offline initialization of BS is running
      # (used during firstboot only)
      @offline_initialization = false

      # Offline initialization file
      @offline_file = ""

      # path to file or directory with data for detection script
      @file_path = ""
      @dir_path = ""

      # Path to SuSE-release file of the old system (before update)
      @suse_release_path = ""

      # what kind of SLEPOS installation was detected on the system
      @detected = {
        "SLEPOS_Server_Admin"  => true,
        "SLEPOS_Server_Branch" => false,
        "SLEPOS_Image_Server"  => true
      }

      # what kind of SLEPOS parts should be migrated
      # (may be smaller set than the detected one)
      @for_migration = {
        "SLEPOS_Server_Admin"  => true,
        "SLEPOS_Server_Branch" => false,
        "SLEPOS_Image_Server"  => true
      }

      # Values that should be filled during BS online initialization
      # (usable during firstboot stage)
      @online_initialization_settings = {
        "ALL_LDAPHOST"       => "",
        "BRANCH_LDAPBASE"    => "",
        "POS_ADMIN_PASSWORD" => ""
      }

      # Which way users wants to synchronize
      # Possible values: `sync, `sync_local, `no_sync, `none (not yet initialized)
      @sync_selection = :none
    end

    publish :variable => :get_type_cmd, :type => "string"
    publish :variable => :migrate_cmd, :type => "string"
    publish :variable => :bs_config_file, :type => "string"
    publish :variable => :bs_init_cmd, :type => "string"
    publish :variable => :sync_cmd, :type => "string"
    publish :variable => :offline_initialization, :type => "boolean"
    publish :variable => :offline_file, :type => "string"
    publish :variable => :file_path, :type => "string"
    publish :variable => :dir_path, :type => "string"
    publish :variable => :suse_release_path, :type => "string"
    publish :variable => :detected, :type => "map"
    publish :variable => :for_migration, :type => "map"
    publish :variable => :online_initialization_settings, :type => "map <string, string>"
    publish :variable => :sync_selection, :type => "symbol"
  end

  POSInstallation = POSInstallationClass.new
  POSInstallation.main
end
