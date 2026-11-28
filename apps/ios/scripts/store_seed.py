"""Seeds a wain-serve home for the App Store and Play screenshots (StoreShotsTests, and the
Android pass in apps/android/fastlane/README.md): two bots, three projects, finished tasks,
routines, and, once the server runs, four real Haiku sessions for the live rows.

    python3 apps/ios/scripts/store_seed.py /private/tmp/wain-store     # prints the token
    WAIN_HOME=/private/tmp/wain-store/home /Applications/Wain.app/Contents/MacOS/wain --serve &
    WAIN_HOME=/private/tmp/wain-store/home python3 apps/ios/scripts/store_seed.py live

`live` starts, through the server's own CLI: a question card, a permission card, a task held
on a 20-minute build (Working), and a two-turn task that reads, edits and runs the tests.
Cards are never logged, so they need live turns, a few Haiku calls in all. The helpers are
redesign_seed.py's, copied, since that script runs on import.

A short root without a symlink: the orchestration socket lives in the home, and the server
canonicalizes paths, so a bot's path through /tmp matches no chat.
"""
import json, os, shutil, subprocess, sys, time, uuid
from datetime import datetime, timedelta, timezone

now = datetime.now(timezone.utc)
stamp = lambda d: d.isoformat(timespec="milliseconds").replace("+00:00", "Z")
TOKEN = "2026" * 16


def write_log(home, sid, turns, start):
    with open(f"{home}/sessions/{sid}.jsonl", "w") as f:
        seq = 0
        for i, (prompt, reply) in enumerate(turns):
            for p in ({"type": "user_message", "text": prompt, "images": [], "issues": [], "baseline": None,
                       "queued": False, "from": None, "cwd": None},
                      {"type": "assistant_text", "block": {"messageId": f"msg_{i}", "index": 0}, "text": reply},
                      {"type": "turn_completed", "status": "success", "stopReason": "end_turn", "finalText": reply}):
                f.write(json.dumps({"id": str(uuid.uuid4()), "sessionId": sid, "harness": "claude_code", "seq": seq,
                                    "ts": stamp(start + timedelta(minutes=i, seconds=seq)), "turnId": None,
                                    "subagent": None, "payload": p}, separators=(",", ":")) + "\n")
                seq += 1


def session(home, cwd, title, turns, ago, status="idle"):
    sid = str(uuid.uuid4())
    modified = now - ago
    write_log(home, sid, turns, modified - timedelta(minutes=len(turns)))
    return {"sessionId": sid, "harness": "claude_code", "cwd": cwd, "projectPath": cwd, "branch": "main",
            "worktreeName": None, "worktreeRemoved": False, "title": title, "titleLocked": True,
            "model": "haiku", "effort": "low", "permissionMode": "auto", "fast": False, "status": status,
            "forkFrom": None, "threadId": None, "issues": [], "parentSessionId": None,
            "created": stamp(modified - timedelta(hours=1)), "modified": stamp(modified), "archived": False,
            "pinned": False, "hidden": False, "aside": False, "continueOff": False}


def git(cwd, *args):
    subprocess.run(["git", "-c", "user.name=Wain", "-c", "user.email=shots@example.com", *args],
                   cwd=cwd, check=True, capture_output=True)


def draft(prompt, project, mode):
    return {"id": str(uuid.uuid4()), "prompt": prompt, "projectPath": project, "harness": "claude_code",
            "model": "haiku", "effort": None, "permissionMode": mode, "fast": False, "useWorktree": False,
            "created": stamp(datetime.now(timezone.utc))}


def bot(home, name, shape, hue, turns, ago):
    bid = str(uuid.uuid4())
    path = f"{home}/bots/{bid}"
    os.makedirs(f"{path}/memory")
    open(f"{path}/AGENTS.md", "w").write(f"# {name}\n")
    return ({"id": bid, "name": name, "path": path, "created": stamp(now - timedelta(days=9)),
             "avatar": {"shape": shape, "hue": hue}}, session(home, path, name, turns, ago))


def next_at(schedule):
    """The schedule's next local `at` after now, past today so no run fires while shots are taken."""
    hour, minute = map(int, schedule["at"].split(":"))
    local = datetime.now().astimezone()
    day = (local + timedelta(days=1)).replace(hour=hour, minute=minute, second=0, microsecond=0)
    while schedule["days"] and day.weekday() not in schedule["days"]:
        day += timedelta(days=1)
    return day.astimezone(timezone.utc)


def routine(bot_id, name, prompt, schedule, ran, paused=False):
    return {"id": str(uuid.uuid4()), "botId": bot_id, "name": name, "prompt": prompt, "schedule": schedule,
            "paused": paused, "created": stamp(now - timedelta(days=6)),
            "nextRun": None if paused else stamp(next_at(schedule)),
            "lastResult": {"outcome": "replied", "text": ran, "at": stamp(now - timedelta(hours=3))}}


# Started through the server's CLI, each a real conversation on its draft's stance.
LIVE = [
    ("Settings: dark mode toggle", "storefront", "manual",
     "Call the AskUserQuestion tool once, with one question: \"Should the dark mode toggle follow the "
     "system setting by default?\" with the options \"Follow the system\" and \"Start in light\". "
     "Once answered, reply with the single word: thanks."),
    ("Retry API calls with backoff", "api", "manual",
     "Run the shell command `pnpm test` in this folder, then reply with the single word: done."),
    ("Checkout button on small screens", "storefront", "bypassPermissions",
     "Run the shell command `./scripts/build.sh` in this folder and wait for it to finish, "
     "then reply with the single word: built."),
    ("Raise the retry limit to 5", "api", "bypassPermissions",
     "Uploads give up too soon on slow networks. Read src/retry.js and tell me why, in two sentences."),
]
# Sent to the last task once its first turn ends, so its transcript holds two real turns.
FOLLOW_UP = "Raise the limit to 5, update the test to match, and run the tests. Reply in one sentence."


def status(sid):
    out = subprocess.run(["wain", "session", "ls", "--all", "--json"], capture_output=True, text=True).stdout
    return next((s.get("status") for s in json.loads(out or "[]") if s.get("sessionId", s.get("id")) == sid), None)


def settle(sid, limit=180):
    for _ in range(limit // 3):
        if status(sid) not in ("in_progress", None):
            return
        time.sleep(3)
    sys.exit(f"{sid} still running after {limit}s")

if sys.argv[1:2] == ["live"]:
    home = os.environ["WAIN_HOME"]
    paths = {p["name"]: p["path"] for p in json.load(open(f"{home}/projects.json"))}
    for title, project, mode, prompt in LIVE:
        held = json.load(open(f"{home}/drafts.json"))
        d = draft(prompt, paths[project], mode)
        json.dump(held + [d], open(f"{home}/drafts.json", "w"))
        out = subprocess.run(["wain", "draft", "start", d["id"]], capture_output=True, text=True, check=True).stdout
        sid = next(w for w in out.split() if len(w) == 36 and w.count("-") == 4)
        subprocess.run(["wain", "session", "rename", sid, title], check=True, capture_output=True)
        print(title, sid)
        time.sleep(2)  # each lands in Home in order
    settle(sid)
    subprocess.run(["wain", "session", "send", sid, FOLLOW_UP], check=True, capture_output=True)
    time.sleep(5)
    settle(sid)
    print("follow-up done")
    sys.exit()

root = sys.argv[1]
home, repos = f"{root}/home", f"{root}/repos"
shutil.rmtree(root, ignore_errors=True)
os.makedirs(f"{home}/sessions")
open(f"{home}/serve-token", "w").write(TOKEN)
os.chmod(f"{home}/serve-token", 0o600)

files = {
    "storefront": {"README.md": "# Storefront\n", "src/checkout.tsx": "export const Checkout = () => null;\n",
                   "scripts/build.sh": "#!/bin/sh\necho 'Building storefront…'\nsleep 1200\n"},
    "api": {"README.md": "# API\n",
            "package.json": '{"name": "api", "type": "module", "scripts": {"test": "node --test"}}\n',
            "src/retry.js": "export const MAX_RETRIES = 3;\n\n"
                            "/** Waits 200ms, then doubles, between tries. */\n"
                            "export async function withRetry(call, wait = (ms) => new Promise((r) => setTimeout(r, ms))) {\n"
                            "  for (let attempt = 0; ; attempt++) {\n"
                            "    try {\n      return await call();\n    } catch (err) {\n"
                            "      if (attempt + 1 >= MAX_RETRIES) throw err;\n"
                            "      await wait(200 * 2 ** attempt);\n    }\n  }\n}\n",
            "test/retry.test.js": "import { test } from 'node:test';\nimport assert from 'node:assert';\n"
                                  "import { MAX_RETRIES, withRetry } from '../src/retry.js';\n\n"
                                  "test('gives up after MAX_RETRIES', async () => {\n  let calls = 0;\n"
                                  "  await assert.rejects(withRetry(async () => { calls++; throw new Error('down'); }, async () => {}));\n"
                                  "  assert.strictEqual(calls, 3);\n});\n"},
    "ios-app": {"README.md": "# iOS app\n"},
}
projects = []
for name, tree in files.items():
    repo = f"{repos}/{name}"
    for rel, text in tree.items():
        os.makedirs(os.path.dirname(f"{repo}/{rel}"), exist_ok=True)
        open(f"{repo}/{rel}", "w").write(text)
    if name == "storefront":
        os.chmod(f"{repo}/scripts/build.sh", 0o755)
    git(repo, "init", "-q", "-b", "main")
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "First")
    projects.append(repo)
json.dump([{"path": p, "name": os.path.basename(p), "lastSelected": stamp(now - timedelta(minutes=i))}
           for i, p in enumerate(projects)], open(f"{home}/projects.json", "w"))
json.dump([], open(f"{home}/drafts.json", "w"))

WAIN_TURNS = [
    ("What shipped in 2.3?",
     "2.3 went out on Monday: offline drafts, faster sync, and the new settings page. Fourteen tasks went into it."),
    ("Is anyone still on search?",
     "No. **Faster search** finished yesterday and its pull request is merged. Nothing else on search is open."),
    ("Is the nightly build green?",
     "Yes. The nightly build passed at 06:10, all 412 tests, and no deploy is waiting."),
    ("What's waiting on me this morning?",
     "Two things. **Settings: dark mode toggle** asks whether the toggle should follow the system by "
     "default, and **Retry API calls with backoff** wants to run `pnpm test`.\n\nThe rest finished "
     "overnight: the reconnect fix and the 2.4 release notes are ready to read."),
    ("Start a task on storefront: keep the checkout button visible on small screens.",
     "Started **Checkout button on small screens** on storefront, with Claude Code. I'll tell you when "
     "it has something to show."),
]
wain, wain_chat = bot(home, "Wain", "circle", 225.0, WAIN_TURNS, timedelta(minutes=2))
ops, ops_chat = bot(home, "Ops", "cloud", 185.0, [
    ("Anything on fire?", "Nothing on fire. CI on main is green and the API's error rate is flat."),
    ("Ship 2.4 to beta once the notes are in.", "Done: 2.4 is out on the beta channel."),
], timedelta(minutes=34))
json.dump([wain, ops], open(f"{home}/bots.json", "w"))

index = [
    wain_chat, ops_chat,
    session(home, f"{repos}/api", "Fix flaky reconnect test",
            [("The reconnect test fails one run in ten. Find out why.", "It races the backoff timer."),
             ("Fix it.", "Fixed: the test now waits on the reconnect event instead of a sleep.")],
            timedelta(minutes=50), status="completed"),
    session(home, f"{repos}/storefront", "Write release notes for 2.4",
            [("Write the release notes for 2.4.", "Written, in CHANGELOG.md: checkout on small screens, "
              "faster search, and two fixes.")], timedelta(hours=2), status="completed"),
    session(home, f"{repos}/ios-app", "Check the Xcode version",
            [("Which Xcode is installed?", "Xcode 26.2, build 17C52.")], timedelta(hours=5)),
]
json.dump(index, open(f"{home}/sessions/index.json", "w"))

json.dump([
    routine(wain["id"], "Morning summary", "Tell me what finished overnight and what waits on me.",
            {"at": "08:30", "days": []}, "Two tasks wait on you; three finished."),
    routine(ops["id"], "Nightly build check", "Check the nightly build and say only if it failed.",
            {"at": "06:00", "days": []}, "The nightly build passed."),
    routine(ops["id"], "Dependency updates", "List outdated dependencies on storefront and api.",
            {"at": "09:00", "days": [0]}, "Three minor updates on storefront."),
    routine(ops["id"], "Watch CI on main", "Tell me when CI on main goes red.",
            {"everyMinutes": 30, "days": []}, "CI on main is green.", paused=True),
], open(f"{home}/routines.json", "w"))

print(TOKEN)
