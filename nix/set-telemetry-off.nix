# Пишет "telemetry": false в ~/.impeccable/config.json, только если ключа нет.
{ writeShellApplication, jq }:
writeShellApplication {
  name = "impeccable-telemetry-off";
  runtimeInputs = [ jq ];
  text = ''
    # usage: impeccable-telemetry-off <config.json>
    cfg=$1
    mkdir -p "$(dirname "$cfg")"
    [ -e "$cfg" ] || echo '{}' > "$cfg"

    # Чужой/битый файл и явное решение пользователя не трогаем.
    jq -e 'type == "object" and (has("telemetry") | not)' "$cfg" >/dev/null 2>&1 || exit 0

    tmp=$(mktemp "$cfg.XXXXXX")
    trap 'rm -f "$tmp"' EXIT
    jq '. + {telemetry: false}' "$cfg" > "$tmp"
    chmod --reference="$cfg" "$tmp"
    mv -f "$tmp" "$cfg"
    trap - EXIT
  '';
}
