# Проверки флейка: сборка, офлайн-лаунчер, слияние хуков, eval HM-модуля.
{
  pkgs,
  self,
  system,
  home-manager,
}:
let
  inherit (pkgs) lib;
  inherit (self.packages.${system}) impeccable impeccable-skill;
  mergeHooks = pkgs.callPackage ./merge-hooks.nix { };
  telemetryOff = pkgs.callPackage ./set-telemetry-off.nix { };
  launcher = "${impeccable-skill}/skills/impeccable/scripts/impeccable";

  mkHm =
    extra:
    home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        self.homeManagerModules.default
        {
          home = {
            username = "tester";
            homeDirectory = "/home/tester";
            stateVersion = "25.05";
          };
        }
        extra
      ];
    };

  hm = mkHm {
    programs.impeccable = {
      enable = true;
      hooks.enable = true;
    };
  };

  # programs.claude-code ведёт settings.json (симлинк в стор): хуки идут через его settings.
  hmClaude = mkHm {
    programs.claude-code = {
      enable = true;
      package = null;
      settings.model = "opus";
    };
    programs.impeccable = {
      enable = true;
      hooks.enable = true;
    };
  };

  hmBad = mkHm {
    programs.impeccable = {
      enable = true;
      claudeConfigDir = "x'; touch /tmp/pwned; '";
    };
  };
  # Утверждение модуля обрывает eval: tryEval ловит throw.
  badDirRejected = !(builtins.tryEval hmBad.activationPackage.drvPath).success;

  fakeEngine = pkgs.writeShellScript "fake-engine" ''
    echo "pro=$IMPECCABLE_PRO agent=$IMPECCABLE_LIVE_COPY_AGENT upd=$IMPECCABLE_NO_UPDATE_CHECK"
  '';
  storeSettings = pkgs.writeText "hm-settings.json" ''{"model":"x"}'';
  storeConfig = pkgs.writeText "cfg.json" "{}";
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
        G=${pkgs.gnugrep}/bin/grep
        unset IMPECCABLE_BIN IMPECCABLE_HOME IMPECCABLE_SKILL_DIR IMPECCABLE_PRO IMPECCABLE_LIVE_COPY_AGENT IMPECCABLE_NO_UPDATE_CHECK
        mkdir proj && cd proj

        probe=$(${pkgs.dash}/bin/dash ${launcher} engine-probe)
        echo "engine-probe: $probe"
        [ "$probe" = "impeccable-engine ${impeccable.version}" ]
        [ "$probe" = "impeccable-engine $(cat ${impeccable-skill}/skills/impeccable/scripts/VERSION)" ]

        # Дефолты запатченного лаунчера.
        $G -qF 'IMPECCABLE_BIN:=${lib.getExe impeccable}' ${launcher}
        $G -qF 'IMPECCABLE_PRO=off' ${launcher}
        $G -qF 'IMPECCABLE_LIVE_COPY_AGENT=chat' ${launcher}
        $G -qF 'IMPECCABLE_NO_UPDATE_CHECK=1' ${launcher}
        # Справочные файлы больше не велят запускать npx install/update.
        if $G -rqF 'run `npx impeccable install` and then' ${impeccable-skill}/skills/impeccable/reference; then echo "stale npx instruction"; exit 1; fi
        if $G -rqF 'and `npx impeccable update` fixes it' ${impeccable-skill}/skills/impeccable/reference; then echo "stale npx instruction"; exit 1; fi

        # Движок берётся по IMPECCABLE_BIN и без sibling-каталога bin/.
        cp -r ${impeccable-skill}/skills/impeccable $TMPDIR/skill
        chmod -R u+w $TMPDIR/skill
        unlink $TMPDIR/skill/scripts/bin/*/impeccable
        [ "$(${pkgs.dash}/bin/dash $TMPDIR/skill/scripts/impeccable engine-probe)" = "$probe" ]

        # Экспортируемые дефолты и их переопределение (движок подменён заглушкой).
        [ "$(IMPECCABLE_BIN=${fakeEngine} ${pkgs.dash}/bin/dash ${launcher})" = "pro=off agent=chat upd=1" ]
        [ "$(IMPECCABLE_BIN=${fakeEngine} IMPECCABLE_LIVE_COPY_AGENT=codex IMPECCABLE_PRO=on IMPECCABLE_NO_UPDATE_CHECK= ${pkgs.dash}/bin/dash ${launcher})" = "pro=on agent=codex upd=" ]

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

  merge-hooks =
    pkgs.runCommand "impeccable-merge-hooks-test"
      {
        nativeBuildInputs = [
          pkgs.jq
          pkgs.coreutils
        ];
      }
      ''
        M=${mergeHooks}/bin/impeccable-merge-hooks
        L=/home/u/.claude/skills/impeccable/scripts/impeccable
        cd $TMPDIR

        # Слияние: чужие ключи/хуки живут, старая запись заменена, повтор идемпотентен,
        # пустые группы пользователя на чужих событиях сохраняются.
        cat > s.json <<'JSON'
        {"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo mine"}]}],
         "Notification":[],
         "SessionStart":[{"hooks":[]}],
         "PostToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"[ ! -f '/old/skills/impeccable/scripts/impeccable' ] || '/old/skills/impeccable/scripts/impeccable' hook"}]}]}}
        JSON
        $M s.json $L
        cp s.json first.json
        $M s.json $L
        cmp s.json first.json
        jq -e '.model == "opus"
          and (.hooks.Stop | length == 2)
          and (.hooks.PostToolUse | length == 1)
          and (.hooks.Notification == [])
          and (.hooks.SessionStart == [{"hooks":[]}])
          and ([.hooks[][].hooks[].command | select(contains("impeccable"))] | length == 2)
          and (.hooks.Stop[0].hooks[0].command == "echo mine")' s.json

        # Событие, опустевшее только из-за нашего удаления, пропадает.
        echo '{"hooks":{"Old":[{"hooks":[{"type":"command","command":"[ ! -f '"'"'/x/skills/impeccable/scripts/impeccable'"'"' ] || '"'"'/x/skills/impeccable/scripts/impeccable'"'"' hook"}]}]}}' > o.json
        $M o.json $L
        jq -e '(.hooks | has("Old") | not) and (.hooks | has("Stop"))' o.json

        # Формы, которые нельзя трогать: битый JSON, несколько документов, не-массив события.
        echo 'not json' > bad.json
        printf '{}\n{}\n' > multi.json
        echo '{"hooks":{"Stop":{"a":1}}}' > nonarray.json
        echo '[1]' > notobj.json
        for f in bad multi nonarray notobj; do
          cp $f.json $f.orig
          $M $f.json $L 2>/dev/null
          cmp $f.json $f.orig
        done

        # Висячая ссылка не заменяется и не создаёт цель.
        ln -s $TMPDIR/nowhere/settings.json dangling.json
        $M dangling.json $L 2>/dev/null
        [ -L dangling.json ]
        [ ! -e $TMPDIR/nowhere ]

        # Ссылка в /nix/store (так выглядит файл Home Manager) остаётся ссылкой.
        ln -s ${storeSettings} store.json
        $M store.json $L 2>/dev/null
        [ -L store.json ]
        [ "$(readlink store.json)" = "${storeSettings}" ]

        # Ссылка наружу стора правится по месту, ссылка остаётся.
        echo '{"k":1}' > real.json
        ln -s real.json link.json
        $M link.json $L
        [ -L link.json ]
        jq -e '.k == 1 and (.hooks.Stop | length == 1)' real.json

        # Новый файл создаётся с режимом 0600.
        umask 022
        $M fresh/settings.json $L
        [ "$(stat -c %a fresh/settings.json)" = 600 ]

        # Телеметрия: ключ добавляется только если его нет; те же защиты.
        T=${telemetryOff}/bin/impeccable-telemetry-off
        $T cfg/config.json
        jq -e '.telemetry == false' cfg/config.json
        [ "$(stat -c %a cfg/config.json)" = 600 ]
        echo '{"telemetry":true,"x":1}' > c2.json
        $T c2.json
        jq -e '.telemetry == true and .x == 1' c2.json
        ln -s $TMPDIR/nowhere/c.json cd.json
        $T cd.json 2>/dev/null
        [ -L cd.json ]
        [ ! -e $TMPDIR/nowhere ]
        ln -s ${storeConfig} cs.json
        $T cs.json 2>/dev/null
        [ "$(readlink cs.json)" = "${storeConfig}" ]
        printf '{}\n{}\n' > cm.json
        $T cm.json 2>/dev/null
        [ "$(wc -l < cm.json)" = 2 ]
        touch $out
      '';

  hm-module = pkgs.runCommand "impeccable-hm-module-eval" { nativeBuildInputs = [ pkgs.jq ]; } ''
    gen=${hm.activationPackage}/home-files
    test -e $gen/.claude/skills/impeccable/SKILL.md
    test -e $gen/.claude/agents/impeccable-documenter.md
    act=${hm.activationPackage}/activate
    grep -q impeccable-merge-hooks $act
    grep -q impeccable-telemetry-off $act
    # активация после linkGeneration
    [ "$(grep -n 'impeccable-merge-hooks' $act | head -1 | cut -d: -f1)" -gt "$(grep -n 'linkGeneration' $act | head -1 | cut -d: -f1)" ]

    # Режим programs.claude-code: хуки в декларативных settings, скрипт слияния не нужен.
    g2=${hmClaude.activationPackage}
    test -e $g2/home-files/.claude/skills/impeccable/SKILL.md
    if grep -q impeccable-merge-hooks $g2/activate; then exit 1; fi
    jq -e '.model == "opus" and (.hooks.PostToolUse[0].matcher == "Edit|Write") and (.hooks.Stop | length == 1)
      and (.hooks.Stop[0].hooks[0].command | contains("/home/tester/.claude/skills/impeccable/scripts/impeccable"))' \
      $g2/home-files/.claude/settings.json

    # Небезопасный claudeConfigDir отвергается утверждением модуля.
    ${if badDirRejected then "true" else "echo 'missing dir assertion'; exit 1"}
    touch $out
  '';
}
