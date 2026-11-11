# Home Manager: скилл, агенты и (опционально) хуки impeccable для Claude Code.
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.impeccable;
  dir = cfg.claudeConfigDir;
  home = config.home.homeDirectory;
  mergeHooks = pkgs.callPackage ./merge-hooks.nix { };
  launcher = "${home}/${dir}/skills/impeccable/scripts/impeccable";
  telemetryOff = pkgs.callPackage ./set-telemetry-off.nix { };
in
{
  options.programs.impeccable = {
    enable = lib.mkEnableOption "the impeccable design skill for Claude Code";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.impeccable-skill;
      defaultText = lib.literalExpression "impeccable-nix.packages.\${system}.impeccable-skill";
      description = "Skill package (skills/impeccable and agents/ with the engine wired in).";
    };

    claudeConfigDir = lib.mkOption {
      type = lib.types.str;
      default = ".claude";
      example = ".config/claude";
      description = "Claude Code config directory, relative to $HOME.";
    };

    agents.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the four impeccable subagents into <claudeConfigDir>/agents.";
    };

    hooks.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Merge the impeccable hooks (PostToolUse Edit|Write and Stop) into
        <claudeConfigDir>/settings.json. The file stays writable; only the
        impeccable entries are replaced on each activation.
      '';
    };

    telemetry.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Allow the engine to send usage pings to impeccable.style. When false,
        `"telemetry": false` is written to ~/.impeccable/config.json if the
        telemetry key is absent there. An existing value is never overwritten.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.file."${dir}/skills/impeccable".source = "${cfg.package}/${cfg.package.skillDir}";
      }

      (lib.mkIf cfg.agents.enable {
        # recursive: каталог агентов остаётся общим с пользовательскими агентами.
        home.file."${dir}/agents" = {
          source = "${cfg.package}/${cfg.package.agentsDir}";
          recursive = true;
        };
      })

      (lib.mkIf cfg.hooks.enable {
        # settings.json пишет сам Claude Code, поэтому не home.file, а слияние.
        home.activation.impeccableHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${lib.getExe mergeHooks} "${home}/${dir}/settings.json" "${launcher}"
        '';
      })

      (lib.mkIf (!cfg.telemetry.enable) {
        # Переменная окружения не дойдёт до хуков, если Claude Code запущен не
        # из сессии с home.sessionVariables; файл читает сам движок всегда.
        home.activation.impeccableTelemetryOff = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${lib.getExe telemetryOff} "${home}/.impeccable/config.json"
        '';
      })
    ]
  );
}
