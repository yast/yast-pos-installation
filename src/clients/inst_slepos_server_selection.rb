# encoding: utf-8

# Package:     POS Installation
# Summary:     Installation of SLEPOS packages
# Authors:	Lukas Ocilka <locilka@suse.cz>
#		Jiri Suchomel <jsuchome@suse.cz>
#
# This client should be called during 2nd stage of installation or update
# of SLES11 together with SLEPOS
module Yast
  class InstSleposServerSelectionClient < Client
    def main
      Yast.import "UI"
      Yast.import "Pkg"
      textdomain "slepos-installation"

      Yast.import "GetInstArgs"
      Yast.import "Label"
      Yast.import "Mode"
      Yast.import "PackageCallbacks"
      Yast.import "PackagesUI"
      Yast.import "Popup"
      Yast.import "POSInstallation"
      Yast.import "Report"
      Yast.import "Stage"
      Yast.import "Wizard"

      Builtins.y2milestone(
        "SLEPOS installation client (%1, %2)",
        Mode.mode,
        Stage.stage
      )

      Wizard.CreateDialog if Mode.normal

      @list_of_patterns = [
        {
          # TRANSLATORS: A name of pattern, used as CheckBox label
          "label" => _(
            "Admin Server (AS)"
          ),
          "name"  => "SLEPOS_Server_Admin",
          "icon"  => "/usr/share/icons/hicolor/32x32/apps/yast-host.png"
        },
        {
          # TRANSLATORS: A name of pattern, used as CheckBox label
          "label" => _(
            "Branch Server (BS)"
          ),
          "name"  => "SLEPOS_Server_Branch",
          "icon"  => "/usr/share/icons/hicolor/32x32/apps/yast-network.png"
        },
        {
          # TRANSLATORS: A name of pattern, used as CheckBox label
          "label" => _(
            "Image Server (IS)"
          ),
          "name"  => "SLEPOS_Image_Server",
          "icon"  => "/usr/share/icons/hicolor/32x32/apps/yast-sw_source.png"
        }
      ]

      # initialize source and target (if already done, nothing happens)
      if !GetInstArgs.going_back
        Pkg.SourceStartManager(true)
        Pkg.TargetInit("/", false)
      end


      @map_of_patterns = Builtins.listmap(@list_of_patterns) do |pattern|
        { Ops.get_string(pattern, "name", "") => pattern }
      end

      @install_patterns = VBox()
      @migrate_patterns = VBox()

      Builtins.foreach(@list_of_patterns) do |one_pattern|
        name = Ops.get(one_pattern, "name", "")
        @install_patterns = Builtins.add(
          @install_patterns,
          CreateCheckBoxTerm(
            Ops.add("install_", name),
            Ops.get(one_pattern, "label", ""),
            Ops.get(one_pattern, "icon", "")
          )
        )
        @install_patterns = Builtins.add(@install_patterns, VSpacing(0.7))
        if Ops.get_boolean(POSInstallation.detected, name, false)
          @migrate_patterns = Builtins.add(
            @migrate_patterns,
            CreateCheckBoxTerm(
              Ops.add("migrate_", name),
              Ops.get(one_pattern, "label", ""),
              Ops.get(one_pattern, "icon", "")
            )
          )
          @migrate_patterns = Builtins.add(@migrate_patterns, VSpacing(0.7))
        end
      end


      if Ops.greater_than(Builtins.size(@migrate_patterns), 0)
        @migrate_patterns = HBox(
          HSpacing(3),
          # frame label
          Frame(_("Data Migration"), VBox(VSpacing(0.7), @migrate_patterns)),
          HSpacing(3)
        )
      end

      @cont = VBox(
        @migrate_patterns,
        VSpacing(),
        HBox(
          HSpacing(3),
          # frame label
          Frame(
            _("Pattern Installation"),
            VBox(VSpacing(0.7), @install_patterns)
          ),
          HSpacing(3)
        )
      )

      Wizard.SetContentsButtons(
        # TRANSLATORS: Dialog caption
        _("Server Pattern Selection"),
        @cont,
        # help text
        _(
          "<p>Choose the pattern which you want to install. You may disable the migration\nof the relevant deployment (Admin Server, Branch Server or Image Server).</p>"
        ) +
          # help text, cont.
          _("<p>The installation will start upon pressing <b>Next</b>.</p>"),
        Label.BackButton,
        Label.NextButton
      )

      Wizard.SetTitleIcon("yast-software")

      InitSelected()

      @ret = nil

      @dialog_ret = :next

      while true
        @ret = UI.UserInput

        if Ops.is_string?(@ret)
          @sret = Builtins.tostring(@ret)
          if Builtins.substring(@sret, 0, 8) == "migrate_"
            @rest = Builtins.substring(@sret, 8)
            # migrated pattern must be installed
            UI.ChangeWidget(Id(Ops.add("install_", @rest)), :Value, true)
            UI.ChangeWidget(
              Id(Ops.add("install_", @rest)),
              :Enabled,
              UI.QueryWidget(Id(@ret), :Value) != true
            )
          end
        elsif @ret == :next
          @dialog_ret = :next
          if HandleSelected()
            break
          else
            next
          end
        elsif @ret == :back
          @dialog_ret = :back
          break
        elsif @ret == :abort || @ret == :cancel
          if Popup.ConfirmAbort(:incomplete)
            @dialog_ret = :abort
            break
          else
            next
          end
        else
          Builtins.y2error("Unhandled ret: %1", @ret)
        end
      end

      Wizard.CloseDialog if Mode.normal

      @dialog_ret
    end

    # check which configuration is detected by slepos scripts and
    # mark appropriate patterns for migration
    def InitSelected
      Builtins.foreach(@list_of_patterns) do |one_pattern|
        name = Ops.get(one_pattern, "name", "")
        if Ops.get_boolean(POSInstallation.detected, name, false)
          Builtins.y2milestone("checking pattern %1 for migration...", name)
          UI.ChangeWidget(Id(Ops.add("migrate_", name)), :Value, true)
          UI.ChangeWidget(Id(Ops.add("install_", name)), :Value, true)
          # do not let user unselect migrated pattern
          UI.ChangeWidget(Id(Ops.add("install_", name)), :Enabled, false)
        end
      end

      nil
    end

    def manual_package_selection
      ret = PackagesUI.RunPatternSelector

      # user didn't accept the pattern selector
      if ret != :accept
        return false
      else
        Pkg.PkgCommit(0)
        return true
      end
    end

    # Check which patterns are selected for installation and migration,
    # install required ones and save info about migration
    def HandleSelected
      to_install = []

      for_migration = {}

      Builtins.foreach(@list_of_patterns) do |one_pattern|
        name = Ops.get(one_pattern, "name", "")
        if UI.QueryWidget(Id(Ops.add("install_", name)), :Value) == true
          Builtins.y2internal("pattern %1 selected for installation", name)
          to_install = Builtins.add(to_install, name)
        end
        if UI.WidgetExists(Id(Ops.add("migrate_", name))) &&
            UI.QueryWidget(Id(Ops.add("migrate_", name)), :Value) == true
          Builtins.y2internal("pattern %1 selected for migration", name)
          Ops.set(for_migration, name, true)
        end
      end
      # filter out already installed (FIXME???)
      # to_install	= filter (string pattern, to_install, {
      #     list <map <string,any> > current_pattern_state = Pkg::ResolvableProperties (pattern, `pattern, "");
      # });

      failed_patterns = []
      Builtins.foreach(to_install) do |pattern|
        if Pkg.ResolvableInstall(pattern, :pattern) == false
          Builtins.y2error("Can't select pattern %1", pattern)
          failed_patterns = Builtins.add(failed_patterns, pattern)
        end
      end
      if failed_patterns != []
        labels = Builtins.mergestring(Builtins.maplist(failed_patterns) do |pat|
          Ops.get_string(@map_of_patterns, [pat, "label"], pat)
        end, "\n")
        # TRANSLATORS: Error message, %1 is replaced with the name of the pattern
        Report.Error(
          Builtins.sformat(
            _(
              "Unable to select patterns:\n" +
                "%1\n" +
                "Starting manual selection."
            ),
            labels
          )
        )
        return manual_package_selection
      end
      if Pkg.PkgSolve(false) == true
        Pkg.PkgCommit(0)
      else
        # TRANSLATORS: Error message
        Report.Error(
          _(
            "An error occurred in pattern selection\nStarting manual selection."
          )
        )
        return manual_package_selection
      end

      # update the migrate info for the next dialog
      POSInstallation.for_migration = deep_copy(for_migration)

      true
    end

    def CreateCheckBoxTerm(pattern_name, pattern_label, pattern_icon)
      HBox(
        HSpacing(2),
        pattern_icon == "" ? Empty() : Image(pattern_icon, ""),
        HSpacing(2),
        Left(CheckBox(Id(pattern_name), Opt(:notify), pattern_label))
      )
    end
  end
end

Yast::InstSleposServerSelectionClient.new.main
