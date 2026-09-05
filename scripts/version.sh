#!/usr/bin/env bash
#
# Maneja el numero de version del proyecto, sea cual sea su ecosistema.
#
#   ./scripts/version.sh actual     imprime la version declarada hoy
#   ./scripts/version.sh siguiente  calcula la proxima segun los commits nuevos
#   ./scripts/version.sh fijar X    escribe X en el archivo que corresponda
#
# El salto lo deciden los commits desde el ultimo tag, en convencion
# Conventional Commits:
#
#   BREAKING CHANGE en el cuerpo, o un "!" antes de los dos puntos  -> mayor
#   algun commit feat:                                              -> menor
#   cualquier otra cosa                                             -> parche
#
set -euo pipefail

tipo_proyecto() {
  if   [ -f pubspec.yaml ];  then echo pubspec
  elif [ -f package.json ];  then echo npm
  elif [ -f VERSION ];       then echo archivo
  else echo "No encuentro pubspec.yaml, package.json ni VERSION." >&2; exit 1
  fi
}

version_actual() {
  case "$(tipo_proyecto)" in
    pubspec) grep -m1 '^version:' pubspec.yaml | sed 's/^version:[[:space:]]*//; s/+.*//' ;;
    npm)     node -p "require('./package.json').version" ;;
    archivo) tr -d '[:space:]' < VERSION ;;
  esac
}

# Las apps Flutter llevan +buildNumber, que Android usa como versionCode.
build_actual() {
  [ "$(tipo_proyecto)" = "pubspec" ] || { echo ""; return; }
  grep -m1 '^version:' pubspec.yaml | sed -n 's/.*+//p'
}

fijar_version() {
  local v="$1"
  case "$(tipo_proyecto)" in
    pubspec)
      local b; b="$(build_actual)"
      if [ -n "$b" ]; then v="$v+$(( b + 1 ))"; fi
      perl -pi -e "s/^version:.*/version: $v/" pubspec.yaml
      ;;
    npm)
      node -e "const f='package.json',j=require('./'+f);j.version='$v';require('fs').writeFileSync(f,JSON.stringify(j,null,2)+'\n')"
      [ -f package-lock.json ] && npm install --package-lock-only --silent >/dev/null 2>&1 || true
      ;;
    archivo) echo "$v" > VERSION ;;
  esac
}

# Commits desde el ultimo tag, ignorando los que genera la propia automatizacion.
commits_nuevos() {
  local prev; prev="$(git tag --sort=-v:refname | head -1 || true)"
  local rango; if [ -n "$prev" ]; then rango="$prev..HEAD"; else rango="HEAD"; fi
  git log "$rango" --no-merges --pretty=format:'%s%n%b%n---FIN---' | grep -v '\[skip ci\]' || true
}

siguiente_version() {
  local prev base salto
  prev="$(git tag --sort=-v:refname | head -1 || true)"
  base="${prev#v}"
  [ -z "$base" ] && base="$(version_actual)"

  local cuerpo; cuerpo="$(commits_nuevos)"
  if [ -z "$(printf '%s' "$cuerpo" | tr -d '[:space:]-FIN')" ]; then
    echo ""   # no hay nada nuevo que publicar
    return
  fi

  if   printf '%s' "$cuerpo" | grep -qE '^BREAKING CHANGE|^[a-z]+(\(.+\))?!:'; then salto=mayor
  elif printf '%s' "$cuerpo" | grep -qE '^feat(\(.+\))?!?:';                    then salto=menor
  else salto=parche
  fi

  IFS=. read -r ma mi pa <<< "$base"
  case "$salto" in
    mayor)  echo "$(( ma + 1 )).0.0" ;;
    menor)  echo "${ma}.$(( mi + 1 )).0" ;;
    parche) echo "${ma}.${mi}.$(( pa + 1 ))" ;;
  esac
}

case "${1:-}" in
  actual)    version_actual ;;
  siguiente) siguiente_version ;;
  fijar)     [ -n "${2:-}" ] || { echo "Falta la version." >&2; exit 1; }; fijar_version "$2" ;;
  *) echo "Uso: $0 {actual|siguiente|fijar <version>}" >&2; exit 1 ;;
esac
