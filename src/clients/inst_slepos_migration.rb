# encoding: utf-8

# Package:     POS Installation
# Summary:     Migration of old SLEPOS data
# Authors:	Jiri Suchomel <jsuchome@suse.cz>
#
# This client should be called during 2nd stage of installation or update
# of SLES11 together with SLEPOS
module Yast
  class InstSleposMigrationClient < Client
    def main
      Yast.import "UI"
      textdomain "slepos-installation"

      Yast.import "Directory"
      Yast.import "GetInstArgs"
      Yast.import "Label"
      Yast.import "Mode"
      Yast.import "Popup"
      Yast.import "POSInstallation"
      Yast.import "Stage"
      Yast.import "String"
      Yast.import "Wizard"

      Builtins.y2milestone(
        "SLEPOS migration client (%1, %2)",
        Mode.mode,
        Stage.stage
      )

      @dialog_ret = :auto

      if Ops.less_than(Builtins.size(POSInstallation.for_migration), 1)
        Builtins.y2milestone("nothing to migrate: skipping...")
        return :auto
      end
      if GetInstArgs.going_back
        Builtins.y2milestone("nothing to do when going back...")
        return :back
      end


      Wizard.CreateDialog if Mode.normal

      @cont = HBox(
        HSpacing(3),
        VBox(
          VSpacing(),
          ReplacePoint(
            Id(:rp_current),
            # progress bar label
            ProgressBar(Id(:current_progress), _("Migration Step Progress"))
          ),
          VSpacing(0.2),
          ReplacePoint(
            Id(:rp_total),
            # progress bar label
            ProgressBar(Id(:total_progress), _("Migration Progress"))
          ),
          VSpacing(),
          ReplacePoint(Id(:rp_label), Label(""))
        ),
        HSpacing(3)
      )

      @process_id = -1
      @log_file = Ops.add(
        Convert.to_string(SCR.Read(path(".target.tmpdir"))),
        "/slepos_migration.log"
      )
      @tasks_passed = -1
      @tasks = 0

      Wizard.SetContentsButtons(
        # TRANSLATORS: Dialog caption
        _("POS Data Migration"),
        @cont,
        # TRANSLATORS: Dialog help
        _(
          "<p>The progress bar indicates the separate migration steps. The complete log\nof the migration is saved and will be shown in case of migration failure.</p>"
        ),
        Label.BackButton,
        Label.NextButton
      )


      Wizard.SetTitleIcon("yast-software")
      Wizard.DisableNextButton
      Wizard.DisableBackButton
      # FIXME Abort button is disabled at this time?

      @migrate_cmd = POSInstallation.migrate_cmd

      if POSInstallation.file_path != ""
        @migrate_cmd = Ops.add(
          Ops.add(@migrate_cmd, " -f "),
          POSInstallation.file_path
        )
      elsif POSInstallation.dir_path != ""
        @migrate_cmd = Ops.add(
          Ops.add(@migrate_cmd, " -d "),
          POSInstallation.dir_path
        )
      end

      if POSInstallation.suse_release_path != ""
        @migrate_cmd = Ops.add(
          Ops.add(@migrate_cmd, " -o "),
          POSInstallation.suse_release_path
        )
      end

      @deploy_type = 0
      if Ops.get_boolean(
          POSInstallation.for_migration,
          "SLEPOS_Server_Admin",
          false
        )
        @deploy_type = 1
      end
      if Ops.get_boolean(
          POSInstallation.for_migration,
          "SLEPOS_Server_Branch",
          false
        )
        @deploy_type = Ops.add(@deploy_type, 2)
      end
      if Ops.get_boolean(
          POSInstallation.for_migration,
          "SLEPOS_Image_Server",
          false
        )
        @deploy_type = Ops.add(@deploy_type, 4)
      end

      @migrate_cmd = Builtins.sformat("%1 -t %2", @migrate_cmd, @deploy_type)
      @migrate_cmd = Ops.add(Ops.add(@migrate_cmd, " -l "), @log_file)
      @migrate_cmd = String.Quote(@migrate_cmd)

      Builtins.y2milestone("migrate command: '%1'", @migrate_cmd)

      @process_id = Convert.to_integer(
        SCR.Execute(path(".process.start_shell"), @migrate_cmd)
      )
      @ret = nil

      # error log
      @details = ""

      while true
        @ret = UI.PollInput

        if SCR.Read(path(".process.running"), @process_id) != true
          update_progress

          @status = Convert.to_integer(
            SCR.Read(path(".process.status"), @process_id)
          )
          if @status != 0
            UI.ReplaceWidget(
              Id(:rp_label),
              HBox(
                # text label (action result)
                Left(Label(_("Migration process failed."))),
                # push button label
                PushButton(Id(:details), _("Show details..."))
              )
            )
            @details = Convert.to_string(
              SCR.Read(path(".target.string"), @log_file)
            )
            @details = "" if @details == nil
          else
            # all progress bars to end
            UI.ChangeWidget(Id(:current_progress), :Value, 100)
            UI.ChangeWidget(Id(:total_progress), :Value, @tasks)

            UI.ReplaceWidget(
              Id(:rp_label),
              # text label (action result)
              Left(Label(_("Migration was successfull.")))
            )
          end
          Wizard.EnableNextButton
          Wizard.EnableBackButton
          break
        else
          update_progress
        end
        if @ret == :abort || @ret == :cancel
          # yes/no popup FIXME
          if Popup.YesNo(_("Cancel migration?"))
            SCR.Execute(path(".process.kill"), @process_id, 15)
            Builtins.sleep(100)
            SCR.Execute(path(".process.kill"), @process_id)
            break
          end
        end
        Builtins.sleep(500)
      end

      while true
        @ret = UI.UserInput
        if @ret == :details
          UI.OpenDialog(
            Opt(:decorated),
            HBox(
              HSpacing(1.5),
              VBox(
                HSpacing(80),
                VSpacing(),
                # log view label
                LogView(Id(:details), _("Error log"), 12, 0),
                VSpacing(),
                PushButton(Label.OKButton),
                VSpacing(0.2)
              ),
              HSpacing(1.5)
            )
          )
          UI.ChangeWidget(Id(:details), :Value, @details)
          UI.UserInput
          UI.CloseDialog
          next
        end
        if @ret == :next
          @dialog_ret = :next
          break
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
        end
      end

      Wizard.CloseDialog if Mode.normal

      @dialog_ret
    end

    # read the migrate script output and show progress
    def update_progress
      line = Convert.to_string(
        SCR.Read(path(".process.read_line"), @process_id)
      )
      if line != nil && line != ""
        Builtins.y2internal("new line: '%1'", line)

        # read total number of tasks
        if Builtins.substring(line, 0, 7) == "titles:"
          l = Builtins.splitstring(line, " ")
          @tasks = Builtins.tointeger(Ops.get(l, 1, "0"))
          @tasks = 0 if @tasks == nil
          UI.ReplaceWidget(
            Id(:rp_total),
            # progress bar label
            ProgressBar(Id(:total_progress), _("Migration Progress"), @tasks)
          )
        # update current task label
        elsif Builtins.substring(line, 0, 6) == "title:"
          l = Builtins.splitstring(line, " ")
          l = Builtins.remove(l, 0)
          current = Builtins.mergestring(l, " ")
          UI.ReplaceWidget(
            Id(:rp_current),
            # progress bar label
            ProgressBar(Id(:current_progress), current, 100)
          )
          @tasks_passed = Ops.add(@tasks_passed, 1)
          UI.ChangeWidget(Id(:total_progress), :Value, @tasks_passed)
          UI.ChangeWidget(Id(:current_progress), :Value, 0)
        elsif Builtins.substring(line, 0, 9) == "position:"
          l = Builtins.splitstring(line, " ")
          pos = Builtins.tointeger(
            Builtins.deletechars(Ops.get(l, 1, "0"), "% ")
          )
          pos = 0 if pos == nil
          UI.ChangeWidget(Id(:current_progress), :Value, pos)
        end
      end
      err = Convert.to_string(
        SCR.Read(path(".process.read_line_stderr"), @process_id)
      )
      Builtins.y2warning("error output: '%1'", err) if err != nil && err != ""

      nil
    end
  end
end

Yast::InstSleposMigrationClient.new.main
