# Общий шелл-код защиты для скриптов, правящих пользовательские файлы.
''
  # Возвращает 0, если файл можно править; печатает причину и 1 иначе.
  # Висячая ссылка и ссылка в /nix/store (файл ведёт Home Manager) остаются нетронутыми:
  # замена ссылки обычным файлом ломает следующий релинк HM.
  safe_target() {
    if [ -L "$1" ]; then
      if [ ! -e "$1" ]; then
        echo "impeccable: $1 is a dangling symlink, left untouched" >&2
        return 1
      fi
      case $(readlink -f "$1") in
        /nix/store/*)
          echo "impeccable: $1 is managed by Home Manager (a Nix store symlink), left untouched;" >&2
          echo "impeccable: declare these entries through programs.claude-code.settings instead" >&2
          return 1
          ;;
      esac
    fi
    return 0
  }
''
