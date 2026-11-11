# Вливает хуки impeccable в settings.json Claude Code, не трогая чужие ключи.
{ writeShellApplication, jq }:
writeShellApplication {
  name = "impeccable-merge-hooks";
  runtimeInputs = [ jq ];
  text = ''
    # usage: impeccable-merge-hooks <settings.json> <launcher>
    settings=$1
    launcher=$2

    # Ровно та форма, что пишет сам движок для user-scope (hook_wiring.rs /
    # admin.rs апстрима): его распознаватель считает записи своими и не
    # дублирует их при `hooks on`.
    cmd="[ ! -f '$launcher' ] || '$launcher' hook"

    mkdir -p "$(dirname "$settings")"
    [ -e "$settings" ] || echo '{}' > "$settings"

    # Файл принадлежит пользователю и Claude Code: битый JSON не перезаписываем.
    if ! jq -e 'type == "object"' "$settings" >/dev/null 2>&1; then
      echo "impeccable: $settings is not a JSON object, hooks not merged" >&2
      exit 0
    fi

    tmp=$(mktemp "$settings.XXXXXX")
    trap 'rm -f "$tmp"' EXIT

    # Свои записи опознаём по пути лаунчера в команде: старую (в т.ч. с другим
    # store-путём или записанную самим движком) заменяем, чужие хуки оставляем.
    jq --arg cmd "$cmd" '
      def ours: ((.command? // "") | (contains("/skills/impeccable/scripts/impeccable") and endswith(" hook")));
      def strip: map(.hooks |= ((. // []) | map(select(ours | not)))) | map(select((.hooks | length) > 0));
      def hook($t; $msg): { type: "command", command: $cmd, timeout: $t, statusMessage: $msg };
      .hooks = (
        ((.hooks // {}) | with_entries(.value |= strip) | with_entries(select(.value | length > 0)))
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
