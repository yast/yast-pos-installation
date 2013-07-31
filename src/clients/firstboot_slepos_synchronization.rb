# encoding: utf-8

# This client does Image synchronization
module Yast
  class FirstbootSleposSynchronizationClient < Client
    def main
      Yast.import "UI"
      textdomain "slepos-firstboot"

      Yast.import "GetInstArgs"
      Yast.import "Label"
      Yast.import "Mode"
      Yast.import "Popup"
      Yast.import "Stage"
      Yast.import "Wizard"

      Yast.import "POSInstallation"


      Builtins.y2milestone(
        "SLEPOS firstboot synchronization (%1, %2)",
        Mode.mode,
        Stage.stage
      )

      @ret = :auto

      if !Stage.firstboot
        Builtins.y2milestone("this should only run in firstboot stage: exiting")
        return deep_copy(@ret)
      end

      @args = GetInstArgs.argmap

      return deep_copy(@ret) if Ops.get_boolean(@args, "going_back", false)

      @synchronize = POSInstallation.sync_selection

      if @synchronize == :no_sync || @synchronize == :none
        Builtins.y2milestone("synchronization was skipped")
        return deep_copy(@ret)
      end

      @cont = VBox(
        VSpacing(0.4),
        ReplacePoint(
          Id(:rp_label),
          # text label
          Label(Id(:label), _("Image synchronization is prepared."))
        ),
        # label
        Left(Label(_("Synchronization script ('possyncimages') output"))),
        LogView(Id(:stdout), "", 6, 0),
        VSpacing(0.4)
      )

      @contents = HBox(
        HSpacing(1),
        VBox(VSpacing(0.4), @cont, VSpacing(0.4)),
        HSpacing(1)
      )

      # help text
      @help_text = _(
        "<p>\n" +
          "Online Image Synchronization may need a longer time, depending on the Admin Server internet connection.\n" +
          "</p>\n" +
          "<p>\n" +
          "Possible network problems indicate the need for a change in the Network Configuration step earlier in the sequence.</p>"
      )

      # dialog caption
      Wizard.SetContents(
        _("POS Image Synchronization"),
        @contents,
        @help_text,
        Ops.get_boolean(@args, "enable_back", true),
        Ops.get_boolean(@args, "enable_next", true)
      )

      @cmd = POSInstallation.sync_cmd
      @cmd = Ops.add(@cmd, " --local") if @synchronize == :sync_local
      @cmd = Ops.add(@cmd, " 2>&1")

      UI.ReplaceWidget(
        Id(:rp_label),
        # text label
        Label(Id(:label), _("Image synchronization is running. Please wait..."))
      )

      @pid = -1

      UI.BusyCursor
      Wizard.DisableNextButton
      Wizard.DisableBackButton

      Builtins.y2milestone("Executing '%1'", @cmd)
      UI.ChangeWidget(Id(:stdout), :LastLine, Ops.add(@cmd, "\n\n"))
      @pid = Convert.to_integer(SCR.Execute(path(".process.start_shell"), @cmd))

      while true
        @ret = Convert.to_symbol(UI.PollInput)
        if SCR.Read(path(".process.running"), @pid) != true
          update_output
          # explicitely check the process buffer after exit (bnc#488799)
          @buf = Convert.to_string(SCR.Read(path(".process.read"), @pid))
          if @buf != nil && @buf != ""
            UI.ChangeWidget(Id(:stdout), :LastLine, Ops.add(@buf, "\n"))
          end

          @status = Convert.to_integer(SCR.Read(path(".process.status"), @pid))
          Builtins.y2internal("exit status of the script: %1", @status)
          UI.ReplaceWidget(
            Id(:rp_label),
            Label(
              Id(:label),
              Opt(:boldFont),
              @status == 0 ?
                # text label
                _("Synchronization is completed.") :
                # text label
                _("Synchronization has failed.")
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
              _("Synchronization has been aborted.")
            )
          )
          break
        end
        Builtins.sleep(100)
      end

      SCR.Execute(path(".process.kill"), @pid)

      UI.NormalCursor

      Wizard.EnableBackButton
      Wizard.EnableNextButton

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

Yast::FirstbootSleposSynchronizationClient.new.main
