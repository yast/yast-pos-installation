# encoding: utf-8

# This client calls Branch Server initialization script and shows its output
module Yast
  class FirstbootSleposInstallationClient < Client
    def main
      Yast.import "UI"
      textdomain "slepos-firstboot"

      Yast.import "FileUtils"
      Yast.import "GetInstArgs"
      Yast.import "Mode"
      Yast.import "Popup"
      Yast.import "Stage"
      Yast.import "Wizard"

      Yast.import "POSInstallation"


      Builtins.y2milestone(
        "SLEPOS firstboot installation (%1, %2)",
        Mode.mode,
        Stage.stage
      )

      @ret = :auto

      return deep_copy(@ret) if GetInstArgs.going_back

      if !Stage.firstboot
        Builtins.y2milestone("this should only run in firstboot stage: exiting")
        return deep_copy(@ret)
      end

      @args = GetInstArgs.argmap
      @display_info = UI.GetDisplayInfo
      @text_mode = Ops.get_boolean(@display_info, "TextMode", false)
      @stdout_file = "posInitBranchserver.log-1"
      @logs_directory = "/var/log/pos"

      # find the latest log file
      @out = Convert.to_map(
        SCR.Execute(
          path(".target.bash_output"),
          Builtins.sformat(
            "ls %1/posInitBranchserver.log-* 2>/dev/null | cut -f 2 -d - | sort -nr",
            @logs_directory
          )
        )
      )
      if Ops.get_string(@out, "stdout", "") != ""
        @nums = Builtins.splitstring(Ops.get_string(@out, "stdout", ""), "\n")
        @last = Builtins.tointeger(Ops.get(@nums, 0, "0"))
        if @last != nil
          @stdout_file = Builtins.sformat(
            "posInitBranchserver.log-%1",
            Ops.add(@last, 1)
          )
        end
      end

      @cont = VBox(
        VSpacing(0.4),
        ReplacePoint(
          Id(:rp_label),
          # text label
          Label(
            Id(:label),
            _("Branch Server installation is running. Please wait...")
          )
        ),
        VBox(
          # label
          Left(Label(_("Setup script ('posInitBranchserver') output"))),
          LogView(Id(:stdout), "", 8, 0)
        )
      )

      @contents = HBox(
        HSpacing(1),
        VBox(VSpacing(0.4), @cont, VSpacing(0.4)),
        HSpacing(1)
      )

      # help text
      @help_text = _(
        "<p>Here you can see the progress of <b>Branch Server Initialization</b>.</p>\n" +
          "\n" +
          "<p>\n" +
          "The initialization could fail from different reasons. For name or DN related errors, check the value of BranchServer DN entered in previous step.</p>\n" +
          "<p>\n" +
          "For network related errors, it's probably necessary to reconfigure network settings early in the sequence. Consult SLEPOS user guide, Chapter <b>BranchServer Network configuration</b> for details.\n" +
          "</p>\n" +
          "\n" +
          "<p>\n" +
          "In case of various service errors, consult SLEPOS user guide, Chapter <b>Adding BranchServer services</b>. Then check your LDAP tree or respective scService entry.\n" +
          "</p>"
      )

      # dialog caption
      Wizard.SetContents(
        _("POS Branch Server Initialization"),
        @contents,
        @help_text,
        Ops.get_boolean(@args, "enable_back", true),
        Ops.get_boolean(@args, "enable_next", true)
      )


      @pid = -1

      UI.BusyCursor
      Wizard.DisableNextButton
      Wizard.DisableBackButton

      @cmd = Builtins.sformat("%1 -r -n 2>&1", POSInstallation.bs_init_cmd)
      if POSInstallation.offline_initialization
        @cmd = Builtins.sformat(
          "%1 -r -n -f %2 2>&1",
          POSInstallation.bs_init_cmd,
          POSInstallation.offline_file
        )
      end
      Builtins.y2milestone("Executing '%1'", @cmd)
      UI.ChangeWidget(Id(:stdout), :LastLine, Ops.add(@cmd, "\n\n"))
      @pid = Convert.to_integer(SCR.Execute(path(".process.start_shell"), @cmd))
      @exit_status = 0
      while true
        @ret = Convert.to_symbol(UI.PollInput)
        if SCR.Read(path(".process.running"), @pid) != true
          update_output
          # explicitely check the process buffer after exit (bnc#488799)
          @buf = Convert.to_string(SCR.Read(path(".process.read"), @pid))
          if @buf != nil && @buf != ""
            UI.ChangeWidget(Id(:stdout), :LastLine, Ops.add(@buf, "\n"))
          end

          @exit_status = Convert.to_integer(
            SCR.Read(path(".process.status"), @pid)
          )
          Builtins.y2milestone("exit status of the script: %1", @exit_status)
          UI.ReplaceWidget(
            Id(:rp_label),
            Label(
              Id(:label),
              Opt(:boldFont),
              @exit_status == 0 ?
                # text label
                _("Initialization is completed.") :
                # text label
                _("Initialization has failed.")
            )
          )
          break
        else
          update_output
        end
        if @ret == :cancel || @ret == :abort
          SCR.Execute(path(".process.kill"), @pid, 15)
          UI.ReplaceWidget(
            Id(:rp_label),
            # text label
            Label(
              Id(:label),
              Opt(:boldFont),
              _("Initialization has been aborted.")
            )
          )
          break
        end
        Builtins.sleep(100)
      end

      SCR.Execute(path(".process.kill"), @pid)

      # save the log files
      if FileUtils.CheckAndCreatePath(@logs_directory)
        SCR.Write(
          path(".target.string"),
          Ops.add(Ops.add(@logs_directory, "/"), @stdout_file),
          Convert.to_string(UI.QueryWidget(Id(:stdout), :Value))
        )
      end


      UI.NormalCursor

      if @exit_status != nil && Ops.greater_than(@exit_status, 249) &&
          Ops.less_than(@exit_status, 254)
        # error message, %1 is exit code (number)
        Popup.Message(
          Builtins.sformat(
            _(
              "There has been a problem with network device configuration (error %1).\nProceed according to the manual."
            ),
            @exit_status
          )
        )
      end

      Wizard.EnableBackButton
      # only allow to continue when script ended correctly
      Wizard.EnableNextButton if @exit_status == 0

      while true
        @ret = UI.UserInput
        if @ret == :abort && !Popup.ConfirmAbort(:incomplete)
          next
        else
          break
        end
      end
      deep_copy(@ret)
    end

    def update_output
      line = Convert.to_string(SCR.Read(path(".process.read_line"), @pid))
      if line != nil && line != ""
        UI.ChangeWidget(Id(:stdout), :LastLine, Ops.add(line, "\n"))
      end

      nil
    end
  end
end

Yast::FirstbootSleposInstallationClient.new.main
