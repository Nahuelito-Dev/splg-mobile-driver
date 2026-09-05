#!/usr/bin/env bash
#
# Arma las notas de la version en NOTES.md y las acumula en CHANGELOG.md.
# Agrupa los commits desde el ultimo tag por tipo de commit convencional.
#
#   VERSION=1.1.0 ./scripts/release-notes.sh
#
# Lo usan las dos vias de release: el workflow de GitHub Actions y el
# finalizador local (splg-release.sh --finish). Una sola fuente de verdad.
#
set -euo pipefail

VERSION="${VERSION:-}"
if [ -z "$VERSION" ]; then
  echo "Falta la variable VERSION." >&2
  exit 1
fi

PREV=$(git tag --sort=-v:refname | head -1 || true)
if [ -n "$PREV" ]; then RANGE="$PREV..HEAD"; else RANGE="HEAD"; fi
echo "Rango de commits: ${RANGE}"

printf '## v%s - %s\n\n' "$VERSION" "$(date +%Y-%m-%d)" > NOTES.md

seccion() {
  local pat="$1" titulo="$2" lineas
  lineas=$(git log $RANGE --no-merges --pretty=format:'%s (%h)' | grep -E "^($pat)(\(.+\))?!?:" || true)
  if [ -n "$lineas" ]; then
    printf '### %s\n\n' "$titulo" >> NOTES.md
    printf '%s\n\n' "$(printf '%s\n' "$lineas" \
      | sed -E 's/^[a-z]+\(([^)]+)\)!?:[[:space:]]*/- **\1:** /; s/^[a-z]+!?:[[:space:]]*/- /')" >> NOTES.md
  fi
}

seccion 'feat'                      'Funcionalidades'
seccion 'fix'                       'Correcciones'
seccion 'perf|refactor'             'Mejoras internas'
seccion 'docs'                      'Documentacion'
seccion 'chore|build|ci|test|style'  'Mantenimiento'

otros=$(git log $RANGE --no-merges --pretty=format:'%s (%h)' \
  | grep -vE "^(feat|fix|perf|refactor|docs|chore|build|ci|test|style)(\(.+\))?!?:" || true)
if [ -n "$otros" ]; then
  printf '### Otros\n\n%s\n\n' "$(printf '%s\n' "$otros" | sed 's/^/- /')" >> NOTES.md
fi

python3 - <<'PY'
import os
notas = open('NOTES.md').read().rstrip() + '\n'
cabecera = '# Changelog\n\nTodas las versiones publicadas de este proyecto.\n\n'
viejo = ''
if os.path.exists('CHANGELOG.md'):
    c = open('CHANGELOG.md').read()
    i = c.find('## ')
    viejo = c[i:] if i != -1 else ''
open('CHANGELOG.md', 'w').write(cabecera + notas + '\n' + viejo)
PY

echo "NOTES.md y CHANGELOG.md actualizados para v${VERSION}"
