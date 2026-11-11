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
        # scripts/VERSION, иначе уходит в скачивание с GitHub. Ловим расхождение
        # при сборке, а не у пользователя.
        pinned=$(tr -d ' \t\r\n' < $skill/scripts/VERSION)
        if [ "$pinned" != "${impeccable.version}" ]; then
          echo "skill pins engine $pinned but the built engine is ${impeccable.version}" >&2
          exit 1
        fi

        # `context` по умолчанию ходит в сеть за свежей версией скилла, пишет
        # ~/.impeccable/update-check.json и просит агента выполнить `npx impeccable
        # update`, что на Nix бессмысленно (обновление = bump flake.lock). Отключаем
        # проверку по умолчанию; пустое значение переменной включает её обратно.
        substituteInPlace $skill/scripts/impeccable \
          --replace-fail \
            'export IMPECCABLE_SKILL_DIR IMPECCABLE_SELF' \
            ': "''${IMPECCABLE_NO_UPDATE_CHECK=1}"
    export IMPECCABLE_SKILL_DIR IMPECCABLE_SELF IMPECCABLE_NO_UPDATE_CHECK'

        # Sibling-раскладка: поиск без переменных окружения и без сети.
        mkdir -p $skill/scripts/bin/${os}-${arch}
        ln -s ${lib.getExe impeccable} $skill/scripts/bin/${os}-${arch}/impeccable

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
    platforms = impeccable.meta.platforms;
  };
}
