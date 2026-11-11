# Пишет "telemetry": false в ~/.impeccable/config.json, только если ключа нет.
{ writeShellApplication, jq }:
writeShellApplication {
  name = "impeccable-telemetry-off";
  runtimeInputs = [ jq ];
  text = ''
    # usage: impeccable-telemetry-off <config.json>
    cfg=$1
    ${import ./guard.nix}
    safe_target "$cfg" || exit 0

    if [ -e "$cfg" ] || [ -L "$cfg" ]; then
      cfg=$(readlink -f "$cfg")
    else
      mkdir -p "$(dirname "$cfg")"
      (umask 077; echo '{}' > "$cfg")
    fi

    # Чужой/битый файл и явное решение пользователя не трогаем.
    jq -s -e 'length == 1 and (.[0] | type) == "object" and (.[0] | has("telemetry") | not)' "$cfg" >/dev/null 2>&1 || exit 0

    tmp=$(mktemp "$cfg.XXXXXX")
    trap 'rm -f "$tmp"' EXIT
    jq '. + {telemetry: false}' "$cfg" > "$tmp"
    chmod --reference="$cfg" "$tmp"
    mv -f "$tmp" "$cfg"
    trap - EXIT
  '';
}
