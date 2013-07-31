# encoding: utf-8

# This client checks which kind of SLEPOS Branch server initialization is running
# and gathers the data for appropriate Branch Server initialization script
module Yast
  class FirstbootSleposInitializationClient < Client
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
        "SLEPOS firstboot initializaton (%1, %2)",
        Mode.mode,
        Stage.stage
      )

      @ret = :auto

      if !Stage.firstboot
        Builtins.y2milestone("this should only run in firstboot stage: exiting")
        return deep_copy(@ret)
      end

      @args = GetInstArgs.argmap

      # files for offline initialization
      # http://svn.suse.de/viewvc/slepos/trunk/slepos/images/branchserver/root/usr/share/SLEPOS/OIF/
      @oif_directory = "/usr/share/SLEPOS/OIF"
      @offline_initialization = POSInstallation.offline_initialization
      @offline_file = POSInstallation.offline_file

      @labels = {
        # text entry label
        "ALL_LDAPHOST"       => _("LDAP URI of Admin Server"),
        # text entry label
        "BRANCH_LDAPBASE"    => _(
          "Branch/Location LDAP Base DN"
        ),
        # text entry label
        "POS_ADMIN_PASSWORD" => _("Branch Password")
      }
      @settings = deep_copy(POSInstallation.online_initialization_settings)

      # If *.tgz in /usr/share/SLEPOS/OIF/ exists, off-line initialization is possible
      @out = Convert.to_map(
        SCR.Execute(
          path(".target.bash_output"),
          Builtins.sformat("ls -A1 %1/*.tgz 2>/dev/null", @oif_directory)
        )
      )
      @offline_files = Builtins.splitstring(
        Ops.get_string(@out, "stdout", ""),
        "\n"
      )
      if @offline_file == "" && @offline_files != nil &&
          Ops.greater_than(Builtins.size(@offline_files), 0)
        @offline_initialization = true
        @offline_file = Ops.get(@offline_files, 0, "")
      end

      @contents = HBox(
        HSpacing(3),
        RadioButtonGroup(
          Id(:rb),
          VBox(
            Left(
              RadioButton(
                Id(:offline_initialization),
                Opt(:notify),
                # radio button label
                _("Offline Initialization"),
                @offline_initialization
              )
            ),
            VSpacing(),
            HBox(
              HSpacing(3),
              VBox(
                # label (file name is on next line)
                Left(Label(_("Offline Initialization File:"))),
                ReplacePoint(
                  Id(:rp_file),
                  HBox(
                    Left(Label(Id(:offline_file), @offline_file)),
                    # button label
                    Right(PushButton(Id(:browse), _("&Change...")))
                  )
                )
              ),
              HSpacing(3)
            ),
            VSpacing(),
            Left(
              RadioButton(
                Id(:online_initialization),
                Opt(:notify),
                # radio button label
                _("Online Initialization"),
                !@offline_initialization
              )
            ),
            HBox(
              HSpacing(3),
              VBox(
                VSpacing(0.5),
                # text entry label
                InputField(
                  Id("ALL_LDAPHOST"),
                  Opt(:hstretch),
                  _("LDAP URI of &Admin Server"),
                  Ops.get(@settings, "ALL_LDAPHOST", "")
                ),
                # text entry label
                InputField(
                  Id("BRANCH_LDAPBASE"),
                  Opt(:hstretch),
                  _("Branch/&Location LDAP Base DN"),
                  Ops.get(@settings, "BRANCH_LDAPBASE", "")
                ),
                # text entry label
                Password(
                  Id("POS_ADMIN_PASSWORD"),
                  Opt(:hstretch),
                  _("Branch &Password"),
                  Ops.get(@settings, "POS_ADMIN_PASSWORD", "")
                )
              ),
              HSpacing(3)
            )
          )
        ),
        HSpacing(3)
      )


      # help text
      @help_text = _(
        "<p><b>Offline Initialization</b><br>\n" +
          "Initialize Branch Server from an <b>Offline Initialization File</b> (OIF). If the file was not found automatically, use <b>Change</b> to enter its correct location.</p>\n" +
          "\n" +
          "<p><b>Online Initialization</b><br>\n" +
          "Initialize Branch Server using an internet connection to the Admin Server.\n" +
          "  \n" +
          "Enter <b>LDAP URI of Admin Server</b> (like <tt>ldaps://admin.mycomp.us</tt>), <b>Branch/Location LDAP Base DN</b> (for example <tt>cn=store1,ou=myunit,o=mycomp,c=us</tt>) and the <b>Password</b> associated with the given Branch/Location.</p>"
      )

      # dialog caption
      Wizard.SetContents(
        _("POS Branch Server Initialization"),
        @contents,
        @help_text,
        Ops.get_boolean(@args, "enable_back", true),
        Ops.get_boolean(@args, "enable_next", true)
      )

      enable_disable_widgets
      if @offline_files == nil || @offline_files == []
        UI.ChangeWidget(Id(:offline_initialization), :Enabled, false)
      end

      while true
        @ret = UI.UserInput
        break if @ret == :back
        break if @ret == :abort && Popup.ConfirmAbort(:incomplete)
        if @ret == :browse
          @file = UI.AskForExistingFile(
            @oif_directory,
            "*.tgz",
            # label for file selection dialog
            _("Choose the Offline Initialization File")
          )
          if @file != nil
            @offline_file = @file
            UI.ReplaceWidget(
              Id(:rp_file),
              HBox(
                Left(Label(Id(:offline_file), @offline_file)),
                Right(PushButton(Id(:browse), _("&Change...")))
              )
            )
          end
        end
        if @ret == :offline_initialization || @ret == :online_initialization
          @offline_initialization = @ret == :offline_initialization
          enable_disable_widgets
        end
        if @ret == :next
          POSInstallation.offline_initialization = @offline_initialization
          POSInstallation.offline_file = @offline_file
          @missing = false
          @write = ""
          # list widgets in the order of appearence
          Builtins.foreach(
            ["ALL_LDAPHOST", "BRANCH_LDAPBASE", "POS_ADMIN_PASSWORD"]
          ) do |key|
            value = Convert.to_string(UI.QueryWidget(Id(key), :Value))
            if !@offline_initialization && value == ""
              label = Ops.get(@labels, key, key)
              # error popup
              Popup.Error(
                Builtins.sformat(_("The value of '%1' is empty."), label)
              )
              UI.SetFocus(Id(key))
              @missing = true
              raise Break
            else
              Ops.set(@settings, key, value)
              @write = Builtins.sformat("%1%2=%3\n", @write, key, value)
            end
          end
          next if @missing
          POSInstallation.online_initialization_settings = deep_copy(@settings)
          if !@offline_initialization
            Builtins.y2milestone("writing new /etc/SLEPOS/branchserver.conf")
            SCR.Write(
              path(".target.string"),
              POSInstallation.bs_config_file,
              @write
            )
          end
          break
        end
      end
      deep_copy(@ret)
    end

    def enable_disable_widgets
      UI.ChangeWidget(Id(:offline_file), :Enabled, @offline_initialization)
      UI.ChangeWidget(Id(:browse), :Enabled, @offline_initialization)

      Builtins.foreach(@settings) do |w_id, val|
        UI.ChangeWidget(Id(w_id), :Enabled, !@offline_initialization)
      end

      nil
    end
  end
end

Yast::FirstbootSleposInitializationClient.new.main
