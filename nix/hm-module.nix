# Home Manager: скилл, агенты и (опционально) хуки impeccable для Claude Code.
self:
{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.programs.impeccable;
  home = config.home.homeDirectory;

  # Модуль programs.claude-code есть не во всех версиях Home Manager.
  hmClaude = options ? programs.claude-code && config.programs.claude-code.enable;

  rawDir =
    if cfg.claudeConfigDir != null then
      cfg.claudeConfigDir
    else if hmClaude then
      config.programs.claude-code.configDir
    else
      ".claude";
  trimmed = lib.removeSuffix "/" rawDir;
  absDir = if lib.hasPrefix "/" trimmed then trimmed else "${home}/${trimmed}";
  # Ключи home.file — относительно $HOME, когда каталог внутри него.
  relDir = lib.removePrefix "${home}/" absDir;

  # Значение попадает в шелл-скрипты активации: никаких кавычек, $, `, \ и ..
  dirOk =
    trimmed != ""
    && builtins.match "[^'\"$`\\\\]+" trimmed != null
    && !(lib.hasInfix ".." trimmed)
    && !(lib.hasInfix "//" trimmed);

  mergeHooks = pkgs.callPackage ./merge-hooks.nix { };
  telemetryOff = pkgs.callPackage ./set-telemetry-off.nix { };
  launcher = "${absDir}/skills/impeccable/scripts/impeccable";
  # Та же строка, что пишет сам движок (см. merge-hooks.nix).
  hookCommand = "[ ! -f '${launcher}' ] || '${launcher}' hook";
  hookEntry = timeout: statusMessage: {
    type = "command";
    command = hookCommand;
    inherit timeout statusMessage;
  };
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
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = ".config/claude";
      description = ''
        Claude Code config directory: relative to $HOME or absolute. When null,
        `programs.claude-code.configDir` is used if that Home Manager module is
        enabled, and `.claude` otherwise. Quotes, `$`, backticks, backslashes,
        `..` and `//` are rejected.
      '';
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
        Install the impeccable hooks (PostToolUse Edit|Write and Stop). With
        `programs.claude-code` enabled they are added to
        `programs.claude-code.settings.hooks`; otherwise they are merged into
        <claudeConfigDir>/settings.json during activation, which is skipped
        with a message when that file is a Nix store symlink.
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
        assertions = [
          {
            assertion = dirOk;
            message = "programs.impeccable.claudeConfigDir (or programs.claude-code.configDir) must be non-empty and contain no quotes, $, backticks, backslashes, '..' or '//': ${rawDir}";
          }
        ];
        home.file."${relDir}/skills/impeccable".source = "${cfg.package}/${cfg.package.skillDir}";
      }

      (lib.mkIf cfg.agents.enable {
        # recursive: каталог агентов остаётся общим с пользовательскими агентами.
        home.file."${relDir}/agents" = {
          source = "${cfg.package}/${cfg.package.agentsDir}";
          recursive = true;
        };
      })

      # Файл ведёт Home Manager (симлинк в стор): правим его декларативно, а не активацией.
      (lib.mkIf (cfg.hooks.enable && hmClaude) {
        programs.claude-code.settings.hooks = {
          PostToolUse = [
            {
              matcher = "Edit|Write";
              hooks = [ (hookEntry 5 "Checking UI changes") ];
            }
          ];
          Stop = [ { hooks = [ (hookEntry 30 "Design deep pass") ]; } ];
        };
      })

      (lib.mkIf (cfg.hooks.enable && !hmClaude) {
        # settings.json пишет сам Claude Code, поэтому не home.file, а слияние;
        # после linkGeneration, чтобы видеть итоговые ссылки HM.
        home.activation.impeccableHooks = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          run ${lib.getExe mergeHooks} ${lib.escapeShellArg "${absDir}/settings.json"} ${lib.escapeShellArg launcher}
        '';
      })

      (lib.mkIf (!cfg.telemetry.enable) {
        # Переменная окружения не дойдёт до хуков, если Claude Code запущен не
        # из сессии с home.sessionVariables; файл читает сам движок всегда.
        home.activation.impeccableTelemetryOff = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          run ${lib.getExe telemetryOff} ${lib.escapeShellArg "${home}/.impeccable/config.json"}
        '';
      })
    ]
  );
}
