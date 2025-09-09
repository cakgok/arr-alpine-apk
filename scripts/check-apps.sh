#!/usr/bin/env bash

set -euo pipefail

apps_json="$APPS_CONFIG"
SELECTED_APP="${SELECTED_APP:-all}"

auth_header=()
if [[ -n "${GH_PAT:-}" ]]; then
  auth_header=(-H "Authorization: Bearer ${GH_PAT}")
fi

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
        curl -sfSL -H "Accept: application/vnd.github+json" \
                -H "User-Agent: update-checker" \
                "${auth_header[@]}" \
                "https://api.github.com/repos/${upstream}/releases/latest" \
        | jq -r '.tag_name // empty' | sed 's/^v//'
    ) || latest_tag=""
        
    if [[ -z $latest_tag ]]; then
        echo "[$app] Couldn’t fetch a release (maybe only prereleases?)"
        continue
    fi

    expected_tag="${app}-v${latest_tag}"
    
    echo "[$app] Latest upstream: $latest_tag. Checking for our release tag: $expected_tag"

    # Check if a release with that tag already exists in repo.
    # `gh release view` exits with a non-zero code if the release is not found.
    if gh release view "$expected_tag" >/dev/null 2>&1; then
      echo "[$app] ✔ Release already exists."
    else
      echo "[$app] → Missing release! Adding to build queue."
      apps_needing_update+=("$app:$latest_tag:$upstream")
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

    matrix_json=$(
    printf '%s\n' "${apps_needing_update[@]}" |
    jq -cRn --argjson cfg "$apps_json" '
        [ inputs
        | split(":") as $p
        | {
            app:      $p[0],
            version:  $p[1],
            upstream: $p[2]
            }
        | .description = $cfg[.app].description
        ]'
    )

    echo "has_updates=true" >> "$GITHUB_OUTPUT"
    echo "apps_matrix<<EOF" >> "$GITHUB_OUTPUT"
    echo "$matrix_json" >> "$GITHUB_OUTPUT"
    echo "EOF" >> "$GITHUB_OUTPUT"

fi