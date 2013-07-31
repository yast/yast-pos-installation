# encoding: utf-8

# This client prepares Image synchronization
module Yast
  class FirstbootSleposSelectionClient < Client
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

      # help text for popup
      @help_text = _(
        "\n" +
          "<p>\n" +
          "<b>Synchronize Images from Admin Server</b><br>\n" +
          "Download and install the latest image versions. This action requires working internet connection to the Admin Server.\n" +
          "</p>\n" +
          "<p>\n" +
          "<b>Synchronize Images Locally</b><br>\n" +
          "Install the locally available images.\n" +
          "</p>\n" +
          "<p>\n" +
          "<b>Do not Synchronize Images</b><br>\n" +
          "Image synchronization is skipped. It should be run manually later, using the <tt>possyncimages</tt> script.</p>"
      )

      @synchronize = POSInstallation.sync_selection
      if @synchronize == :none
        @synchronize = POSInstallation.offline_initialization ? :sync_local : :sync
      end

      @contents = HBox(
        HSpacing(1),
        VBox(
          VSpacing(),
          # label
          Left(Label(_("Choose the way how the image should be synchronized"))),
          VSpacing(),
          HBox(
            HSpacing(2),
            RadioButtonGroup(
              Id(:rb),
              VBox(
                Left(
                  RadioButton(
                    Id(:sync),
                    # radio button label
                    _("Synchronize Image from Admin Server"),
                    @synchronize == :sync
                  )
                ),
                VSpacing(),
                Left(
                  RadioButton(
                    Id(:sync_local),
                    # radio button label
                    _("Synchronize Image Locally"),
                    @synchronize == :sync_local
                  )
                ),
                VSpacing(),
                Left(
                  RadioButton(
                    Id(:no_sync),
                    # radio button label
                    _("Do not Synchronize Image"),
                    @synchronize == :no_sync
                  )
                )
              )
            )
          )
        ),
        HSpacing(1)
      )

      # dialog caption
      Wizard.SetContents(
        _("POS Image Synchronization"),
        @contents,
        @help_text,
        Ops.get_boolean(@args, "enable_back", true),
        Ops.get_boolean(@args, "enable_next", true)
      )

      while true
        @ret = UI.UserInput
        if @ret == :abort && !Popup.ConfirmAbort(:incomplete)
          next
        else
          break
        end
      end

      @synchronize = Convert.to_symbol(UI.QueryWidget(Id(:rb), :Value))

      Builtins.y2milestone("selected syncrhonization type: %1", @synchronize)

      POSInstallation.sync_selection = @synchronize

      deep_copy(@ret)
    end
  end
end

Yast::FirstbootSleposSelectionClient.new.main
