"""open - open files, folders and URLs with the right app. Your overrides first, Windows default otherwise."""
import argparse, json, os, subprocess, sys
from pathlib import Path

CONFIG = Path(os.environ.get("APPDATA", Path.home())) / "open" / "config.json"


def load():
    try:
        return json.loads(CONFIG.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}


def save(cfg):
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    CONFIG.write_text(json.dumps(cfg, indent=2), encoding="utf-8")


def is_url(target):
    return "://" in target or target.lower().startswith(("mailto:", "www."))


def key_for(target):
    """Config key: 'url', 'dir', or the lowercase extension ('.pdf')."""
    if is_url(target):
        return "url"
    if os.path.isdir(target):
        return "dir"
    return Path(target).suffix.lower()


def norm_key(k):
    k = k.lower()
    return k if k in ("url", "dir") or k.startswith(".") else "." + k


def resolve(target, cfg, with_app=None):
    """App to use for target, or None for the Windows default."""
    return with_app or cfg.get(key_for(target))


def launch(target, app):
    if is_url(target) and target.lower().startswith("www."):
        target = "https://" + target
    if app:
        # ShellExecute finds apps by full path, PATH, or App Paths (firefox, chrome, notepad...)
        os.startfile(app, arguments=subprocess.list2cmdline([target]))
    else:
        os.startfile(target)


def main(argv=None):
    p = argparse.ArgumentParser(prog="open", description=__doc__)
    p.add_argument("targets", nargs="*", help="files, folders or URLs")
    p.add_argument("--with", dest="with_app", metavar="APP", help="use APP this one time")
    p.add_argument("--set", nargs=2, metavar=("EXT", "APP"), help="always open EXT (.pdf, url, dir) with APP")
    p.add_argument("--unset", metavar="EXT", help="remove an override")
    p.add_argument("--list", action="store_true", help="show overrides")
    a = p.parse_args(argv)

    cfg = load()
    if a.set:
        cfg[norm_key(a.set[0])] = a.set[1]
        save(cfg)
        print(f"{norm_key(a.set[0])} -> {a.set[1]}")
    if a.unset:
        if cfg.pop(norm_key(a.unset), None) is None:
            print(f"no override for {norm_key(a.unset)}")
        save(cfg)
    if a.list:
        for k, v in sorted(cfg.items()):
            print(f"{k:8} {v}")
        if not cfg:
            print(f"no overrides ({CONFIG})")
    if not (a.targets or a.set or a.unset or a.list):
        p.print_help()

    rc = 0
    for t in a.targets:
        if not is_url(t):
            if not os.path.exists(t):
                print(f"open: not found: {t}", file=sys.stderr)
                rc = 1
                continue
            t = os.path.abspath(t)
        app = resolve(t, cfg, a.with_app)
        try:
            launch(t, app)
        except OSError as e:
            print(f"open: can't open {t} with {app or 'default app'}: {e.strerror or e}", file=sys.stderr)
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
