# Движок impeccable (Rust workspace апстрима), собирается из impeccable-src.
{
  lib,
  rustPlatform,
  src,
}:
let
  # Версия движка живёт в workspace-манифесте; читаем её оттуда, чтобы
  # bump flake.lock не требовал ручной правки версии.
  workspace = (lib.importTOML "${src}/Cargo.toml").workspace.package;
in
rustPlatform.buildRustPackage {
  pname = "impeccable";
  inherit (workspace) version;
  inherit src;

  # В Cargo.lock апстрима нет git-зависимостей, поэтому outputHashes не нужны.
  cargoLock.lockFile = "${src}/Cargo.lock";

  # Бинарь `impeccable` собирает единственный пакет cli; остальные крейты — его библиотеки.
  cargoBuildFlags = [
    "--package"
    "impeccable"
  ];

  # Тесты апстрима выключены: в workspace сотни интеграционных тестов, каждый
  # линкуется release-профилем с fat LTO (>20 мин сборки без результата), а
  # часть из них требует браузер/сеть. Работоспособность движка проверяет
  # checks.launcher-offline (engine-probe и context).
  doCheck = false;

  meta = {
    description = "Engine of impeccable, a design skill for AI coding agents (Nix build of the upstream Rust workspace)";
    homepage = "https://impeccable.style";
    changelog = "https://github.com/pbakaus/impeccable/releases";
    license = lib.licenses.asl20;
    mainProgram = "impeccable";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
