# Вливает хуки impeccable в settings.json Claude Code, не трогая чужие ключи.
{ writeShellApplication, jq }:
writeShellApplication {
  name = "impeccable-merge-hooks";
  runtimeInputs = [ jq ];
  text = ''
    # usage: impeccable-merge-hooks <settings.json> <launcher>
    settings=$1
    launcher=$2
    ${import ./guard.nix}
    safe_target "$settings" || exit 0

    # Ровно та форма, что пишет сам движок для user-scope (hook_wiring.rs /
    # admin.rs апстрима): его распознаватель считает записи своими и не
    # дублирует их при `hooks on`.
    cmd="[ ! -f '$launcher' ] || '$launcher' hook"

    if [ -e "$settings" ] || [ -L "$settings" ]; then
      settings=$(readlink -f "$settings")
    else
      mkdir -p "$(dirname "$settings")"
      (umask 077; echo '{}' > "$settings")
    fi

    # Файл принадлежит пользователю и Claude Code: всё, что не похоже на
    # ожидаемую форму, не перезаписываем.
    if ! jq -s -e 'length == 1 and (.[0] | type) == "object" and ((.[0].hooks // {}) | type) == "object" and all((.[0].hooks // {})[]; type == "array")' "$settings" >/dev/null 2>&1; then
      echo "impeccable: $settings has an unexpected shape (not one JSON object with array hook events), hooks not merged" >&2
      exit 0
    fi

    tmp=$(mktemp "$settings.XXXXXX")
    trap 'rm -f "$tmp"' EXIT

    # Свои записи опознаём по пути лаунчера в команде: старую (в т.ч. с другим
    # store-путём или записанную самим движком) заменяем, чужие хуки оставляем.
    # Пустыми удаляем только группы и события, опустевшие из-за нашего удаления.
    jq --arg cmd "$cmd" '
      def isours: type == "object" and ((.command? // "") as $c | ($c | type) == "string"
        and ($c | contains("/skills/impeccable/scripts/impeccable")) and ($c | endswith(" hook")));
      def hasours: type == "object" and ((.hooks // []) | type) == "array" and any(.hooks[]?; isours);
      def clean: map(if hasours then (.hooks |= map(select(isours | not))) | select((.hooks | length) > 0) else . end);
      def hook($t; $msg): { type: "command", command: $cmd, timeout: $t, statusMessage: $msg };
      .hooks = (
        ((.hooks // {}) | to_entries
          | map(if (.value | any(.[]; hasours)) then (.value |= clean) | select(.value | length > 0) else . end)
          | from_entries)
        | .PostToolUse = ((.PostToolUse // []) + [{ matcher: "Edit|Write", hooks: [hook(5; "Checking UI changes")] }])
        | .Stop = ((.Stop // []) + [{ hooks: [hook(30; "Design deep pass")] }])
      )
    ' "$settings" > "$tmp"

    if cmp -s "$tmp" "$settings"; then
      exit 0
    fi
    chmod --reference="$settings" "$tmp"
    mv -f "$tmp" "$settings"
    trap - EXIT
  '';
}
