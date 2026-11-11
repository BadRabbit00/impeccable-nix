# Проверки флейка: сборка, офлайн-лаунчер, слияние хуков, eval HM-модуля.
{
  pkgs,
  self,
  system,
  home-manager,
}:
let
  inherit (self.packages.${system}) impeccable impeccable-skill;
  mergeHooks = pkgs.callPackage ./merge-hooks.nix { };
  telemetryOff = pkgs.callPackage ./set-telemetry-off.nix { };
  launcher = "${impeccable-skill}/skills/impeccable/scripts/impeccable";

  hm = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      self.homeManagerModules.default
      {
        home = {
          username = "tester";
          homeDirectory = "/home/tester";
          stateVersion = "25.05";
        };
        programs.impeccable = {
          enable = true;
          hooks.enable = true;
        };
      }
    ];
  };
in
{
  inherit impeccable impeccable-skill;

  # Лаунчер должен найти движок рядом с собой: пустой PATH, чистый HOME, сеть в
  # сэндбоксе недоступна. Если бы сработал путь скачивания, он упал бы, а в
  # HOME появился бы ~/.impeccable.
  launcher-offline =
    pkgs.runCommand "impeccable-launcher-offline" { nativeBuildInputs = [ pkgs.coreutils ]; }
      ''
        export HOME=$(mktemp -d)
        export PATH=${pkgs.coreutils}/bin
        unset IMPECCABLE_BIN IMPECCABLE_HOME IMPECCABLE_SKILL_DIR
        mkdir proj && cd proj

        probe=$(${pkgs.dash}/bin/dash ${launcher} engine-probe)
        echo "engine-probe: $probe"
        [ "$probe" = "impeccable-engine ${impeccable.version}" ]

        # Реальная команда скилла (SKILL.md запускает `context`).
        ${pkgs.dash}/bin/dash ${launcher} context > context.out 2> context.err || {
          cat context.err; exit 1; }
        head -c 300 context.out; echo

        # Ничего не записано в HOME.
        if [ -n "$(ls -A $HOME)" ]; then
          echo "HOME is not empty:"; ls -laR $HOME; exit 1
        fi
        touch $out
      '';

  merge-hooks = pkgs.runCommand "impeccable-merge-hooks-test" { nativeBuildInputs = [ pkgs.jq ]; } ''
    s=$TMPDIR/settings.json
    cat > $s <<'JSON'
    {"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo mine"}]}],
     "PostToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"[ ! -f '/old/skills/impeccable/scripts/impeccable' ] || '/old/skills/impeccable/scripts/impeccable' hook"}]}]}}
    JSON
    L=/home/u/.claude/skills/impeccable/scripts/impeccable
    ${mergeHooks}/bin/impeccable-merge-hooks $s $L
    cp $s first.json
    ${mergeHooks}/bin/impeccable-merge-hooks $s $L
    cmp $s first.json   # идемпотентность
    jq -e '.model == "opus"
      and (.hooks.Stop | length == 2)
      and (.hooks.PostToolUse | length == 1)
      and ([.hooks[][].hooks[].command | select(contains("impeccable"))] | length == 2)
      and (.hooks.Stop[0].hooks[0].command == "echo mine")' $s

    # Битый файл не перезаписывается.
    echo 'not json' > $TMPDIR/bad.json
    ${mergeHooks}/bin/impeccable-merge-hooks $TMPDIR/bad.json $L 2>/dev/null
    [ "$(cat $TMPDIR/bad.json)" = "not json" ]

    # Телеметрия: ключ добавляется только если его нет.
    t=$TMPDIR/cfg/config.json
    ${telemetryOff}/bin/impeccable-telemetry-off $t
    jq -e '.telemetry == false' $t
    echo '{"telemetry":true,"x":1}' > $t
    ${telemetryOff}/bin/impeccable-telemetry-off $t
    jq -e '.telemetry == true and .x == 1' $t
    touch $out
  '';

  hm-module = pkgs.runCommand "impeccable-hm-module-eval" { } ''
    gen=${hm.activationPackage}/home-files
    test -e $gen/.claude/skills/impeccable/SKILL.md
    test -e $gen/.claude/agents/impeccable-documenter.md
    grep -q impeccable-merge-hooks ${hm.activationPackage}/activate
    grep -q impeccable-telemetry-off ${hm.activationPackage}/activate
    touch $out
  '';
}
