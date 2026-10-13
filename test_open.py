import os, tempfile
from open import resolve, key_for, norm_key

cfg = {".pdf": "SumatraPDF.exe", "url": "firefox", "dir": "totalcmd"}

assert key_for("a/b/Doc.PDF") == ".pdf"
assert key_for("https://x.com") == "url"
assert key_for("www.x.com") == "url"
assert key_for(tempfile.gettempdir()) == "dir"
assert key_for("noext") == ""

assert resolve("x.pdf", cfg) == "SumatraPDF.exe"          # config override
assert resolve("x.pdf", cfg, "notepad") == "notepad"      # --with beats config
assert resolve("x.png", cfg) is None                      # Windows default
assert resolve("https://x.com", cfg) == "firefox"
assert resolve(os.getcwd(), cfg) == "totalcmd"

assert norm_key("PDF") == ".pdf" and norm_key(".pdf") == ".pdf" and norm_key("URL") == "url"
print("ok")
