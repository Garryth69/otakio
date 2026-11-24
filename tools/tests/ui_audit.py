"""UI audit: runs the offline simulator scenarios in every theme and every language, collects what the renderer flags
(text leaving the screen, text with too little contrast on what is behind it, Lua errors) and builds one contact
sheet per run for a visual check.

  python tools/tests/ui_audit.py --out <dir> [--jobs 8] [--themes Otakio,Light] [--langs 1,17] [--scenarios alltabs]
"""
import argparse, collections, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
THEMES = ["Otakio", "AMOLED", "Dark", "Sakura", "Light", "Ocean", "Matcha", "Crimson"]
# System language ids (see language.lua): English, Japanese, French, Spanish, German, Italian, Russian,
# Traditional and Simplified Chinese, Brazilian Portuguese
LANGS = {1: "en", 0: "ja", 2: "fr", 3: "es", 4: "de", 5: "it", 8: "ru", 10: "zht", 11: "zhs", 17: "pt"}
# offline scenarios that together reach every tab, dialog and side sheet (name, extra arguments, shot interval)
SCENARIOS = {
    "alltabs": (["--seed-library", "12"], 45),
    "settings": ([], 40),
    "themepick": ([], 30),
    "about": ([], 40),
    "dlviews": ([], 40),
    "extlang": ([], 40),
    "browselang": ([], 40),
    "importempty": ([], 30),
    "extissues": (["--keyboard", "scan"], 40),
    "settingstree": ([], 16),
    "autobackup": ([], 30),
}


def run(job):
    scenario, theme, lang, out = job
    extra, every = SCENARIOS[scenario]
    tag = "%s_%s_%s" % (scenario, theme, LANGS[lang])
    shots = os.path.join(out, "shots", tag)
    cmd = [sys.executable, os.path.join(HERE, "sim.py"), scenario, "--theme", theme, "--lang", str(lang),
           "--shots-every", str(every), "--outdir", shots] + extra
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
    text = p.stdout + p.stderr
    issues = [l.strip()[3:] for l in text.splitlines() if l.strip().startswith("UI ")]
    failed = p.returncode != 0 or "FAILED" in text or "Traceback" in text
    errors = [l for l in text.splitlines() if re.search(r"(?i)lua error|attempt to|FAILED|Traceback", l)][:5]
    sheet(shots, os.path.join(out, tag + ".jpg"))
    return tag, failed, issues, errors


def sheet(shots, dest):
    """Every screenshot of a run side by side at 1/3 size, numbered by frame"""
    if not os.path.isdir(shots):
        return
    files = sorted(f for f in os.listdir(shots) if f.endswith(".png"))
    if not files:
        return
    cols, w, h = 5, 320, 181
    rows = (len(files) + cols - 1) // cols
    im = Image.new("RGB", (cols * w, rows * (h + 14)), (40, 40, 40))
    d = ImageDraw.Draw(im)
    for i, f in enumerate(files):
        x, y = (i % cols) * w, (i // cols) * (h + 14)
        im.paste(Image.open(os.path.join(shots, f)).convert("RGB").resize((w, h)), (x, y + 14))
        d.text((x + 4, y), f.rsplit("_", 1)[-1][:-4], fill=(255, 255, 0))
    im.save(dest, quality=80)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--jobs", type=int, default=8)
    ap.add_argument("--themes", default=",".join(THEMES))
    ap.add_argument("--langs", default=",".join(str(k) for k in LANGS))
    ap.add_argument("--scenarios", default=",".join(SCENARIOS))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    scenarios = args.scenarios.split(",")
    jobs = set()
    for s in scenarios:
        for t in args.themes.split(","):
            jobs.add((s, t, 1, args.out))  # every theme in English
        for l in args.langs.split(","):
            jobs.add((s, "Otakio", int(l), args.out))  # every language in the default theme
    report = collections.OrderedDict()
    with ThreadPoolExecutor(args.jobs) as pool:
        for tag, failed, issues, errors in pool.map(run, sorted(jobs)):
            report[tag] = (failed, issues, errors)
            print(("FAIL " if failed else "ok   ") + tag + ("  %d UI issues" % len(issues) if issues else ""), flush=True)
    with open(os.path.join(args.out, "report.txt"), "w", encoding="utf8") as fh:
        for tag, (failed, issues, errors) in report.items():
            if failed or issues:
                fh.write("== %s%s\n" % (tag, " FAILED" if failed else ""))
                for e in errors:
                    fh.write("   ! " + e + "\n")
                for i in sorted(set(issues)):
                    fh.write("   " + i + "\n")
    print("report:", os.path.join(args.out, "report.txt"))


if __name__ == "__main__":
    main()
