"""Generate browser authentication file for ytmusicapi using cURL or raw headers."""
import sys
import os
import re
# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from ytmusicapi import setup

print("""
╔══════════════════════════════════════════════════════════════════════════╗
║  CRÉATION DU FICHIER D'AUTHENTIFICATION BROWSER                          ║
╚══════════════════════════════════════════════════════════════════════════╝

📋 INSTRUCTIONS:

1. Ouvre https://music.youtube.com dans Chrome/Firefox
2. Assure-toi d'être connecté avec le compte ZacoFunKy
3. Ouvre DevTools (F12)
4. Va dans Network (Réseau)
5. Filtre par "browse"
6. Rafraîchis (F5)
7. Clique sur une requête "browse"
8. Copie TOUS les Request Headers (depuis la première ligne jusqu'à la dernière)

Exemple de format:
:authority: music.youtube.com
:method: POST
:path: /youtubei/v1/browse
accept: */*
authorization: SAPISIDHASH ...
cookie: VISITOR_INFO1_LIVE=...; PREF=...
...

""")

print("Colle les Request Headers ou la commande cURL ci-dessous, puis ENTRÉE deux fois:\n")
print("=" * 78)

headers_lines = []
while True:
    try:
        line = input()
        if not line.strip():
            break
        headers_lines.append(line)
    except EOFError:
        break

text = "\n".join(headers_lines)

# If user pasted a curl command, extract headers and cookie
if text.strip().lower().startswith("curl "):
    lines = text.splitlines()
    hdrs = []
    cookie_val = None
    for ln in lines:
        m = re.search(r"-H\s+'([^:]+):\s*(.*)'", ln)
        if m:
            key = m.group(1).strip()
            val = m.group(2).strip()
            hdrs.append(f"{key}: {val}")
        m2 = re.search(r"-b\s+'(.+?)'", ln)
        if m2:
            cookie_val = m2.group(1).strip()
    if cookie_val:
        # Ensure cookie header present
        hdrs.append(f"cookie: {cookie_val}")
    text = "\n".join(hdrs)

headers_text = text

if not headers_text.strip():
    print("\n❌ Aucun header fourni!")
    sys.exit(1)

print("\n📝 Headers reçus, création du fichier...\n")

# Output to project root (parent of scripts/)
output_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'browser_auth_new.json')

try:
    setup(filepath=output_path, headers_raw=headers_text)
    print(f"✅ Fichier {output_path} créé!\n")
    print("Teste maintenant avec:")
    print("  python .\\scripts\\test_full_auth.py")
except Exception as e:
    print(f"❌ Erreur: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
