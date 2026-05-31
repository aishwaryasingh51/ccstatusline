#!/usr/bin/env bash
input=$(cat)

# Parse all input fields in one jq call (\x1f delimiter — see CLAUDE.md gotcha)
IFS=$'\x1f' read -r cwd model used week five five_reset < <(
  jq -r '[.workspace.current_dir // .cwd,
          .model.display_name // "",
          (.context_window.used_percentage | numbers | tostring) // "",
          (.rate_limits.seven_day.used_percentage | numbers | tostring) // "",
          (.rate_limits.five_hour.used_percentage | numbers | tostring) // "",
          (.rate_limits.five_hour.resets_at | numbers | tostring) // ""] | join("")' <<<"$input"
)
home="$HOME"

# Path display
home_icon=$'\xef\x80\x95'
short_cwd="${cwd/#$home/$home_icon}"
# Glyph needs a space before the next char or terminals render it small (see CLAUDE.md gotcha)
[[ "$short_cwd" == "${home_icon}/"* ]] && short_cwd="${home_icon} ${short_cwd#${home_icon}}"
IFS='/' read -ra _p <<<"$short_cwd"
n=${#_p[@]}
if (( n > 4 )); then
  short_cwd=".../${_p[n-4]}/${_p[n-3]}/${_p[n-2]}/${_p[n-1]}"
fi

# Git status — branch and flags stored separately so the build block can color each flag
_git_branch=""; _git_staged=0; _git_modified=0; _git_untracked=0
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  _git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
    || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  if [[ -n "$_git_branch" ]]; then
    gs=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)
    if [[ -n "$gs" ]]; then
      while IFS= read -r ln; do
        case "${ln:0:1}" in [MADRCU]) _git_staged=1 ;; esac
        [[ "${ln:1:1}" == M ]] && _git_modified=1
        [[ "${ln:0:2}" == "??" ]] && _git_untracked=1
      done <<<"$gs"
    fi
  fi
fi

plan=$(jq -r '.model // empty' "$HOME/.claude/settings.json" 2>/dev/null \
  | awk '{s=$0; sub(/plan/,"Plan",s); print toupper(substr(s,1,1)) substr(s,2)}')

# ── Adaptive palette ──────────────────────────────────────────────────────────
# printf -v writes directly into the named variable — no subshell
_emit() { local h=${2#\#}; [[ ${#h} -eq 6 ]] && printf -v "$1" '\033[38;2;%d;%d;%dm' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"; }
_lerp() {
  local h1="${1#\#}" h2="${2#\#}" t=$3
  printf '\033[38;2;%d;%d;%dm' \
    $(( (16#${h1:0:2}) + ((16#${h2:0:2}) - (16#${h1:0:2})) * t / 100 )) \
    $(( (16#${h1:2:2}) + ((16#${h2:2:2}) - (16#${h1:2:2})) * t / 100 )) \
    $(( (16#${h1:4:2}) + ((16#${h2:4:2}) - (16#${h1:4:2})) * t / 100 ))
}
_RST='\033[0m'
_set_ansi() {
  C_IRIS='\033[95m'; C_ROSE='\033[91m'; C_GOLD='\033[93m'
  C_TEXT='\033[97m'; C_MUTED='\033[90m'
  _G1='\033[92m'; _G2='\033[96m'; _G3='\033[93m'; _G4='\033[91m'
  _G1h=""; _G2h=""; _G3h=""; _G4h=""
}
_load_pywal() {
  local v; v=$(jq -r '[.colors.color4,.colors.color5,.colors.color3,
    .special.foreground,.colors.color8,.colors.color2,
    .colors.color6,.colors.color3,.colors.color1] | @tsv' "$1" 2>/dev/null) || return 1
  IFS=$'\t' read -r _i _r _g _t _m _g1 _g2 _g3 _g4 <<< "$v"
  _emit C_IRIS "$_i"; _emit C_ROSE "$_r"; _emit C_GOLD "$_g"
  _emit C_TEXT "$_t"; _emit C_MUTED "$_m"
  _emit _G1 "$_g1"; _emit _G2 "$_g2"; _emit _G3 "$_g3"; _emit _G4 "$_g4"
  _G1h=$_g1; _G2h=$_g2; _G3h=$_g3; _G4h=$_g4
}
_alac_val() {
  awk -v sec="[colors.$1]" -v k="$2" '
    $0==sec{s=1;next} s&&/^\[/{s=0}
    s{ n=index($0,"="); if(!n) next
       ky=substr($0,1,n-1); gsub(/[ \t]/,"",ky); if(ky!=k) next
       v=substr($0,n+1); gsub(/[ \t'"'"'"]/,"",v); print v; exit }
  ' "$3"
}
_gh_batch() {
  # Parse multiple Ghostty config/theme keys in one awk pass
  # $1=comma-separated key list, $2...=files (later files override earlier ones)
  local _keys="$1"; shift
  local _gf=()
  local _f; for _f in "$@"; do [[ -r "$_f" ]] && _gf+=("$_f"); done
  [[ ${#_gf[@]} -eq 0 ]] && return 1
  awk -v keys="$_keys" '
    BEGIN{
      n=split(keys,K,",")
      for(i=1;i<=n;i++){k=K[i];last[k]="";if(substr(k,1,8)=="palette.")palkey[k]=substr(k,9)}
    }
    /^[[:space:]]*#/||/^[[:space:]]*$/{next}
    {
      gsub(/[[:space:]]/,"")
      for(i=1;i<=n;i++){
        k=K[i]
        if(k in palkey){pk=palkey[k];if($0~("^palette="pk"=#")){v=$0;sub(/^palette=[^=]*=/,"",v);last[k]=v}}
        else{if($0~("^"k"=#")){v=$0;sub(/^[^=]*=/,"",v);last[k]=v}}
      }
    }
    END{for(i=1;i<=n;i++)printf "%s%s",last[K[i]],(i<n?"\t":"\n")}
  ' "${_gf[@]}"
}

# Probe palette sources in priority order (OS-branched)
if [[ "$OSTYPE" == darwin* ]]; then
  _mac_ok=0
  # 1. Ghostty
  if (( ! _mac_ok )); then
    _gcfg="$HOME/.config/ghostty/config"
    if [[ -r "$_gcfg" ]]; then
      _theme=$(awk '/^[[:space:]]*#/{next}{
        gsub(/^[[:space:]]+|[[:space:]]+$/,"")
        if(/^theme[[:space:]]*=/){sub(/^theme[[:space:]]*=[[:space:]]*/,"");n=split($0,a,",");t=a[1];gsub(/^[[:space:]]+|[[:space:]]+$/,"",t);sub(/^(dark|light):/,"",t);print t;exit}
      }' "$_gcfg")
      _tf=""
      if [[ -n "$_theme" ]]; then
        for _tp in "$HOME/.config/ghostty/themes/$_theme" \
                   "/Applications/Ghostty.app/Contents/Resources/ghostty/themes/$_theme"; do
          [[ -r "$_tp" ]] && { _tf="$_tp"; break; }
        done
      fi
      IFS=$'\t' read -r _t _i _r _g _m _g1 _g2 _g3 _g4 < <(
        _gh_batch "foreground,palette.5,palette.6,palette.3,palette.8,palette.2,palette.3,palette.1,palette.9" "$_tf" "$_gcfg"
      )
      if [[ -n "$_t" ]]; then
        _emit C_TEXT "$_t"; _emit C_IRIS "$_i"; _emit C_ROSE "$_r"
        _emit C_GOLD "$_g"; _emit C_MUTED "$_m"
        _emit _G1 "$_g1"; _emit _G2 "$_g2"; _emit _G3 "$_g3"; _emit _G4 "$_g4"
        _G1h=$_g1; _G2h=$_g2; _G3h=$_g3; _G4h=$_g4
        _mac_ok=1
      fi
    fi
  fi
  # 2. Alacritty
  if (( ! _mac_ok )); then
    _acfg="$HOME/.config/alacritty/alacritty.toml"
    if [[ -r "$_acfg" ]]; then
      _t=$(_alac_val primary foreground "$_acfg")
      if [[ -n "$_t" ]]; then
        _G1h=$(_alac_val normal green  "$_acfg"); _G2h=$(_alac_val normal cyan   "$_acfg")
        _G3h=$(_alac_val normal yellow "$_acfg"); _G4h=$(_alac_val normal red    "$_acfg")
        _emit C_TEXT  "$_t"
        _emit C_IRIS  "$(_alac_val normal  blue    "$_acfg")"
        _emit C_ROSE  "$(_alac_val normal  magenta "$_acfg")"
        _emit C_GOLD  "$(_alac_val normal  yellow  "$_acfg")"
        _emit C_MUTED "$(_alac_val bright  black   "$_acfg")"
        _emit _G1 "$_G1h"; _emit _G2 "$_G2h"; _emit _G3 "$_G3h"; _emit _G4 "$_G4h"
        _mac_ok=1
      fi
    fi
  fi
  # 3. iTerm2
  if (( ! _mac_ok )); then
    _iplist="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
    if [[ -r "$_iplist" ]] && command -v plutil &>/dev/null; then
      _def_guid=$(defaults read com.googlecode.iterm2 "Default Bookmark Guid" 2>/dev/null)
      [[ -z "$_def_guid" ]] && _def_guid=$(plutil -extract "New Bookmarks.0.Guid" raw -o - "$_iplist" 2>/dev/null)
      if [[ -n "$_def_guid" ]]; then
        _icolors=$(plutil -extract "New Bookmarks" json -o - "$_iplist" 2>/dev/null | \
          jq -r --arg g "$_def_guid" '
            .[]|select(.Guid==$g)|
            def c(k):.[(k+" Color")]//{}|[(.["Red Component"]//0),(.["Green Component"]//0),(.["Blue Component"]//0)];
            [c("Foreground"),c("Ansi 5"),c("Ansi 1"),c("Ansi 3"),c("Ansi 8"),c("Ansi 2"),c("Ansi 6"),c("Ansi 3"),c("Ansi 1")]|flatten|@tsv
          ' 2>/dev/null | \
          awk '{for(i=1;i<=NF;i+=3){r=int($i*255+.5);g=int($(i+1)*255+.5);b=int($(i+2)*255+.5);printf "#%02x%02x%02x%s",r,g,b,(i+3<=NF?"\t":"\n")}}')
        if [[ -n "$_icolors" ]]; then
          IFS=$'\t' read -r _t _i _r _g _m _g1 _g2 _g3 _g4 <<< "$_icolors"
          if [[ -n "$_t" && "$_t" != "#000000" ]]; then
            _emit C_TEXT "$_t"; _emit C_IRIS "$_i"; _emit C_ROSE "$_r"
            _emit C_GOLD "$_g"; _emit C_MUTED "$_m"
            _emit _G1 "$_g1"; _emit _G2 "$_g2"; _emit _G3 "$_g3"; _emit _G4 "$_g4"
            _G1h=$_g1; _G2h=$_g2; _G3h=$_g3; _G4h=$_g4
            _mac_ok=1
          fi
        fi
      fi
    fi
  fi
  # 4. Terminal.app — NSColor blobs not parseable from bash; fall through to ANSI
  (( _mac_ok )) || _set_ansi
else
  # ── Linux: noctalia → matugen → wallust → pywal → omarchy → ANSI ────────────
  if [[ -r "$HOME/.config/noctalia/colors.json" ]]; then
    _f="$HOME/.config/noctalia/colors.json"
    _v=$(jq -r '[.mTertiary,.mPrimary,.mSecondary,.mOnSurface,.mOnSurfaceVariant,
                 .mPrimary,.mSecondary,.mTertiary,.mError] | @tsv' "$_f" 2>/dev/null)
    IFS=$'\t' read -r _i _r _g _t _m _g1 _g2 _g3 _g4 <<< "$_v"
    _emit C_IRIS "$_i"; _emit C_ROSE "$_r"; _emit C_GOLD "$_g"
    _emit C_TEXT "$_t"; _emit C_MUTED "$_m"
    _emit _G1 "$_g1"; _emit _G2 "$_g2"; _emit _G3 "$_g3"; _emit _G4 "$_g4"
    _G1h=$_g1; _G2h=$_g2; _G3h=$_g3; _G4h=$_g4
  else
    _f=""
    for _mf in "$HOME/.config/matugen/colors.json" "$HOME/.cache/matugen/colors.json"; do
      [[ -r "$_mf" ]] && { _f=$_mf; break; }
    done
    if [[ -n "$_f" ]]; then
      _v=$(jq -r '[.colors_dark.tertiary//.colors.dark.tertiary//"",
                   .colors_dark.primary//.colors.dark.primary//"",
                   .colors_dark.secondary//.colors.dark.secondary//"",
                   .colors_dark.on_surface//.colors.dark.on_surface//"",
                   .colors_dark.on_surface_variant//.colors.dark.on_surface_variant//"",
                   .colors_dark.error//.colors.dark.error//""] | @tsv' "$_f" 2>/dev/null)
      IFS=$'\t' read -r _i _r _g _t _m _g4 <<< "$_v"
      if [[ -n "$_i" ]]; then
        _emit C_IRIS "$_i"; _emit C_ROSE "$_r"; _emit C_GOLD "$_g"
        _emit C_TEXT "$_t"; _emit C_MUTED "$_m"
        _emit _G1 "$_r"; _emit _G2 "$_g"; _emit _G3 "$_i"; _emit _G4 "$_g4"
        _G1h=$_r; _G2h=$_g; _G3h=$_i; _G4h=$_g4
      else _set_ansi; fi
    elif [[ -r "$HOME/.cache/wallust/colors.json" ]]; then
      _load_pywal "$HOME/.cache/wallust/colors.json" || _set_ansi
    elif [[ -r "$HOME/.cache/wal/colors.json" ]]; then
      _load_pywal "$HOME/.cache/wal/colors.json" || _set_ansi
    elif [[ -r "$HOME/.config/omarchy/current/theme/alacritty.toml" ]]; then
      _tf="$HOME/.config/omarchy/current/theme/alacritty.toml"
      _t=$(_alac_val primary foreground "$_tf")
      if [[ -n "$_t" ]]; then
        _G1h=$(_alac_val normal green  "$_tf"); _G2h=$(_alac_val normal cyan   "$_tf")
        _G3h=$(_alac_val normal yellow "$_tf"); _G4h=$(_alac_val normal red    "$_tf")
        _emit C_TEXT  "$_t"
        _emit C_IRIS  "$(_alac_val normal  blue    "$_tf")"
        _emit C_ROSE  "$(_alac_val normal  magenta "$_tf")"
        _emit C_GOLD  "$(_alac_val normal  yellow  "$_tf")"
        _emit C_MUTED "$(_alac_val bright  black   "$_tf")"
        _emit _G1 "$_G1h"; _emit _G2 "$_G2h"; _emit _G3 "$_G3h"; _emit _G4 "$_G4h"
      else _set_ansi; fi
    else
      _set_ansi
    fi
  fi
fi

grad() {
  local p=$1
  if [[ -z "$_G1h" ]]; then
    if   [[ $p -le 25 ]]; then printf '%b' "$_G1"
    elif [[ $p -le 55 ]]; then printf '%b' "$_G2"
    elif [[ $p -le 85 ]]; then printf '%b' "$_G3"
    else                        printf '%b' "$_G4"; fi
    return
  fi
  if   [[ $p -le 33 ]]; then _lerp "$_G1h" "$_G2h" $(( p * 100 / 33 ))
  elif [[ $p -le 66 ]]; then _lerp "$_G2h" "$_G3h" $(( (p - 33) * 100 / 33 ))
  else                        _lerp "$_G3h" "$_G4h" $(( (p - 66) * 100 / 34 ))
  fi
}
grad_rem() {
  local r=$1 d
  d=$(( (18000 - r) * 100 / 18000 ))
  [[ $d -lt 0 ]] && d=0; [[ $d -gt 100 ]] && d=100
  if [[ -z "$_G1h" ]]; then
    if   [[ $r -gt 13500 ]]; then printf '%b' "$_G1"
    elif [[ $r -gt  8100 ]]; then printf '%b' "$_G2"
    elif [[ $r -gt  2700 ]]; then printf '%b' "$_G3"
    else                          printf '%b' "$_G4"; fi
    return
  fi
  if   [[ $d -le 33 ]]; then _lerp "$_G1h" "$_G2h" $(( d * 100 / 33 ))
  elif [[ $d -le 66 ]]; then _lerp "$_G2h" "$_G3h" $(( (d - 33) * 100 / 33 ))
  else                        _lerp "$_G3h" "$_G4h" $(( (d - 66) * 100 / 34 ))
  fi
}

# ── Build lines ───────────────────────────────────────────────────────────────
# Line 1: distro icon + path — owns the full terminal width
# Line 2: git info, plan, model, usage metrics
# Claude Code appends its own mode indicator on a 3rd line automatically.
read -r _icon < "$HOME/.claude/.distro-icon" 2>/dev/null
[[ -z "$_icon" ]] && _icon=$'\xef\x8c\x9a'
line1="${C_IRIS}${_icon}${_RST} ${C_TEXT}${short_cwd}${_RST}"

line2=""
if [[ -n "$_git_branch" ]]; then
  _gh_icon=$'\xef\x82\x9b'; _tick=$'\xef\x80\x8c'
  line2+="${C_GOLD}${_gh_icon} ${_git_branch}${_RST}"
  if (( ! _git_staged && ! _git_modified && ! _git_untracked )); then
    line2+=" ${_G1}${_tick}${_RST}"
  else
    (( _git_staged ))    && line2+="${C_ROSE}+${_RST}"
    (( _git_modified ))  && line2+="${C_GOLD}!${_RST}"
    (( _git_untracked )) && line2+="${C_MUTED}?${_RST}"
  fi
fi
[[ -n "$plan" ]]      && line2+="  ${C_ROSE}${plan}${_RST}"
[[ -n "$model" ]]     && line2+="  ${C_IRIS}${model}${_RST}"
if [[ -n "$used" ]]; then
  u_int=$(printf '%.0f' "$used")
  line2+=" ${C_MUTED}󰍛 $(grad "$u_int")${u_int}%${_RST} ${C_MUTED}|${_RST}"
fi
w_src="${week:-$used}"
if [[ -n "$w_src" ]]; then
  w_int=$(printf '%.0f' "$w_src")
  line2+=" ${C_MUTED}Week: $(grad "$w_int")${w_int}%${_RST}"
fi
if [[ -n "$five" ]]; then
  f_int=$(printf '%.0f' "$five")
  if [[ -n "$five_reset" ]]; then
    rem=$(( five_reset - ${EPOCHSECONDS:-$(date +%s)} )); [[ "$rem" -lt 0 ]] && rem=0
    line2+=" ${C_MUTED}| Sess: $(grad "$f_int")${f_int}%${_RST}${C_MUTED} ($(grad_rem "$rem")$(printf '%dh%02dm' $((rem/3600)) $(((rem%3600)/60)))${_RST}${C_MUTED})${_RST}"
  else
    line2+=" ${C_MUTED}| Sess: $(grad "$f_int")${f_int}%${_RST}"
  fi
fi
printf "%b\n%b\n" "$line1" "$line2"
