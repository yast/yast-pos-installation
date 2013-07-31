# encoding: utf-8

# Package:     POS Installation
# Summary:     Initialization of current SLEPOS status
# Authors:     Jiri Suchomel <jsuchome@suse.cz>
#
#
# This client should be called during 2nd stage of installation or update
# of SLES11 together with SLEPOS
module Yast
  class InstSleposDetectionClient < Client
    def main
      Yast.import "UI"
      textdomain "slepos-installation"

      Yast.import "Directory"
      Yast.import "FileUtils"
      Yast.import "Label"
      Yast.import "Mode"
      Yast.import "Popup"
      Yast.import "POSInstallation"
      Yast.import "Stage"
      Yast.import "String"
      Yast.import "Wizard"

      Builtins.y2milestone(
        "SLEPOS detection client (%1, %2)",
        Mode.mode,
        Stage.stage
      )

      @dialog_ret = :auto

      if Mode.update
        if FileUtils.Exists("/root/inst-sys/imported/SuSE-release")
          POSInstallation.suse_release_path = "/root/inst-sys/imported/SuSE-release"
          Builtins.y2milestone("old SuSE-release found")
        end
      end

      Wizard.CreateDialog if Mode.normal


      # there are 2 possible situations:
      # 1. normal SLES11 installation
      # 2. update from SLE10

      # FIXME dat si pozor, at nedelem nektere veci opakovane... (Next & Back):  if (!GetInstArgs::going_back ())

      # regular installation of SLES11
      if !Mode.update
        # path to file or directory with data for detection script
        @file_path = POSInstallation.file_path
        @dir_path = POSInstallation.dir_path

        # FIXME maybe move this part to standalone client...

        # ask for nlpos9 data... :
        # zde to probiha podobneji jako u migrace sleposu10, jen je tu navic moznost
        # predat konfiguraci offline BS, ktera slouzi pro konfiguraci BS na slepos11
        # pro offline ldap, detekci tohoto zpusobu si jiz obstara sam migracni
        # skript, je treba jen dopsat do yast komentare text navic pro tuto moznost.

        @cont = RadioButtonGroup(
          Id("migration_data"),
          Opt(:notify),
          VBox(
            Left(
              # radio button label
              RadioButton(
                Id("rb_file"),
                Opt(:notify),
                _("Path to archive file"),
                @file_path != ""
              )
            ),
            HBox(
              HSpacing(3),
              HBox(
                InputField(Id("file_path"), Opt(:hstretch), "", @file_path),
                PushButton(Id("browse_file"), Label.BrowseButton)
              )
            ),
            VSpacing(),
            Left(
              RadioButton(
                Id("rb_dir"),
                Opt(:notify),
                _("Path to backup directory"),
                @dir_path != ""
              )
            ),
            HBox(
              HSpacing(3),
              HBox(
                InputField(Id("dir_path"), Opt(:hstretch), "", @dir_path),
                PushButton(Id("browse_dir"), Label.BrowseButton)
              )
            )
          )
        )
        @cont = HBox(HSpacing(3), @cont, HSpacing(3))

        # help text
        @help = _(
          "<p>In case you are not migrating from NLPOS9 and this is a new SLEPOS 11          \ninstallation continue by clicking <b>Next</b>.</p>"
        ) +
          # help text, cont.
          _(
            "<p>To migrate from NLPOS9 insert the backed up archive file or backup directory   \n" +
              "into the corresponding input box and continue by clicking <b>Next</b>.\n" +
              "The backup file or directory is prepared beforehand using the script <tt>nlpos9_backup_data.sh</tt>\n" +
              "which can be found on the SLEPOS CD in the directory <tt>/migration/</tt> or in the directory\n" +
              "<tt>/usr/lib/SLEPOS/migration</tt> of <tt>POS_Migration.rpm</tt> package.</p>"
          )

        # Dialog caption
        Wizard.SetContentsButtons(
          _("Entering Migration Data"),
          @cont,
          @help,
          Label.BackButton,
          Label.NextButton
        )
        Wizard.SetTitleIcon("yast-software")

        UI.ChangeWidget(Id("file_path"), :Enabled, @file_path != "")
        UI.ChangeWidget(Id("browse_file"), :Enabled, @file_path != "")
        UI.ChangeWidget(Id("dir_path"), :Enabled, @dir_path != "")
        UI.ChangeWidget(Id("browse_dir"), :Enabled, @dir_path != "")

        @ret2 = :next
        while true
          @ret2 = UI.UserInput

          if @ret2 == "rb_file" || @ret2 == "rb_dir"
            UI.ChangeWidget(Id("file_path"), :Enabled, @ret2 == "rb_file")
            UI.ChangeWidget(Id("browse_file"), :Enabled, @ret2 == "rb_file")
            UI.ChangeWidget(Id("dir_path"), :Enabled, @ret2 == "rb_dir")
            UI.ChangeWidget(Id("browse_dir"), :Enabled, @ret2 == "rb_dir")
          end
          if @ret2 == "browse_file"
            # file location popup label
            @selected = UI.AskForExistingFile(@file_path, "", _("Path to File"))
            if @selected != nil
              @file_path = @selected
              UI.ChangeWidget(Id("file_path"), :Value, @file_path)
            end
          end
          if @ret2 == "browse_dir"
            # directory location popup label
            @selected = UI.AskForExistingDirectory(
              @dir_path,
              _("Path to Directory")
            )
            if @selected != nil
              @dir_path = @selected
              UI.ChangeWidget(Id("dir_path"), :Value, @dir_path)
            end
          end
          if @ret2 == :next
            # FIXME validate
            # reset the possible value of the string which won't be used
            if UI.QueryWidget(Id("migration_data"), :Value) == "rb_file"
              @file_path = Convert.to_string(
                UI.QueryWidget(Id("file_path"), :Value)
              )
              @dir_path = ""
            else
              @dir_path = Convert.to_string(
                UI.QueryWidget(Id("dir_path"), :Value)
              )
              @file_path = ""
            end

            POSInstallation.dir_path = @dir_path
            POSInstallation.file_path = @file_path
            @dialog_ret = :next
            break
          elsif @ret2 == :back
            @dialog_ret = :back
            break
          elsif @ret2 == :abort || @ret2 == :cancel
            if Popup.ConfirmAbort(:incomplete)
              @dialog_ret = :abort
              break
            else
              next
            end
          end
        end
      end
      # the rest of workflow is common to SLES11 installation and update from SLES10

      # Now, SLEPOS slepos11_get_deploy_type.sh script should detect the type of installation:
      # 	AS (Admin Server),
      # 	BS (Branch Server)
      # 	IS (Image Server)
      #
      # 'slepos11_get_deploy_type.sh [<-f file.tar.gz>|<-d backup_directory>] [-o SuSE-release]'
      # return: sum of (AS:1, BS:2, IS:4)

      @get_type_cmd = POSInstallation.get_type_cmd

      # on installed system, find the script in y2update (bnc#517314)
      if Mode.mode == "installation" && Stage.stage == "normal"
        @get_type_cmd = Ops.add("/y2update/all/", @get_type_cmd)
      end

      if POSInstallation.file_path != ""
        @get_type_cmd = Ops.add(
          Ops.add(@get_type_cmd, " -f "),
          POSInstallation.file_path
        )
      elsif POSInstallation.dir_path != ""
        @get_type_cmd = Ops.add(
          Ops.add(@get_type_cmd, " -d "),
          POSInstallation.dir_path
        )
      end

      if POSInstallation.suse_release_path != ""
        @get_type_cmd = Ops.add(
          Ops.add(@get_type_cmd, " -o "),
          POSInstallation.suse_release_path
        )
      end

      @get_type_cmd = String.Quote(@get_type_cmd)

      # detection should be fast, no need for progress and/or background
      @out = Convert.to_map(
        SCR.Execute(path(".target.bash_output"), @get_type_cmd)
      )
      @ret = 0
      if Ops.get_string(@out, "stderr", "") == "" &&
          Ops.greater_than(Ops.get_integer(@out, "exit", 0), 0) &&
          Ops.less_than(Ops.get_integer(@out, "exit", 0), 8)
        @ret = Ops.get_integer(@out, "exit", 0)
      end

      Builtins.y2milestone("output of '%1': %2", @get_type_cmd, @out)

      # reset the map with detected servers...
      @detected = {}

      if Ops.bitwise_or(@ret, 1) == @ret
        Ops.set(@detected, "SLEPOS_Server_Admin", true)
      end
      if Ops.bitwise_or(@ret, 2) == @ret
        Ops.set(@detected, "SLEPOS_Server_Branch", true)
      end
      if Ops.bitwise_or(@ret, 4) == @ret
        Ops.set(@detected, "SLEPOS_Image_Server", true)
      end

      # ... and save new one
      POSInstallation.detected = deep_copy(@detected)

      Wizard.CloseDialog if Mode.normal

      deep_copy(@dialog_ret)
    end
  end
end

Yast::InstSleposDetectionClient.new.main
