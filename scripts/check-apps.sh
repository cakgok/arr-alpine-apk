#!/usr/bin/env bash

set -euo pipefail

apps_json="$APPS_CONFIG"
SELECTED_APP="${SELECTED_APP:-all}"

apps_to_check=()

if [[ $SELECTED_APP = all ]]; then
    mapfile -t apps_to_check < <(jq -r 'keys[]' <<<"$apps_json")
else
    apps_to_check=("$SELECTED_APP")
fi

apps_needing_update=()
for app in "${apps_to_check[@]}"; do
    
    # Get upstream repo
    upstream=$(jq -r --arg k "$app" '.[$k].upstream // empty' <<<"$apps_json")
    
    if [[ -z $upstream || $upstream == null ]]; then
        echo "No upstream configured for $app, skipping"
        continue
    fi
    
    # Check if APKBUILD exists for this app
    apkbuild_path="${app}/APKBUILD"
    if [[ ! -f $apkbuild_path ]]; then
        echo "[$app] Missing $apkbuild_path, skipping."
        continue
    fi
    
    # Fetch latest upstream tag
    latest_tag=$(
        curl -sS -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${GITHUB_TOKEN:-}" \
            "https://api.github.com/repos/${upstream}/releases/latest" \
        | jq -r '.tag_name // empty' | sed 's/^v//'
        ) || true 
        
    if [ -z "$latest_tag" ] || [ "$latest_tag" = "null" ]; then
        echo "Failed to fetch upstream tag for $app"
        continue
    fi
    
    # Read current version from APKBUILD
    current_ver=$(grep -m1 -Po '^pkgver=\K\S+' "$apkbuild_path" || true)
    
    echo "[$app] Current: $current_ver  Latest: $latest_tag"
    
    if [[ $latest_tag != "$current_ver" && -n "$current_ver" ]]; then        
        echo "[$app] → update needed!"
        apps_needing_update+=("$app:$latest_tag:$upstream")
    else
        echo "[$app] ✔ up-to-date"
    fi
done

if [[ ${#apps_needing_update[@]} -eq 0 ]]; then
    echo "No apps need updates"
    {
        echo "has_updates=false"
        echo "apps_matrix=[]"
    } >>"$GITHUB_OUTPUT"
else
    echo "Apps needing updates: ${apps_needing_update[*]}"

    # Build matrix JSON with jq
    matrix_json=$(
    printf '%s\n' "${apps_needing_update[@]}" |
    jq -Rn --argjson cfg "$apps_json" '
        [ inputs
        | split(":") as $p
        | {
            app:      $p[0],
            version:  $p[1],
            upstream: $p[2]
            }
        | .description = $cfg[.app].description
        ]' | jq -c
    )

    {
        echo "has_updates=true"
        printf 'apps_matrix=%s\n' "$matrix_json"
    } >>"$GITHUB_OUTPUT"
fi
