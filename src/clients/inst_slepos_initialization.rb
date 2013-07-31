# encoding: utf-8

# This client should be called at the beginning of update with SLESPOS 11 Add-On,
# to silently perform some initialization steps before the real update starts
module Yast
  class InstSleposInitializationClient < Client
    def main
      Yast.import "Directory"
      Yast.import "GetInstArgs"
      Yast.import "Mode"
      Yast.import "Installation"
      Yast.import "Stage"
      Yast.import "String"

      Builtins.y2milestone(
        "SLEPOS initializaton (%1, %2)",
        Mode.mode,
        Stage.stage
      )

      if !Mode.update || !Stage.initial
        Builtins.y2milestone(
          "this should only run in first stage of update: exiting"
        )
        return :auto
      end

      # save old /etc/SuSE-release, so we can find it in 2nd stage
      # it will be in /root/inst-sys/imported after installation
      if !GetInstArgs.going_back
        SCR.Execute(path(".target.mkdir"), "/root/imported")
        @out = Convert.to_map(
          SCR.Execute(
            path(".target.bash_output"),
            Builtins.sformat(
              "cp '%1/etc/SuSE-release' /root/imported",
              String.Quote(Installation.destdir)
            )
          )
        )
        if Ops.get_integer(@out, "exit", 1) != 0
          Builtins.y2error("saving old SuSE-release failed: %1", @out)
        else
          Builtins.y2milestone("SuSE-release copied to /root/imported")
        end
      end
      :auto
    end
  end
end

Yast::InstSleposInitializationClient.new.main
