#!/bin/bash
set -euo pipefail
tool_dir=$(cd "$(dirname "$0")" && pwd)
cd "$tool_dir/../../../.."
root=$PWD
cache="$root/.build/midscene"
catalog="$tool_dir/cases.json"
unset E2E_SELECTED_CASE
case "${1:-}" in
  --list)
    printf '编号\t测试场景\t运行模式\t前置条件及影响\n'
    jq -r 'to_entries[] | [.key, .value.title, (.value.profiles | join("/")), .value.setup] | @tsv' "$catalog"
    exit 0 ;;
  --case)
    id=${2:-}
    profiles=$(jq -er --arg id "$id" '.[$id].profiles | select(type == "array") | join(" ")' "$catalog") || {
      echo "未知用例 '$id'，用 make e2e-list 查看编号" >&2; exit 2;
    }
    E2E_PROFILE=${E2E_PROFILE:-${profiles%% *}}
    if [[ " $profiles " != *" $E2E_PROFILE "* ]]; then
      echo "$id 支持的运行模式为 $profiles" >&2; exit 2
    fi
    export E2E_SELECTED_CASE="$id"
    if [[ $id == login-me ]]; then export E2E_LOGIN_ME=1
    elif [[ $id == member-login ]]; then export E2E_LOGIN_ME=0
    fi ;;
esac
profile=${E2E_PROFILE:-guest}
device_profile=$profile
suite=smoke.test.mjs
case "$profile" in
  gesture) device_profile=guest ;;
  daily) device_profile=member; suite=daily.test.mjs ;;
  push) device_profile=member; suite=push.test.mjs ;;
  draft) device_profile=member; suite=draft.test.mjs ;;
  comment) device_profile=member; suite=comment.test.mjs ;;
  logout) suite=logout.test.mjs ;;
  login) device_profile=member; suite=login.test.mjs ;;
  guest|member) ;;
  *) echo "E2E_PROFILE 只接受 guest、member、login、logout、draft、daily、gesture、push 或 comment" >&2; exit 2 ;;
esac
config=${E2E_CONFIG_FILE:-"$HOME/.config/nodeseek/e2e.json"}
settings='{}'
if [[ -e $config || -n ${E2E_CONFIG_FILE:-} ]]; then
  settings=$(jq -ce 'select(type == "object")' "$config") || { echo "无法读取本机 E2E 配置 $config" >&2; exit 2; }
fi
if [[ -z ${E2E_ENV_FILE:-} && -z ${OPENAI_API_KEY:-} ]]; then
  E2E_ENV_FILE=$(jq -r '.envFile // empty' <<<"$settings")
  export E2E_ENV_FILE
fi
if [[ $profile != gesture ]]; then node "$tool_dir/api-key.mjs"; fi
if [[ $device_profile == member || $profile == logout ]]; then
  device_name="NodeSeek E2E Member"
  E2E_MEMBER_USERNAME=${E2E_MEMBER_USERNAME:-$(jq -r '.memberDisplayName // empty' <<<"$settings")}
  member_env_file=$(jq -r '.memberEnvFile // empty' <<<"$settings")
  if [[ -z $E2E_MEMBER_USERNAME && -n $member_env_file ]]; then
    E2E_MEMBER_USERNAME=$(node -e '
      const { parseEnv } = require("node:util");
      const { readFileSync } = require("node:fs");
      const account = parseEnv(readFileSync(process.argv[1], "utf8"));
      if (!account.E2E_MEMBER_USERNAME?.trim()) throw new Error("账号文件缺少 E2E_MEMBER_USERNAME");
      process.stdout.write(account.E2E_MEMBER_USERNAME.trim());
    ' "$member_env_file")
  fi
  export E2E_MEMBER_USERNAME
  if [[ $profile == logout ]]; then device_name="NodeSeek E2E Profile"; fi
  if [[ $profile == login || $profile == logout ]]; then
    [[ -r "$member_env_file" ]] || { echo "登录测试需要可读的 memberEnvFile" >&2; exit 2; }
    export E2E_MEMBER_ENV_FILE="$member_env_file"
  fi
else
  device_name="NodeSeek E2E"
fi
udid=${SIMULATOR_ID:-$(jq -r --arg profile "$device_profile" '.[$profile + "UDID"] // empty' <<<"$settings")}
udid=$(xcrun simctl list -j devices available | jq -er --arg id "$udid" --arg name "$device_name" '
  [.devices[][] | select(if $id != "" then .udid == $id else .name == $name end)]
  | if length == 1 then .[0].udid else error("请核对 " + $name + " 的设备配置或指定 SIMULATOR_ID") end')
if [[ $profile == gesture ]]; then
  command -v axe >/dev/null || { echo "分页手势回放需要 AXe" >&2; exit 2; }
  if [[ ${1:-} == --check ]]; then echo "AXe 与手势设备 $udid 可用"; exit 0; fi
  exec python3 "$tool_dir/paging-gestures.py" "$udid"
fi
if [[ ${1:-} == --check ]]; then
  echo "API Key 已读取，$profile 模拟器 $udid 可用。账号登录状态在运行用例时验证。"
  exit 0
fi

mkdir -p "$cache"
if ! shlock -p "$$" -f "$cache/run.pid"; then
  echo "已有 Midscene 测试在运行，详见 $cache/run.pid" >&2
  exit 1
fi
wda_started=false
cleanup() {
  if $wda_started; then
    xcrun simctl terminate "$udid" com.facebook.WebDriverAgentRunner.xctrunner 2>/dev/null || true
  fi
  rm -f "$cache/run.pid"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
run_dir=$(mktemp -d "$cache/$(date +%Y%m%d-%H%M%S)-$profile-XXXXXX")
echo "模拟器 ${udid}，报告目录 $run_dir"
xcrun simctl bootstatus "$udid" -b
deps_stamp="$tool_dir/node_modules/.nodeseek-lock"
if ! cmp -s "$deps_stamp" "$tool_dir/package-lock.json"; then
  npm ci --prefix "$tool_dir" --no-fund --no-audit > "$run_dir/npm.log" 2>&1 || { tail -30 "$run_dir/npm.log"; exit 1; }
  cp "$tool_dir/package-lock.json" "$deps_stamp"
fi
build() {
  local log="$run_dir/$1.log"
  shift
  xcodebuild -quiet "$@" -destination "platform=iOS Simulator,id=$udid" > "$log" 2>&1 || { tail -40 "$log"; return 1; }
}
build app -project nodeseek.xcodeproj -scheme nodeseek -configuration Debug \
  -derivedDataPath "${E2E_DERIVED_DATA:-$cache/app}" -clonedSourcePackagesDirPath "${SOURCE_PACKAGES:-.build/SourcePackages}" build
xcrun simctl install "$udid" "${E2E_DERIVED_DATA:-$cache/app}/Build/Products/Debug-iphonesimulator/nodeseek.app"

build wda -project "$tool_dir/node_modules/appium-webdriveragent/WebDriverAgent.xcodeproj" \
  -scheme WebDriverAgentRunner -configuration Debug -derivedDataPath "$cache/wda" build-for-testing
xcrun simctl install "$udid" "$cache/wda/Build/Products/Debug-iphonesimulator/WebDriverAgentRunner-Runner.app"
port=${E2E_WDA_PORT:-18100}
if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null; then
  echo "WDA 端口 $port 已占用，请指定 E2E_WDA_PORT" >&2
  exit 1
fi
wda_pid=$(SIMCTL_CHILD_USE_IP=127.0.0.1 SIMCTL_CHILD_USE_PORT="$port" xcrun simctl launch "$udid" com.facebook.WebDriverAgentRunner.xctrunner)
wda_started=true
for i in {1..60}; do
  if curl -fsS --max-time 1 "http://127.0.0.1:$port/status" 2>/dev/null | jq -e '.value.ready == true' >/dev/null; then break; fi
  sleep 1
done
# 确认监听进程属于刚启动的设备，避免操作同机其他模拟器。
lsof -nP -a -p "${wda_pid##*: }" -iTCP:"$port" -sTCP:LISTEN >/dev/null || { echo '目标设备 WDA 未就绪' >&2; exit 1; }

export SIMULATOR_ID="$udid" E2E_WDA_PORT="$port" E2E_PROFILE="$profile" MIDSCENE_RUN_DIR="$run_dir"
node --test --test-reporter=spec --test-reporter-destination=stdout \
  --test-reporter=junit --test-reporter-destination="$run_dir/junit.xml" "$tool_dir/$suite"
# 名称过滤器匹配不到用例时，Node 会把整个文件记为通过。
actual=$(xmllint --xpath 'string((//testcase[not(skipped) and starts-with(@name, "[")])[1]/@name)' "$run_dir/junit.xml")
[[ -n $actual ]] || { echo "没有实际执行任何 $profile 用例，请核对筛选条件与跳过原因" >&2; exit 1; }
if [[ -n ${E2E_SELECTED_CASE:-} ]]; then
  [[ $actual == "[$E2E_SELECTED_CASE] "* ]] || { echo "未执行指定用例 $E2E_SELECTED_CASE" >&2; exit 1; }
fi
