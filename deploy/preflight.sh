#!/usr/bin/env bash
# 適用の前に、マニフェストが参照する Secret とキーが名前空間にそろっているかを確かめる。
# Secret かキーが無いまま適用すると、Pod が CreateContainerConfigError か ImagePullBackOff で起動しない。
# 集める正本はマニフェストの secretKeyRef と imagePullSecrets で、手で書いた一覧を持たない。
# deploy/README.md の Secret の表と、この一覧が一致することは spec/platform/deploy_manifests_spec.rb が確かめる。
#
#   deploy/preflight.sh                               そろっているかを確かめる
#   deploy/preflight.sh --list                        集めた名前とキーを並べるだけ（kubectl を使わない）
#   KUBECTL="ssh raspi kubectl" deploy/preflight.sh   手元から Raspberry Pi の k3s を見る
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
namespace="factory-ops-rails"
kubectl_cmd=${KUBECTL:-kubectl}

# secretKeyRef の次の 2 行（name と key の順に書く）と、imagePullSecrets の名前を拾う。imagePullSecrets のキーは種類で決まる
required=$(
  {
    grep -h -A2 'secretKeyRef:' "$here"/*.yaml | awk '$1 == "name:" { name = $2 } $1 == "key:" { print name, $2 }'
    grep -h -A1 'imagePullSecrets:' "$here"/*.yaml | awk '$1 == "-" && $2 == "name:" { print $3, ".dockerconfigjson" }'
  } | sort -u
)

if [ -z "$required" ]; then
  echo "preflight: マニフェストから Secret の参照を集められなかった（grep の前提が変わった）" >&2
  exit 1
fi

if [ "${1:-}" = "--list" ]; then
  echo "参照する Secret とキー（名前空間 ${namespace}）:"
  echo "$required" | sed 's/^/  - /'
  exit 0
fi

# 繋がっていないクラスタを見て、全部が無いと報告しないように、先に名前空間を確かめる
if ! $kubectl_cmd get namespace "$namespace" </dev/null >/dev/null 2>&1; then
  echo "preflight: 名前空間 ${namespace} が見つからない。クラスタに繋がっていないか、名前空間を作っていない（deploy/README.md「Secret」）" >&2
  exit 1
fi

missing=()
while read -r name key; do
  # describe はキーと大きさだけを出し、値を出さない。</dev/null が無いと、KUBECTL の ssh が標準入力を読み、ループが 1 件目で終わる
  if $kubectl_cmd describe secret "$name" -n "$namespace" </dev/null 2>/dev/null | grep -q "^${key}:"; then
    echo "  OK      $name $key"
  else
    echo "  MISSING $name $key"
    missing+=("$name $key")
  fi
done <<<"$required"

if [ ${#missing[@]} -gt 0 ]; then
  echo "preflight: Secret のキーが ${#missing[@]} 件足りない。入れ方は deploy/README.md「Secret」にある" >&2
  exit 1
fi

echo "preflight: 参照する Secret とキーはすべてある"
