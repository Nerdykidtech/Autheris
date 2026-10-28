"""Renders the header and search-results images for every App Store language."""
import html, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1]
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# locale: (lang, header line, search headline, device line)
TEXT = {
    "en-US":   ("en", "Every 2FA code, one tap away.", "Your 2FA codes, one tap away.",
                "iPhone, iPad, Mac and Apple Watch"),
    "de-DE":   ("de", "Jeder 2FA-Code, nur einen Tipp entfernt.", "Ihre 2FA-Codes, nur einen Tipp entfernt.",
                "iPhone, iPad, Mac und Apple Watch"),
    "es-ES":   ("es", "Cada código 2FA, a un toque.", "Tus códigos 2FA, a un toque.",
                "iPhone, iPad, Mac y Apple Watch"),
    "fr-FR":   ("fr", "Chaque code 2FA, à portée de doigt.", "Vos codes 2FA, à portée de doigt.",
                "iPhone, iPad, Mac et Apple Watch"),
    "pt-BR":   ("pt", "Cada código 2FA a um toque.", "Seus códigos 2FA a um toque.",
                "iPhone, iPad, Mac e Apple Watch"),
    "ja":      ("ja", "すべての2FAコードを、ワンタップで。", "2FAコードを、\nワンタップで。",
                "iPhone、iPad、Mac、Apple Watch"),
    "zh-Hans": ("zh-Hans", "每个 2FA 验证码，一触即得。", "你的 2FA 验证码，\n一触即得。",
                "iPhone、iPad、Mac 和 Apple Watch"),
}

# Shrinks a headline until it fits its box, so longer languages stay inside the safe area.
FIT = """<script>
function fit(el, w, h) {
  let s = parseFloat(getComputedStyle(el).fontSize);
  while ((el.scrollWidth > w || el.offsetHeight > h) && s > 20) { s -= 2; el.style.fontSize = s + 'px'; }
}
</script>"""

def page(kind, lang, header, search, devices):
    src = open(os.path.join(HERE, f"{kind}.html"), encoding="utf-8").read()
    src = src.replace('<html>', f'<html lang="{lang}">')
    # Japanese and Chinese: the heaviest system faces, and no breaks inside words.
    cjk = {"ja": '"Hiragino Sans", "Hiragino Kaku Gothic ProN"', "zh-Hans": '"PingFang SC"'}.get(lang)
    if cjk:
        src = src.replace("</style>", f"h1, p.sub {{ font-family: -apple-system, {cjk}, sans-serif; word-break: keep-all; }} h1 {{ font-weight: 900; white-space: nowrap; }}</style>")
    if kind == "header":
        src = src.replace("Every 2FA code, one tap away.", html.escape(header))
        src = src.replace("</body>", FIT + "<script>fit(document.querySelector('h1'), 1300, 100)</script></body>")
        src = src.replace("h1 { position", "h1 { white-space: nowrap; width: max-content; margin: 0 auto; position")
    else:
        src = src.replace("Your 2FA codes, one tap away.", html.escape(search).replace("\n", "<br>"))
        src = src.replace("iPhone, iPad, Mac and Apple&nbsp;Watch", html.escape(devices))
        src = src.replace("</body>", FIT + "<script>fit(document.querySelector('h1'), 940, 560)</script></body>")
    path = os.path.join(HERE, f"_{kind}-{lang}.html")
    open(path, "w", encoding="utf-8").write(src)
    return path

for locale, (lang, header, search, devices) in TEXT.items():
    for kind, size, name in (("header", "1920,823", "header-3840x1646"),
                             ("search", "1920,1280", "search-3840x2560")):
        dest = os.path.join(OUT, f"{locale}-{name}.png")
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--force-device-scale-factor=2", f"--window-size={size}",
                        "--virtual-time-budget=2000", f"--screenshot={dest}",
                        "file://" + page(kind, lang, header, search, devices)],
                       check=True, capture_output=True)
        print(dest)
