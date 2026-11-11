# Скилл impeccable из апстрима + движок, положенный туда, где его ищет лаунчер.
{
  lib,
  stdenvNoCC,
  impeccable,
  src,
}:
let
  # Имена каталога движка считает сам лаунчер (scripts/impeccable): <os>-<arch>.
  inherit (stdenvNoCC.hostPlatform) isLinux isAarch64;
  os = if isLinux then "linux" else "darwin";
  arch = if isAarch64 then "arm64" else "x64";
  engine = lib.getExe impeccable;
in
stdenvNoCC.mkDerivation {
  pname = "impeccable-skill";
  inherit (impeccable) version;
  inherit src;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    skill=$out/skills/impeccable
    mkdir -p $out/skills $out/agents
    cp -r plugin/skills/impeccable $skill
    cp plugin/agents/*.md $out/agents/
    chmod -R u+w $out

    # Лаунчер принимает sibling-бинарь только если тот сообщает версию из
    # scripts/VERSION, иначе уходит в скачивание с GitHub. Сверяем и версию
    # из Cargo.toml, и то, что реально печатает собранный движок.
    pinned=$(tr -d ' \t\r\n' < $skill/scripts/VERSION)
    if [ "$pinned" != "${impeccable.version}" ]; then
      echo "skill pins engine $pinned but the built engine is ${impeccable.version}" >&2
      exit 1
    fi
    probe=$(${engine} engine-probe)
    if [ "$probe" != "impeccable-engine $pinned" ]; then
      echo "engine-probe printed '$probe', scripts/VERSION pins '$pinned'" >&2
      exit 1
    fi

    # Лаунчер-«fail closed»: движок из стора выбран по умолчанию (IMPECCABLE_BIN
    # исполняется до uname/скачивания), остальное опасное выключено, но каждое
    # значение можно переопределить переменной окружения:
    #  - IMPECCABLE_NO_UPDATE_CHECK: `context` иначе ходит в сеть, пишет
    #    ~/.impeccable/update-check.json и просит `npx impeccable update`;
    #    пустое значение включает проверку обратно.
    #  - IMPECCABLE_PRO=off: Pro-диспетчер исполняет скачанный бинарь после login.
    #  - IMPECCABLE_LIVE_COPY_AGENT=chat: live Apply иначе запускает codex/claude
    #    с отключёнными подтверждениями и текстом страницы в промпте; режим chat
    #    без chat-поллера ничего не запускает.
    substituteInPlace $skill/scripts/impeccable \
      --replace-fail \
        'export IMPECCABLE_SKILL_DIR IMPECCABLE_SELF' \
        ': "''${IMPECCABLE_BIN:=${engine}}"
    : "''${IMPECCABLE_PRO=off}"
    : "''${IMPECCABLE_LIVE_COPY_AGENT=chat}"
    : "''${IMPECCABLE_NO_UPDATE_CHECK=1}"
    export IMPECCABLE_SKILL_DIR IMPECCABLE_SELF IMPECCABLE_BIN IMPECCABLE_PRO IMPECCABLE_LIVE_COPY_AGENT IMPECCABLE_NO_UPDATE_CHECK'

    # Справочные файлы скилла велят агенту запускать `npx impeccable update`
    # и `install`: оба заменяют каталог скилла не-Nix сборкой.
    substituteInPlace $skill/reference/doctor.md \
      --replace-fail \
        "and \`npx impeccable update\` fixes it, or the harness's plugin manager for a plugin install" \
        "and updating the impeccable-nix flake input fixes it (\`nix flake update impeccable-src\`, then rebuild); never run \`npx impeccable update\` here, it would replace the Nix-managed skill"
    substituteInPlace $skill/reference/hooks.md \
      --replace-fail \
        'run `npx impeccable install` and then' \
        'install the Hermes plugin by hand (never run `npx impeccable install` under Nix: it would replace the Nix-managed skill) and then'

    # Sibling-раскладка остаётся запасным путём: поиск без сети.
    mkdir -p $skill/scripts/bin/${os}-${arch}
    ln -s ${engine} $skill/scripts/bin/${os}-${arch}/impeccable

    # Лицензия и NOTICE апстрима едут вместе со скиллом.
    for d in $out $skill; do
      cp LICENSE NOTICE.md $d/
    done

    runHook postInstall
  '';

  passthru = {
    skillDir = "skills/impeccable";
    agentsDir = "agents";
    engine = impeccable;
  };

  meta = {
    description = "impeccable design skill and agents for AI coding agents, wired to the Nix-built engine";
    homepage = "https://impeccable.style";
    license = lib.licenses.asl20;
    inherit (impeccable.meta) platforms;
  };
}
