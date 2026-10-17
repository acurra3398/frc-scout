"""Adds a release to the top of source.json (SideStore treats the first version as the latest)."""
import json, os, sys
from datetime import datetime, timezone

version, build, notes, size = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
repo = os.environ.get("GITHUB_REPOSITORY", "acurra3398/frc-scout")
path = "updates/source.json"
source = json.load(open(path))
app = source["apps"][0]
app["versions"] = [v for v in app["versions"] if v["version"] != version]
app["versions"].insert(0, {
    "version": version,
    "buildVersion": build,
    "date": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "localizedDescription": notes,
    "downloadURL": f"https://github.com/{repo}/releases/download/v{version}/Scout.ipa",
    "size": size,
    "minOSVersion": "17.0",
})
json.dump(source, open(path, "w"), indent=2, ensure_ascii=False)
