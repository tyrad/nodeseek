"""从 App-hosted XCTest 接收屏幕坐标，通过 AXe 在同一模拟器发出真实拖动。"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

device = sys.argv[1]
root = Path.cwd()
reports = root / ".build" / "detail-paging-e2e"
reports.mkdir(parents=True, exist_ok=True)
run = Path(tempfile.mkdtemp(prefix="gesture-", dir=reports))
print(f"模拟器 {device}，报告目录 {run}", flush=True)
env = {**os.environ, "TEST_RUNNER_NODESEEK_PAGING_RUN": str(run)}
with (run / "xcode.log").open("w") as log:
    with subprocess.Popen(["make", "xcode-test-class", "TEST=DetailPagingGestureTests",
                           f"SIMULATOR_ID={device}"], env=env, stdout=log, stderr=subprocess.STDOUT) as proc:
        sent = set()
        command = run / "drag.json"
        while proc.poll() is None:
            if command.exists():
                drag = json.loads(command.read_text())
                phase = drag["phase"]
                if phase not in sent:
                    sent.add(phase)
                    if phase == "refresh":
                        subprocess.run(["axe", "tap", "--udid", device, "--tap-style", "physical",
                                        "-x", str(drag["x"]), "-y", str(drag["y"])], check=True)
                        continue
                    subprocess.run(["axe", "swipe", "--udid", device, "--duration", "1.0",
                                    "--start-x", str(drag["x"]), "--end-x", str(drag["x"]),
                                    "--start-y", str(drag["from"]), "--end-y", str(drag["to"])], check=True)
            time.sleep(0.05)
if proc.returncode or sent != {"timeout", "retry", "last", "refresh"} or not (run / "measurements.json").exists():
    print((run / "xcode.log").read_text()[-3500:], file=sys.stderr)
    sys.exit("分页时序未通过，请检查本轮 xcresult 和已完成的手势 " + str(sorted(sent)))
print((run / "measurements.json").read_text())
